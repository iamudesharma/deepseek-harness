import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration-stage evidence for the P1 hubs (migration/plan.md): the real
/// application host activates every hub plugin through PluginHost, services
/// resolve via DshContext, slot composition carries the sidebar into the
/// router's frame, and the theme service drives the live ThemeMode.
void main() {
  testWidgets('full host activation integrates all P1 hub seams', (tester) async {
    late final WidgetRef captured;
    PluginHost? host;
    Object? failure;

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        }),
      ),
    );

    // Activate exactly what DshApp activates — same entry point, no test shim.
    PluginHost? built;
    try {
      built = buildAppHost(captured);
      await built.activateAll();
    } catch (e) {
      failure = e;
    }
    expect(failure, isNull, reason: 'hub plugins must activate cleanly');
    final h = built!;

    // Service injection: every P1 service name resolves through DshContext.
    final context = _HostContextView(h);
    expect(context.require<Object>('slots'), same(h.slots));
    expect(context.require<Object>('theme'), isA<Object>());
    expect(context.require<Object>('settingsScope'), isA<Object>());
    expect(context.require<Object>('connection'), isA<Object>());
    expect(context.hasService('runtime'), isTrue);
    // P1.5 runtime service dependencies resolve through the same face.
    expect(context.require<SessionsService>('sessions'), isNotNull);
    expect(context.require<WorkspacesService>('workspaces'), isNotNull);
    expect(context.require<LocaleService>('locale'), isNotNull);
    expect(context.require<RemoteEventBus>('remote'), isNotNull);

    // Slot registration/composition: shell owns root; sidebar fills its hole.
    expect(h.slots.winnersOfSlot('root'), hasLength(1));
    expect(h.slots.isDeclared('layout.sidebar'), isTrue);
    expect(h.slots.entries('layout.sidebar'), hasLength(1));

    // Runtime behavior: theme service writes propagate to the UI seat.
    final theme = context.require<Object>('theme') as dynamic;
    theme.setPreference(AppThemePreference.dark);
    await tester.pump();
    expect(captured.read(themeModeProvider), ThemeMode.dark);
    // Router-facing ledger handoff happened during activation.
    expect(captured.read(activeSlotsProvider), same(h.slots));

    h.deactivateAll();
  });
}

/// Minimal [DshContext] view over an already-activated host, for asserting
/// the service table through the same face plugins use.
class _HostContextView implements DshContext {
  _HostContextView(this._host);

  final PluginHost _host;

  @override
  T require<T>(String name) => get<T>(name)!;

  @override
  T? get<T>(String name) => _host.service<T>(name);

  @override
  void provide(String name, Object service) =>
      throw UnsupportedError('read-only view');

  @override
  bool hasService(String name) => _host.hasService(name);

  @override
  SlotRegistry get slots => _host.slots;

  @override
  void onDispose(Disposer disposer) =>
      throw UnsupportedError('read-only view');
}
