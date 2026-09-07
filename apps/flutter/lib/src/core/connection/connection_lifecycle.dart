import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/app_lifecycle.dart';
import 'connection_controller.dart';
import 'connection_target.dart';
import 'connection_target_provider.dart';

/// Test-observable lifecycle state, defaulting to `resumed` (foreground).
///
/// Production updates arrive from [AppLifecycleObserver] (WidgetsBinding).
/// Tests override this provider's state directly to simulate `paused`/
/// `resumed` without a real OS background transition.
final appLifecycleStateProvider = StateProvider<AppLifecycleState>(
  (ref) => AppLifecycleState.resumed,
);

/// Wires [AppLifecycleState] → [FlutterConnectionController] suspend/resume.
///
/// Mobile lifecycle handling is gated behind [shouldApplyMobileLifecycle]:
/// - RemoteTarget on Android/iOS: `paused` suspends, `resumed` resumes with a
///   fresh generation, new WS ticket, and authoritative resync.
/// - LocalTarget, Web, macOS: no-op, preserving existing behavior.
/// - `inactive` and `detached` are observed but do not drive network state
///   (inactive is transient; detached is termination).
///
/// Does not treat every lifecycle event as a network failure: only `paused`
/// stops the loop and only `resumed` restarts it.
final connectionLifecycleProvider = Provider<void>((ref) {
  // Edge-triggered handling via listen so the provider does not rebuild on
  // target changes and accumulate listeners.
  ref.listen<AppLifecycleState>(appLifecycleStateProvider, (prev, next) {
    final target = ref.read(connectionTargetProvider);
    final controller = ref.read(flutterConnectionProvider);
    if (!shouldApplyMobileLifecycle(target)) return;

    switch (next) {
      case AppLifecycleState.paused:
        if (controller.isRunning) {
          controller.suspend();
        }
        break;
      case AppLifecycleState.resumed:
        // Resume always creates a fresh generation, even if the previous
        // generation was already stopped by a network loss — the resume
        // handshake re-validates hostId, ticket, and authoritative state.
        if (!controller.isRunning) {
          controller.resume();
        }
        break;
      case AppLifecycleState.inactive:
        // Transient (e.g., incoming call, PiP) — do not suspend, do not
        // treat as a network failure. Keep the current generation alive so a
        // quick inactive→resumed without pause does not churn.
        break;
      case AppLifecycleState.detached:
        // App termination — stop the loop cleanly.
        if (controller.isRunning) {
          controller.stop();
        }
        break;
      case AppLifecycleState.hidden:
        // Flutter 3.13+ hidden: treat like paused for mobile remote clients
        // to close sockets when the app is no longer visible, but only when
        // the platform seam says we are on mobile. Currently no-op to avoid
        // double-suspend with the paused handler; hidden→paused is common.
        break;
    }
  });

  // Handle target flips while the lifecycle is already paused (e.g., pairing
  // completes while backgrounded). If the new target is remote+mobile and the
  // lifecycle is paused, suspend the now-remote controller.
  ref.listen<ConnectionTarget>(connectionTargetProvider, (prev, next) {
    final lifecycle = ref.read(appLifecycleStateProvider);
    final controller = ref.read(flutterConnectionProvider);
    if (lifecycle == AppLifecycleState.paused &&
        shouldApplyMobileLifecycle(next) &&
        controller.isRunning) {
      controller.suspend();
    }
  });

  // Initial paused handling for tests that override the state before this
  // provider is first watched.
  final initialLifecycle = ref.read(appLifecycleStateProvider);
  final initialTarget = ref.read(connectionTargetProvider);
  final initialController = ref.read(flutterConnectionProvider);
  if (initialLifecycle == AppLifecycleState.paused &&
      shouldApplyMobileLifecycle(initialTarget) &&
      initialController.isRunning) {
    scheduleMicrotask(initialController.suspend);
  }
});

/// WidgetsBinding observer that forwards OS lifecycle events into
/// [appLifecycleStateProvider], keeping the handler pure and testable.
///
/// Mount once near the root (in [_buildRoot]) so the provider-based handler
/// above drives suspend/resume. Web/macOS still mounts this widget but the
/// handler no-ops behind the seam.
class AppLifecycleObserver extends ConsumerStatefulWidget {
  const AppLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleObserver> createState() =>
      _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Forward to the test-observable provider; the connection handler
    // filters by the mobile seam before acting.
    ref.read(appLifecycleStateProvider.notifier).state = state;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
