import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'src/core/bootstrap/app_plugins.dart';
import 'src/core/plugin/plugin_host.dart';
import 'src/core/renderer/slot_outlet.dart';

void main() {
  if (kDebugMode) {
    // Hooks into the Flutter runtime for the OpenCode agent (Marionette MCP):
    // widget-tree and interaction introspection Playwright cannot see
    // through the canvas.
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const ProviderScope(child: DshApp()));
}

/// Root application widget.
///
/// Boots the plugin host ([buildAppHost] + [PluginHost.activateAll]) and
/// renders the shell through the `'root'` slot — the only hardwired piece of
/// the tree, mirroring the React rule that the shell alone renders `'root'`.
/// Everything below arrives from plugins' slot registrations.
class DshApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const DshApp({super.key});

  @override
  ConsumerState<DshApp> createState() => _DshAppState();
}

class _DshAppState extends ConsumerState<DshApp> {
  PluginHost? _host;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    // Activation is async; the first frame renders blank until the host is up.
    // The pump loop's synchronous state mutations must not run during build,
    // so activation starts here rather than in build.
    Future<void>(() async {
      final host = buildAppHost(ref);
      await host.activateAll();
      if (mounted) setState(() => _host = host);
    }).catchError((Object error) {
      if (mounted) setState(() => _bootError = error);
    });
  }

  @override
  void dispose() {
    _host?.deactivateAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) {
      // Boot failure surfaces loud instead of a silent blank app; success
      // swaps to the slot-rendered shell on the next frame after activation.
      if (_bootError != null) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: _BootErrorScreen(error: _bootError!),
        );
      }
      return const SizedBox.shrink();
    }
    return SlotVersionBuilder(
      registry: host.slots,
      builder: (context, version) =>
          SlotOutlet(registry: host.slots, slotKey: 'root'),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFF1B1B1F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Plugin host failed to activate:\n$error',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Color(0xFFE3E2E6), fontSize: 14),
          ),
        ),
      ),
    ),
  );
}
