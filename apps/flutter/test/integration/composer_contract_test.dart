/// Composer control contract tests (manual-QA bug 6 regression gate).
///
/// Mounts the REAL composed shell — [buildAppHost] with every plugin
/// activated over a captured client — and drives each composer control like
/// a user. Each control must open its OWN surface and emit its own wire
/// payload: the model dropdown talks `session.selectModel` (effort picks
/// preserve provider/model; an empty catalog synthesizes nothing), the
/// permission seat submits `/permission <value>` through the command channel
/// behind the danger-full-access risk gate, the plan chip executes `/plan
/// off`, typing `/` opens the trigger menu whose pick opens the popupSelect
/// surface, and submit carries draft text plus staged image parts.
library;

import 'dart:typed_data';

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart'
    as conn;
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/widgets/attachment_rail.dart';
import 'package:dsh_flutter/src/plugins/commands/ui/popup_select_overlay.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/column.dart';
import 'package:dsh_flutter/src/features/model_selection/model_directory.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/ui/permission_seat.dart';
import 'package:dsh_flutter/src/plugins/plan/ui/plan_provider.dart';
import 'package:dsh_flutter/src/plugins/workspace/ui/workspace_picker_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String qaSession = 's-qa';

/// Captured-client double: records the wire payloads the contract asserts.
class QaClient extends conn.ConnectionClient {
  QaClient() : super(baseUrl: 'http://qa-host');

  final List<({String method, Map<String, dynamic> payload})> calls = [];
  final List<({String sessionId, String content, String mode, List<Map<String, dynamic>> images})>
      sends = [];

  Map<String, dynamic> Function(String method, Map<String, dynamic> payload)?
      onCallMethod;

