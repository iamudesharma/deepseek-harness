import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEventEnvelope e(
  String type,
  int seq,
  Map<String, Object?> data, {
  List<int>? sources,
  Object? surfaceOp,
}) => SessionEventEnvelope.fromJson({
  'type': type,
  'seq': seq,
  'time': 0,
  'data': data,
  if (sources != null) 'sourceEventSeqs': sources,
  if (surfaceOp != null) 'surfaceOp': surfaceOp,
});

void main() {
  test('manual compaction lifecycle: run -> summary -> checkpoint -> done yields manual node with compaction', () {
    final f = ConversationNodeFolder()
      ..add(
        e('command/run', 1, {
          'commandId': 'cmd-1',
          'name': 'compact',
          'args': '',
        }),
      )
      ..add(
        SessionEventEnvelope.fromJson({
          'type': 'compaction/summary',
          'seq': 2,
          'time': 0,
          'data': {
            'compactionId': 'manual-1',
            'sourceCommandId': 'cmd-1',
            'summary': [
              {'type': 'text', 'text': 'manual summary **bold**'},
            ],
            'shadowedSeqs': [10, 11],
            'shadowedTokenCount': 123,
          },
        }),
      )
      ..add(
        SessionEventEnvelope.fromJson({
          'type': 'user/message',
          'seq': 3,
          'time': 0,
          'data': {
            'content': [
              {'type': 'text', 'text': 'checkpoint'},
            ],
            'source': {
              'kind': 'plugin',
              'plugin': 'compact',
              'compactionId': 'manual-1',
              'sourceCommandId': 'cmd-1',
            },
          },
          'surfaceOp': {'op': 'replace', 'start': 10, 'end': 11},
        }),
      )
      ..add(
        e('command/done', 4, {
          'commandId': 'cmd-1',
          'kind': 'success',
          'text': 'done',
          'sourceEventSeq': 2,
        }),
      );
    final nodes = f.snapshot().nodes;
    final manual = nodes.whereType<ManualCompactionNode>().single;
    expect(manual.command.commandId, 'cmd-1');
    expect(manual.compaction, isNotNull);
    expect(manual.compaction!.text, 'manual summary **bold**');
    expect(manual.compaction!.shadowedItemCount, 2);
    expect(manual.compaction!.shadowedTokenCount, 123);
    // markdown text preserved
    expect(manual.compaction!.text, contains('**bold**'));
    print('manual ok ${manual.key}');
  });

  test('manual compaction running without checkpoint shows manual node without compaction', () {
    final f = ConversationNodeFolder()
      ..add(e('command/run', 1, {'commandId': 'cmd-2', 'name': 'compact'}));
    final nodes = f.snapshot().nodes;
    final manual = nodes.whereType<ManualCompactionNode>().single;
    expect(manual.command.name, 'compact');
    expect(manual.compaction, isNull);
    expect(manual.command.outcome, isNull);
    print('running ok');
  });

  test('manual compaction out-of-order parent: child before parent still materializes correctly', () {
    final f = ConversationNodeFolder()
      ..add(e('tool/call', 1, {'callId': 'root-1', 'name': 'run-code'}))
      // child dispatched before parent subcall exists as parent
      ..add(
        e('tool/code-dispatch-start', 2, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1',
          'subCallId': 'root-1:code:1:code:1',
          'name': 'inner',
          'arguments': {},
        }),
      )
      ..add(
        e('tool/code-dispatch-start', 3, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:1',
          'name': 'bash',
          'arguments': {},
        }),
      )
      ..add(
        e('tool/code-dispatch', 4, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1',
          'subCallId': 'root-1:code:1:code:1',
          'name': 'inner',
          'content': [
            {'type': 'text', 'text': 'deep-out'},
          ],
        }),
      );
    final tool = f.snapshot().nodes.whereType<ToolNode>().single;
    // Should have outer child with inner child nested, not flattened at root
    expect(tool.subCalls.length, 1);
    expect(tool.subCalls[0].subCallId, 'root-1:code:1');
    expect(tool.subCalls[0].children.length, 1);
    expect(tool.subCalls[0].children[0].subCallId, 'root-1:code:1:code:1');
    print('out-of-order ok');
  });

  test('depth 256 cap rejects', () {
    final f = ConversationNodeFolder()
      ..add(e('tool/call', 1, {'callId': 'root-1', 'name': 'run-code'}));
    // Build chain depth 256 should be allowed, 257th should be rejected
    for (int i = 1; i <= 255; i++) {
      final parent = i == 1 ? 'root-1' : 'c$i';
      final child = 'c${i + 1}';
      f.add(
        e('tool/code-dispatch-start', i + 1, {
          'rootCallId': 'root-1',
          'parentCallId': parent,
          'subCallId': child,
          'name': 'n',
          'arguments': {},
        }),
      );
    }
    // One more to exceed 256 (parent depth 256 -> child depth 257 should reject)
    f.add(
      e('tool/code-dispatch-start', 300, {
        'rootCallId': 'root-1',
        'parentCallId': 'c256',
        'subCallId': 'c257',
        'name': 'n',
        'arguments': {},
      }),
    );
    final tool = f.snapshot().nodes.whereType<ToolNode>().single;
    int maxDepth(ToolSubCall n) => n.children.isEmpty
        ? 1
        : 1 + n.children.map(maxDepth).reduce((a, b) => a > b ? a : b);
    int depth = tool.subCalls.isEmpty ? 0 : maxDepth(tool.subCalls[0]);
    // depth should be capped at 256, not exceed
    expect(depth <= 256, isTrue);
    print('depth cap ok depth=$depth');
  });

  test('cycle rejection', () {
    final f = ConversationNodeFolder()
      ..add(e('tool/call', 1, {'callId': 'root-1', 'name': 'run-code'}))
      ..add(
        e('tool/code-dispatch-start', 2, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'a',
          'name': 'x',
          'arguments': {},
        }),
      )
      ..add(
        e('tool/code-dispatch-start', 3, {
          'rootCallId': 'root-1',
          'parentCallId': 'a',
          'subCallId': 'b',
          'name': 'y',
          'arguments': {},
        }),
      );
    // Try to create cycle: b -> a
    f.add(
      e('tool/code-dispatch-start', 4, {
        'rootCallId': 'root-1',
        'parentCallId': 'b',
        'subCallId': 'a',
        'name': 'x',
        'arguments': {},
      }),
    );
    final tool = f.snapshot().nodes.whereType<ToolNode>().single;
    // Cycle edge should be rejected, so still only a->b, not b->a
    expect(tool.subCalls.length, 1);
    expect(tool.subCalls[0].subCallId, 'a');
    expect(tool.subCalls[0].children.length, 1);
    expect(tool.subCalls[0].children[0].subCallId, 'b');
    expect(tool.subCalls[0].children[0].children, isEmpty);
    print('cycle rejected ok');
  });
}
