import 'package:dsh_flutter/src/features/settings_models/widgets/model_list_editor.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _t(String key) => key;

Widget _wrap(ModelListEditor editor) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: editor)),
    ),
  );
}

ModelListEditor _editor({
  List<ModelDraft> models = const [],
  bool overridden = false,
  ValueChanged<List<ModelDraft>>? onChange,
  VoidCallback? onReset,
  ProbeTarget probe = const ProbeTarget(settingsNs: 'llm-pi-ai'),
  String? probeBlockedMessage,
  Future<List<Map<String, dynamic>>> Function(ProbeTarget)? onDiscover,
  bool disabled = false,
}) {
  return ModelListEditor(
    models: models,
    overridden: overridden,
    onChange: onChange ?? (_) {},
    onReset: onReset,
    probe: probe,
    probeBlockedMessage: probeBlockedMessage,
    onDiscover: onDiscover ?? (_) async => const [],
    disabled: disabled,
    t: _t,
  );
}

void main() {
  group('ModelListEditor rows', () {
    testWidgets('inherited rows render with the inherited meta', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _editor(
            models: [
              {'id': 'base-model'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('modelsInherited'), findsOneWidget);
      expect(find.text('restoreDefaults'), findsNothing);
    });

    testWidgets('typing an id emits the patched rows', (tester) async {
      List<ModelDraft>? changed;
      await tester.pumpWidget(
        _wrap(
          _editor(
            models: [
              {'id': ''},
            ],
            overridden: true,
            onChange: (next) => changed = next,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, 'gpt-x');
      await tester.pump();

      expect(changed, [
        {'id': 'gpt-x'},
      ]);
    });

    testWidgets('add model appends a blank row', (tester) async {
      List<ModelDraft>? changed;
      await tester.pumpWidget(
        _wrap(_editor(onChange: (next) => changed = next)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('addModel'));
      await tester.pump();

      expect(changed, [
        {'id': ''},
      ]);
    });

    testWidgets('delete removes the row', (tester) async {
      List<ModelDraft>? changed;
      await tester.pumpWidget(
        _wrap(
          _editor(
            models: [
              {'id': 'a'},
              {'id': 'b'},
            ],
            overridden: true,
            onChange: (next) => changed = next,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('removeModel').first);
      await tester.pump();

      expect(changed, [
        {'id': 'b'},
      ]);
    });

    testWidgets('restore defaults calls onReset when overridden', (
      tester,
    ) async {
      var reset = false;
      await tester.pumpWidget(
        _wrap(
          _editor(
            models: [
              {'id': 'custom'},
            ],
            overridden: true,
            onReset: () => reset = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('modelsCustomized'), findsOneWidget);
      await tester.tap(find.text('restoreDefaults'));
      await tester.pump();

      expect(reset, isTrue);
    });
  });

  group('ModelListEditor fetch', () {
    const probe = ProbeTarget(
      settingsNs: 'llm-pi-ai',
      provider: 'opencode',
      baseURL: 'https://opencode.ai/zen/v1',
    );

    testWidgets('fetch is disabled without a route or endpoint', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_editor(probe: const ProbeTarget(settingsNs: 'llm-pi-ai'))),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'fetchModels'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('fetch opens the picker and adopts the selection', (
      tester,
    ) async {
      List<ModelDraft>? changed;
      await tester.pumpWidget(
        _wrap(
          _editor(
            models: [
              {'id': 'keep', 'contextWindow': 1000},
            ],
            overridden: true,
            probe: probe,
            onDiscover: (_) async => [
              {'id': 'keep', 'contextWindow': 9999},
              {'id': 'new-model', 'name': 'New'},
            ],
            onChange: (next) => changed = next,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('fetchModels'));
      await tester.pumpAndSettle();

      // Already-configured ids start unchecked; the new one is picked.
      expect(find.text('new-model'), findsOneWidget);
      await tester.tap(find.text('fetchAdopt'));
      await tester.pumpAndSettle();

      // Tuned row wins over provider numbers; the pick appends with metadata.
      expect(changed, [
        {'id': 'keep', 'contextWindow': 1000},
        {'id': 'new-model', 'name': 'New'},
      ]);
    });

    testWidgets('fetch failure shows next to the rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _editor(
            probe: probe,
            onDiscover: (_) async => throw Exception('endpoint down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('fetchModels'));
      await tester.pumpAndSettle();

      expect(find.textContaining('endpoint down'), findsOneWidget);
    });

    testWidgets('empty fetch reports no models', (tester) async {
      await tester.pumpWidget(
        _wrap(_editor(probe: probe, onDiscover: (_) async => const [])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('fetchModels'));
      await tester.pumpAndSettle();

      expect(find.text('fetchEmpty'), findsOneWidget);
    });
  });
}
