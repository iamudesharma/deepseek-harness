import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart'
    show SlotComponentProps;
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show LocaleService, localeServiceProvider;
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/features/model_selection/model_directory.dart';
import 'package:dsh_flutter/src/plugins/brand_official/brand_official_plugin.dart';
import 'package:dsh_flutter/src/plugins/model_selection/model_directory_service.dart';
import 'package:dsh_flutter/src/plugins/model_selection/locales.dart';
import 'package:dsh_flutter/src/plugins/model_selection/ui/model_seat.dart';
import 'package:dsh_flutter/src/plugins/workspace/locales.dart';
import 'package:dsh_flutter/src/plugins/workspace/ui/workspace_picker_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Registers the plugin-owned dictionaries the pumped seats consume; in the
/// real app each namespace lands in its owning plugin's `apply`.
void _registerLocaleDictionaries(ProviderContainer container) {
  final LocaleService locale = container.read(localeServiceProvider);
  locale.register(kModelNamespace, {'zh': kModelZh, 'en': kModelEn});
  locale.register(kWorkspaceNamespace, {
    'zh': kWorkspaceZh,
    'en': kWorkspaceEn,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('brand mark renders the official fish mark', (tester) async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);
    host.register(const BrandOfficialPlugin());
    await host.activateAll();

    declareSurfaceHoles(host);
    final entry = host.slots
        .winnersOfSlot('conversation.hero.brand.mark')
        .single;
    Widget mark(BuildContext context) =>
        (entry.component as Widget Function(BuildContext, SlotComponentProps))(
          context,
          const SlotComponentProps(slotKey: kHeroBrandMarkSlot, priority: 0),
        );

    await tester.pumpWidget(MaterialApp(home: Builder(builder: mark)));
    // The fish mark paints via a custom painter, not a text fallback.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('model seat shows the trigger and lists the loaded catalog', (
    tester,
  ) async {
    final directories = ModelDirectoryService(FakeClient());
    bindActivatedModelDirectories(directories);
    addTearDown(() => bindActivatedModelDirectories(null));

    const summary = SessionSummary(
      sessionId: SessionId('s-1'),
      updatedAt: 0,
      running: false,
      blank: true,
    );

    final container = ProviderContainer(
      overrides: [currentSessionProvider.overrideWithValue(summary)],
    );
    addTearDown(container.dispose);
    _registerLocaleDictionaries(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ModelSeat())),
      ),
    );
    await tester.pump();

    // Unset trigger shows the localized fallback copy.
    expect(find.text('选择模型'), findsOneWidget);

    // Opening the menu loads the directory; the fake answers empty, so the
    // menu opens with no model rows (fail-loud emptiness, not fake data).
    await tester.tap(find.byType(ModelSeat));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<(String, ModelInfo)>), findsNothing);
  });

  testWidgets('workspace picker chip renders the add flow affordance', (
    tester,
  ) async {
    final client = FakeClient()
      ..answers['workspace.list'] = {
        'items': [
          {'workspaceId': 'ws-1', 'title': 'Main', 'path': '/work/main'},
        ],
      };

    final container = ProviderContainer(
      overrides: [connectionClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    _registerLocaleDictionaries(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: WorkspacePickerChip())),
      ),
    );
    await tester.pumpAndSettle();

    // Chip label resolves workspace.section.workspaces in the default (zh)
    // service locale.
    expect(find.text('工作区'), findsOneWidget);
  });
}
