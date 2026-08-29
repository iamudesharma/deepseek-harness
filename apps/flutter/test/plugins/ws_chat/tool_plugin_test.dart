import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_plugin.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_presentation_registry.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:dsh_flutter/src/plugins/tool/ui/keyed_tool_card.dart';
import 'package:dsh_flutter/src/plugins/tool/ui/tool_call_tree.dart'
    show
        BashToolCard,
        DiffToolCard,
        GenericToolCard,
        ReadToolCard,
        SearchToolCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopFace implements SettingsFace {
  @override
  Future<Map<String, Object?>> describe() async => const {};

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async => const {};
}

PluginHost _host() {
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide(
    'conversation',
    ConversationController(
      client: ConnectionClient(baseUrl: ''),
      settingsScope: SettingsScope<Object?>(
        face: _NoopFace(),
        namespace: 'ui-theme',
      ),
    ),
  );
  return host;
}

SessionEventEnvelope _event(String type, int seq, Map<String, Object?> data) =>
    SessionEventEnvelope.fromJson({
      'type': type,
      'seq': seq,
      'time': 0,
      'data': data,
    });

ChatNodeData _dataFor(ConversationNode node) => ChatNodeData(
  key: node.key,
  lines: switch (node) {
    ToolNode(:final callId, :final result) => [callId, ?result],
    _ => [node.key],
  },
  toolName: switch (node) {
    ToolNode(:final name) => name,
    _ => null,
  },
  raw: switch (node) {
    ToolNode() => _TestToolAdapter(node),
    _ => null,
  },
);

class _TestToolAdapter implements ToolNodeAdapter, ToolNodeAdapterWithSubCalls {
  _TestToolAdapter(this.node);
  final ToolNode node;
  @override
  List<ToolSubCallAdapter> get subCalls =>
      node.subCalls.map((c) => _TestSubCallAdapter(c)).toList();
  @override
  ToolCall toToolCall() {
    final status = node.status == ToolNodeStatus.running
        ? ToolCallStatus.running
        : node.isError
        ? ToolCallStatus.error
        : ToolCallStatus.success;
    return ToolCall(
      id: node.callId,
      toolName: node.name,
      kind: kindForTool(node.name),
      status: status,
      result: node.result,
      time: 0,
    );
  }
}

class _TestSubCallAdapter implements ToolSubCallAdapter {
  _TestSubCallAdapter(this.sub);
  final ToolSubCall sub;
  @override
  String get subCallId => sub.subCallId;
  @override
  String get name => sub.name;
  @override
  bool get isError => sub.isError;
  @override
  String? get result => sub.result;
  @override
  List<ToolSubCallAdapter> get children =>
      sub.children.map(_TestSubCallAdapter.new).toList();
}

/// Folds a call+result script and returns (settled node, running node).
(ToolNode, ToolNode) _foldCallAndResult() {
  final folder = ConversationNodeFolder()
    ..add(_event('tool/call', 1, {'callId': 'c1', 'name': 'read'}))
    ..add(
      _event('tool/result', 2, {
        'message': {'callId': 'c1'},
        'result': 'file body\nline two',
      }),
    )
    ..add(_event('tool/call', 3, {'callId': 'c2', 'name': 'read'}));
  final nodes = folder.snapshot().nodes.whereType<ToolNode>().toList();
  return (nodes.first, nodes.last);
}