  @override
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    sends.add((
      sessionId: sessionId.value,
      content: content,
      mode: mode,
      images: images,
    ));
  }

  @override
  Future<Map<String, dynamic>> callMethod(
      String method, Map<String, dynamic> payload) async {
    calls.add((method: method, payload: payload));
    final handler = onCallMethod;
    if (handler != null) return handler(method, payload);
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> sessionModels(
      {required String sessionId}) async {
    calls.add((method: 'session.models', payload: {'sessionId': sessionId}));
    return modelDirectoryPayload;
  }

  @override
  Future<Map<String, dynamic>> sessionSelectModel({
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'provider': provider,
      'model': model,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    };
    calls.add((method: 'session.selectModel', payload: payload));
    return {
      'selected': {
        'provider': provider,
        'model': model,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> skillList({required String sessionId}) async {
    calls.add((method: 'skill.list', payload: {'sessionId': sessionId}));
    final handler = onCallMethod;
    if (handler != null) {
      final v = handler('skill.list', {'sessionId': sessionId});
      if (v.containsKey('skills')) return v;
    }
    return const <String, dynamic>{'skills': []};
  }

  /// Scripted per-session directory (mutated by individual tests before the
  /// first watch auto-loads it).
  Map<String, dynamic> modelDirectoryPayload = const <String, dynamic>{
    'groups': [
      {
        'id': 'deepseek',
        'name': 'DeepSeek',
        'models': [
          {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
          {
            'id': 'deepseek-reasoner',
            'name': 'DeepSeek Reasoner',
            'reasoning': {
              'defaultEffort': 'medium',
              'efforts': [
                {'id': 'low', 'name': 'Low'},
                {'id': 'medium', 'name': 'Medium'},
                {'id': 'high', 'name': 'High'},
              ],
            },
          },
        ],
      },
    ],
    'routable': true,
  };

  ({String method, Map<String, dynamic> payload})? singleCall(String method) {
    final hits =
        calls.where((c) => c.method == method).toList(growable: false);
    return hits.isEmpty ? null : hits.single;
  }
}

/// Pumps the real composed conversation column for [qaSession] under the
/// fully activated application host. Returns the captured container so tests
/// can seed session-scoped projections.
Future<ProviderContainer> pumpComposedShell(
  WidgetTester tester,
  QaClient client,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [conn.connectionClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);

  PluginHost? host;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (context, ref, _) {
      // Activate exactly what DshApp activates — no test shim.
      host ??= buildAppHost(ref);
      return const SizedBox.shrink();
    }),
  ));
  await tester.pump();
  await host!.activateAll();
  addTearDown(host!.deactivateAll);

  // Seed the QA session as current BEFORE mounting the column.
  container.read(sessionsProvider.notifier).addSession(const SessionSummary(
        sessionId: SessionId(qaSession),
        updatedAt: 0,
        running: false,
        blank: false,
        title: 'QA session',
      ));
  container
      .read(sessionsProvider.notifier)
      .setCurrent(const SessionId(qaSession));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
        home: Scaffold(body: ConversationColumn(sessionId: qaSession))),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('model dropdown selects strictly from groups and sends the advertised default effort',
      (tester) async {
    final client = QaClient();
    await pumpComposedShell(tester, client);

    // Trigger label starts unselected (no current in the scripted catalog).
    expect(find.text('Select model'), findsOneWidget);

    await tester.tap(find.text('Select model'));
    await tester.pumpAndSettle();
    // Root pane drills first.
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    // The live catalog only — both scripted rows visible, pick the
    // reasoning model.
    expect(find.text('DeepSeek Chat'), findsOneWidget);
    expect(find.text('DeepSeek Reasoner'), findsOneWidget);
    await tester.tap(find.text('DeepSeek Reasoner'));
    await tester.pumpAndSettle();

    final call = client.singleCall('session.selectModel');
    expect(call, isNotNull);
    expect(call!.payload['provider'], 'deepseek');
    expect(call.payload['model'], 'deepseek-reasoner');
    // A supported model STARTS at its advertised default effort.
    expect(call.payload['reasoningEffort'], 'medium');

    // Accepted selection closes the menu; the chip itself shows the model
    // with its effort badge.
    expect(find.text('DeepSeek Reasoner'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
  });

  testWidgets('effort submenu appears only for a reasoning model and preserves provider/model',
      (tester) async {
    final client = QaClient()..modelDirectoryPayload = _reasoningCurrent();
    await pumpComposedShell(tester, client);

    // Current model advertises reasoning → root pane carries the Effort row.
    await tester.tap(find.byIcon(Icons.memory_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Effort'), findsOneWidget);

    await tester.tap(find.text('Effort'));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Provider default'), findsNothing); // default pinned

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();

    final call = client.singleCall('session.selectModel')!;
    expect(call.payload['provider'], 'deepseek'); // preserved
    expect(call.payload['model'], 'deepseek-reasoner'); // preserved
    expect(call.payload['reasoningEffort'], 'high');
  });

  testWidgets('non-reasoning current model hides the Effort row entirely',
      (tester) async {
    final client = QaClient()
      ..modelDirectoryPayload = _plainCurrent(modelId: 'deepseek-chat');
    await pumpComposedShell(tester, client);

    await tester.tap(find.byIcon(Icons.memory_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Effort'), findsNothing);
  });

  testWidgets('empty catalog renders the explicit empty row and never synthesizes a selection',
      (tester) async {
    final client = QaClient()
      ..modelDirectoryPayload = const <String, dynamic>{
        'groups': <Object?>[],
        'routable': true,
      };
    await pumpComposedShell(tester, client);

    await tester.tap(find.byIcon(Icons.memory_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.text('No models available'), findsOneWidget);
    expect(client.singleCall('session.selectModel'), isNull);
  });

  testWidgets('permission seat gates danger-full-access then submits /permission through the command channel',
      (tester) async {
    final client = QaClient();
    final container = await pumpComposedShell(tester, client);
    container.read(permissionSelectProvider(qaSession).notifier).state =
        const PermissionSelect(
      options: [
        PresetOption(value: 'default', name: 'Default'),
        PresetOption(value: 'danger-full-access', name: 'Full Access'),
      ],
      currentValue: 'default',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PermissionSeat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Access'));
    await tester.pumpAndSettle();

    // RiskConfirmation gate first (dialog copy is locale-bound; the gate is
    // asserted structurally): the confirm FilledButton stays dead until the
    // acknowledge checkbox flips.
    expect(find.byType(Checkbox), findsOneWidget);
    final FilledButton enableButton = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(enableButton.onPressed, isNull);
    expect(
      client.calls.where((c) => c.method == 'commands/execute'),
      isEmpty,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final executed = client.calls
        .where((c) => c.method == 'commands/execute')
        .map((c) => c.payload)
        .toList();
    expect(executed, hasLength(1));
    final args = executed.single['args'] as Map;
    expect(args['agentId'], qaSession);
    expect(args['line'], '/permission danger-full-access');
  });

  testWidgets('plan chip exit executes /plan off through the bound control',
      (tester) async {
    final client = QaClient();
    final container = await pumpComposedShell(tester, client);
    container.read(planProvider.notifier).enter();
    await tester.pumpAndSettle();

    // The chip is its own docked surface (Plan wordmark + close glyph); the
    // wordmark sits inside the chip's InkWell.
    expect(find.text('Plan'), findsOneWidget);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    final executed = client.calls
        .where((c) => c.method == 'commands/execute')
        .map((c) => c.payload)
        .toList();
    expect(executed, hasLength(1));
    expect((executed.single['args'] as Map)['line'], '/plan off');
  });

  testWidgets("typing '/' opens the trigger menu and picking a host command executes it detached",
      (tester) async {
    final client = QaClient();
    // Scope birth prewarms the command catalog; serve it from the first
    // commands/list onward (slash-form, args wrapper) — legacy
    // command.list shape is also answered for older fakes.
    client.onCallMethod = (method, payload) {
      if (method == 'commands/list' || method == 'command.list') {
        return const <String, dynamic>{
          'commands': [
            {'name': 'plan', 'description': 'Plan mode'},
          ],
        };
      }
      // Some product paths still hit the legacy dot form before the slash
      // migration lands on the host; the skills catalog is stubbed too so
      // the '/' trigger group stays populated even when the host fake 400s.
      if (method == 'skill.list' || method == 'skill/list') {
        return const <String, dynamic>{
          'skills': [],
        };
      }
      return const <String, dynamic>{};
    };
    await pumpComposedShell(tester, client);

    final field = find.byType(TextField);
    await tester.enterText(field, '/');
    await tester.pump();
    // Host catalog arrives over command.list (async); bounded pumps keep
    // this deterministic.
    for (var i = 0;
        i < 20 && find.text('plan').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('plan'), findsOneWidget);

    await tester.tap(find.text('plan'));
    await tester.pumpAndSettle();

    // A host command without an input hint executes detached through the
    // prompt channel (the menu pick consumes the token; no draft splice).
    final prompts = client.calls
        .where((c) => c.method == 'session.prompt')
        .map((c) => c.payload)
        .toList();
    expect(prompts, hasLength(1));
    expect(prompts.single['sessionId'], qaSession);
    final content = prompts.single['content'] as List;
    expect((content.single as Map)['text'], '/plan');
    // The trigger menu closed after the pick.
    expect(find.text('plan'), findsNothing);
  });

  testWidgets('submit carries draft text and staged image parts through the send channel',
      (tester) async {
    final client = QaClient();
    final container = await pumpComposedShell(tester, client);

    container
        .read(composerControllerProvider(qaSession).notifier)
        .addAttachments([
      ComposerAttachment.create(
        name: 'shot.png',
        mimeType: 'image/png',
        size: 4,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
    ]);
    await tester.pumpAndSettle();
    // Attachment rail renders on its own strip inside the card (thumbnails,
    // not names).
    expect(find.byType(AttachmentRail), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello qa');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(client.sends, hasLength(1));
    final send = client.sends.single;
    expect(send.sessionId, qaSession);
    expect(send.content, 'hello qa');
    expect(send.mode, 'queue');
    expect(send.images, hasLength(1));
    expect(send.images.single['mediaType'], 'image/png');
  });

  testWidgets('tool row order: access < plan < model < send inside the composer card',
      (tester) async {
    final client = QaClient();
    final container = await pumpComposedShell(tester, client);
    // Make every seat visible: the plan chip self-hides while target off.
    container.read(planProvider.notifier).enter();
    container.read(permissionSelectProvider(qaSession).notifier).state =
        const PermissionSelect(
      options: [PresetOption(value: 'default', name: 'Default')],
      currentValue: 'default',
    );
    await tester.pumpAndSettle();

    Rect rectOf(Finder finder) => tester.getRect(finder.first);

    final Rect access = rectOf(find.byType(PermissionSeat));
    final Rect plan = rectOf(find.text('Plan'));
    final Rect model = rectOf(find.byIcon(Icons.memory_outlined));
    final Rect send = rectOf(find.byIcon(Icons.arrow_upward_rounded));

    // React InputBar.tsx DOM order (lines 695-758): access and plan lead in
    // `.modes`, the model seat trails in `.trailing` immediately before send.
    expect(access.left, lessThan(plan.left),
        reason: 'access seat sits before the plan chip');
    expect(plan.left, lessThan(model.left),
        reason: 'plan chip sits before the model seat');
    expect(model.right, lessThan(send.left),
        reason: 'model seat sits immediately before send');

    // Every seat lives INSIDE the composer card — none floats at window
    // level. The card is the TextField's ancestor box.
    final Rect field = rectOf(find.byType(TextField));
    for (final (String name, Rect r) in [
      ('access', access),
      ('plan', plan),
      ('model', model),
      ('send', send)
    ]) {
      expect(r.left >= field.left - 1 && r.right <= field.right + 24,
          isTrue,
          reason:
              '$name seat must sit within the composer card row (left=${r.left}, right=${r.right})');
      expect(r.top >= field.bottom - 1, isTrue,
          reason: '$name seat must sit on the tool row BELOW the draft field');
    }
  });

  testWidgets('workspace chip never mounts in the active-session composer',
      (tester) async {
    final client = QaClient();
    await pumpComposedShell(tester, client);

    // React keeps the picker in `conversation.hero.workspace` only; an
    // active session's composer carries no workspace control.
    expect(find.byType(WorkspacePickerChip), findsNothing);
  });

  testWidgets("typing '/' anchors the trigger menu to the composer card",
      (tester) async {
    final client = QaClient();
    client.onCallMethod = (method, payload) {
      if (method == 'commands/list' || method == 'command.list') {
        return const <String, dynamic>{
          'commands': [
            {'name': 'plan', 'description': 'Plan mode'},
          ],
        };
      }
      if (method == 'skill.list' || method == 'skill/list') {
        return const <String, dynamic>{'skills': []};
      }
      return const <String, dynamic>{};
    };
    await pumpComposedShell(tester, client);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0;
        i < 20 && find.text('plan').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }

    final Rect menu = tester.getRect(find.byKey(const ValueKey('input-menu-surface')));
    final Rect field = tester.getRect(find.byType(TextField));
    // Left-aligned to the composer card (React MenuView.module.css
    // `.menu { bottom: calc(100% + 4px); left: 0 }` against the card-wide
    // overlay anchor) and floating fully ABOVE the card's top edge. The
    // field sits one card padding inside the card edges, so the menu's left
    // edge may lead the field by up to that padding but must never drift
    // toward the card center.
    expect(menu.left, greaterThanOrEqualTo(field.left - 48),
        reason: 'menu stays at the card left edge instead of drifting right');
    expect(menu.left, lessThan(field.left + 48),
        reason: 'menu hugs the card left edge instead of drifting right');
    expect(menu.bottom, lessThanOrEqualTo(field.top + 2),
        reason: 'menu opens upward above the composer card');
  });
}

Map<String, dynamic> _reasoningCurrent() => const <String, dynamic>{
      'current': {
        'provider': 'deepseek',
        'model': 'deepseek-reasoner',
        'reasoningEffort': 'medium',
      },
      'groups': [
        {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'models': [
            {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
            {
              'id': 'deepseek-reasoner',
              'name': 'DeepSeek Reasoner',
              'reasoning': {
                'defaultEffort': 'medium',
                'efforts': [
                  {'id': 'low', 'name': 'Low'},
                  {'id': 'medium', 'name': 'Medium'},
                  {'id': 'high', 'name': 'High'},
                ],
              },
            },
          ],
        },
      ],
      'routable': true,
    };

Map<String, dynamic> _plainCurrent({required String modelId}) =>
    <String, dynamic>{
      'current': {'provider': 'deepseek', 'model': modelId},
      'groups': [
        {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'models': [
            {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
            {'id': 'deepseek-reasoner', 'name': 'DeepSeek Reasoner'},
          ],
        },
      ],
      'routable': true,
    };
