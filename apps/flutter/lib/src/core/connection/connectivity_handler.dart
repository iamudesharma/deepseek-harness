import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/connectivity.dart';
import '../../platform/connectivity_plus_adapter.dart';
import 'connection_controller.dart';

/// Provider for the platform connectivity monitor.
///
/// Web returns a no-op (always online); tests override with a fake.
final connectivityMonitorProvider = Provider<ConnectivityMonitor>((ref) {
  if (kIsWeb) return const NoopConnectivityMonitor();
  return ConnectivityPlusMonitor();
});

/// Current connectivity state, seeded by an initial check and then streamed.
///
/// Used only to nudge the single authoritative connection state
/// ([connectionStateProvider] via [FlutterConnectionController]) — never a
/// second reconnect loop.
final connectivityStateProvider =
    StateNotifierProvider<ConnectivityStateNotifier, AppConnectivityState>(
      (ref) => ConnectivityStateNotifier(ref),
    );

class ConnectivityStateNotifier extends StateNotifier<AppConnectivityState> {
  ConnectivityStateNotifier(this.ref) : super(AppConnectivityState.wifi) {
    _init();
  }

  final Ref ref;
  StreamSubscription<AppConnectivityState>? _sub;

  Future<void> _init() async {
    final monitor = ref.read(connectivityMonitorProvider);
    try {
      state = await monitor.checkConnectivity();
    } catch (_) {
      state = AppConnectivityState.wifi;
    }
    _sub = monitor.onConnectivityChanged.listen((next) {
      final prev = state;
      state = next;
      // On recovery from offline, nudge the controller to retry immediately
      // instead of waiting for the full backoff. The controller owns the
      // generation and ensures only one loop is active.
      if (prev == AppConnectivityState.none &&
          next != AppConnectivityState.none) {
        try {
          ref.read(flutterConnectionProvider).handleNetworkOnline();
        } catch (_) {}
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
    });
  }
}

/// Watches [connectivityStateProvider] and triggers a fresh generation on
/// network recovery when the controller is in `reconnecting`/`disconnected`.
///
/// Mount in the root (like [connectionLifecycleProvider]) so the single
/// connection loop is the only authority; no duplicate reconnect loops.
final connectivityLifecycleProvider = Provider<void>((ref) {
  ref.watch(connectivityStateProvider);
  // The actual nudge happens inside [ConnectivityStateNotifier] to keep the
  // provider's build side-effect free; this provider exists to ensure the
  // notifier is instantiated when the app starts (watched in [_buildRoot]).
});