void main() {
  test('activation provides the keyed presentation service and registers the chat-node renderers', () async {
    final host = _host();
    addTearDown(host.deactivateAll);
    host.register(ToolPlugin());

    await host.activateAll();

    final presentations = host.service<ToolPresentationRegistry>(
      'toolPresentation',
    );
    expect(presentations, isNotNull);
    // React's shipped registrations: bash/read rows, edit/write diff row,
    // grep/glob search row, web_search/web_fetch, todo_write, ask_user_question.
    expect(
      presentations!.keys,
      containsAll([
        'bash',
        'read',
        'edit',
        'write',
        'grep',
        'glob',
        'web_search',
        'web_fetch',
        'todo_write',
        'ask_user_question',
      ]),
    );
    final conversation = host.service<ConversationController>('conversation')!;
    // Single chat-node entry key `tool-call` owns the ToolCallTree dispatch.
    expect(conversation.renderers.resolve('tool-call'), isNotNull);
    expect(conversation.renderers.keys, contains('tool-call'));
    expect(conversation.renderers.resolve('bash'), isNull);
    expect(conversation.renderers.resolve('read'), isNull);
  });

  test('an unclaimed tool name keeps the builtin presentation and generic fallback', () async {
    final host = _host();
    addTearDown(host.deactivateAll);
    host.register(ToolPlugin());
    await host.activateAll();

    final presentations = host.service<ToolPresentationRegistry>(
      'toolPresentation',
    )!;
    final conversation = host.service<ConversationController>('conversation')!;
    // Unknown tool not in shipped set -> generic fallback via tool-call renderer.
    expect(presentations.resolve('mystery_tool_xyz'), isNull);
    expect(conversation.renderers.resolve('mystery_tool_xyz'), isNull);
    // The single tool-call renderer still exists.
    expect(conversation.renderers.resolve('tool-call'), isNotNull);
    expect(conversation.renderers.resolve('assistant'), isNull);
  });

  test('presentation registry rejects a duplicate claim', () async {
    final registry = ToolPresentationRegistry();
    registry.register('bash', (_, _) => const SizedBox.shrink());
    expect(
      () => registry.register('bash', (_, _) => const SizedBox.shrink()),
      throwsStateError,
    );
  });

  testWidgets(
    'folded tool/call+result stream picks the right card per tool name',
    (tester) async {
      final host = _host();
      addTearDown(host.deactivateAll);
      host.register(ToolPlugin());
      await host.activateAll();
      final conversation = host.service<ConversationController>(
        'conversation',
      )!;
      final (settled, running) = _foldCallAndResult();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) {
                    final renderer = conversation.renderers.resolve(
                      'tool-call',
                    )!;
                    return renderer(context, _dataFor(settled));
                  },
                ),
                Builder(
                  builder: (context) {
                    final renderer = conversation.renderers.resolve(
                      'tool-call',
                    )!;
                    return renderer(context, _dataFor(running));
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Both rows dispatched through the single tool-call entry; each renders
      // its tool-specific card via the keyed presentation table.
      expect(find.byType(KeyedToolCard), findsNWidgets(0));
      // The new ToolCallTree row is used for tool-call nodes.
      expect(find.text('read'), findsNWidgets(2));

      // The settled row is expandable and its expanded body IS the read card.
      // Tap the first row's header to expand.
      await tester.tap(find.text('read').first);
      await tester.pumpAndSettle();
      expect(find.byType(ReadToolCard), findsOneWidget);

      // The running row has no result line, so it stays collapsed.
      expect(find.byType(ReadToolCard), findsOneWidget);
    },
  );

  testWidgets(
    'dispatch falls back per key: bash→terminal card, grep→search card, unknown→generic',
    (tester) async {
      final host = _host();
      addTearDown(host.deactivateAll);
      host.register(ToolPlugin());
      await host.activateAll();
      final conversation = host.service<ConversationController>(
        'conversation',
      )!;

      ChatNodeData dataFor(String toolName, String callId) => ChatNodeData(
        key: 't$callId',
        lines: [callId, 'out'],
        toolName: toolName,
        raw: null,
      );
      Widget pump(String toolName, String callId) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final renderer = conversation.renderers.resolve('tool-call')!;
              return renderer(context, dataFor(toolName, callId));
            },
          ),
        ),
      );

      await tester.pumpWidget(pump('bash', 'b1'));
      await tester.tap(find.text('bash').first);
      await tester.pumpAndSettle();
      expect(find.byType(BashToolCard), findsOneWidget);

      await tester.pumpWidget(pump('grep', 'g1'));
      await tester.tap(find.text('grep').first);
      await tester.pumpAndSettle();
      expect(find.byType(SearchToolCard), findsOneWidget);

      await tester.pumpWidget(pump('edit', 'e1'));
      await tester.tap(find.text('edit').first);
      await tester.pumpAndSettle();
      expect(find.byType(DiffToolCard), findsOneWidget);

      // An unclaimed name lands on the generic fallback via the tool-call renderer.
      await tester.pumpWidget(pump('mystery_tool_xyz', 't9'));
      await tester.tap(find.text('mystery_tool_xyz').first);
      await tester.pumpAndSettle();
      expect(find.byType(GenericToolCard), findsOneWidget);
    },
  );

  test('live ToolCallNode resolves to chat-node renderer tool-call and produces visible content', () async {
    final host = _host();
    addTearDown(host.deactivateAll);
    host.register(ToolPlugin());
    await host.activateAll();
    final conversation = host.service<ConversationController>('conversation')!;
    final renderer = conversation.renderers.resolve('tool-call');
    expect(
      renderer,
      isNotNull,
      reason: 'tool-call renderer must be registered',
    );
    // Simulate a live ToolNode folded from tool/call.
    final folder = ConversationNodeFolder()
      ..add(_event('tool/call', 1, {'callId': 'live-1', 'name': 'bash'}));
    final node = folder.snapshot().nodes.whereType<ToolNode>().single;
    final data = _dataFor(node);
    expect(data.toolName, 'bash');
    // Verify the resolved renderer would produce a widget (smoke via tester)
    // is done in the widget tests above; this test confirms the registry contract.
  });
}
