import 'package:dsh_flutter/src/core/events/tool_stream.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real wire shapes: `assistant/chunk` events carry `{turn, step, chunk}` —
/// the same StreamChunk union the React PartialAccumulator folds
/// (packages/client/runtime/src/client/sessions/partial.ts; chunk fixtures
/// from packages/llm/llm/tests/assembler.spec.ts and
/// packages/core/agent-loop/tests/mock-adapter.ts).
Map<String, Object?> _chunkEvent({
  required int seq,
  required Map<String, Object?> chunk,
}) =>
    {
      'type': 'assistant/chunk',
      'seq': seq,
      'time': 0,
      'data': {'turn': 1, 'step': 1, 'chunk': chunk},
    };

void main() {
  group('decodeAssistantChunk', () {
    test('decodes the delta variants the model stream produces', () {
      final tool = decodeAssistantChunk(const {
        'type': 'tool-call-delta',
        'index': 2,
        'id': 'call-1',
        'name': 'echo',
        'argumentsDelta': '{"text":',
      }) as ToolCallDeltaChunk;
      expect(tool.index, 2);
      expect(tool.id, 'call-1');
      expect(tool.name, 'echo');
      expect(tool.argumentsDelta, '{"text":');

      expect(decodeAssistantChunk(const {'type': 'text-delta', 'text': 'hi'}),
          isA<TextDeltaChunk>());
      expect(
          decodeAssistantChunk(
              const {'type': 'reasoning-delta', 'text': 'th'}),
          isA<ReasoningDeltaChunk>());
    });

    test('unknown variants degrade instead of throwing', () {
      final other = decodeAssistantChunk(const {'type': 'usage', 'tokens': 3});
      expect(other, isA<OtherChunk>());
      expect(decodeAssistantChunk('garbage'), isA<OtherChunk>());
    });
  });

  group('ToolStreamAccumulator (partial.ts fold semantics)', () {
    test('accumulates callId, name, and argsRaw across fragments', () {
      final acc = ToolStreamAccumulator();
      acc.fold(decodeAssistantChunk(const {
        'type': 'tool-call-delta',
        'index': 0,
        'id': 'call-1',
        'name': 'echo',
        'argumentsDelta': '{"text":',
      }));
      acc.fold(decodeAssistantChunk(const {
        'type': 'tool-call-delta',
        'index': 0,
        'argumentsDelta': '"hi"}',
      }));
      final partial = acc.snapshot().single;
      // First non-empty id wins; later continuation deltas carry empty ids.
      expect(partial.callId, 'call-1');
      expect(partial.name, 'echo');
      expect(partial.argsRaw, '{"text":"hi"}');
    });

    test('keeps block-level identity per index; non-deltas change nothing',
        () {
      final acc = ToolStreamAccumulator();
      acc.fold(const TextDeltaChunk('ignored here'));
      expect(acc.snapshot(), isEmpty);
      acc.fold(decodeAssistantChunk(const {
        'type': 'tool-call-delta',
        'index': 0,
        'id': 'c1',
        'argumentsDelta': '{}',
      }));
      acc.fold(decodeAssistantChunk(const {
        'type': 'tool-call-delta',
        'index': 1,
        'id': 'c2',
        'name': 'read',
        'argumentsDelta': '{"pa',
      }));
      final blocks = acc.snapshot();
      expect(blocks.length, 2);
      expect(blocks[0].callId, 'c1');
      expect(blocks[1].argsRaw, '{"pa');
      // Snapshot compaction keeps index order stable.
      expect(blocks[0].argsRaw, '{}');
    });
  });

  group('ConversationNodeFolder tool-call-delta folding', () {
    test('argument deltas surface on the in-flight assistant node and settle '
        'with its message', () {
      final folder = ConversationNodeFolder();
      folder.add(SessionEventEnvelope.fromJson(_chunkEvent(
        seq: 5,
        chunk: const {
          'type': 'tool-call-delta',
          'index': 0,
          'id': 'call-1',
          'name': 'bash',
          'argumentsDelta': '{"comm',
        },
      )));
      folder.add(SessionEventEnvelope.fromJson(_chunkEvent(
        seq: 6,
        chunk: const {
          'type': 'tool-call-delta',
          'index': 0,
          'argumentsDelta': 'and":"ls"}',
        },
      )));

      final inFlight = folder.snapshot().nodes.whereType<AssistantNode>()
          .singleWhere((n) => n.key == 'a-turn1-step1');
      expect(inFlight.streaming, isTrue);
      expect(inFlight.partialToolCalls.single.callId, 'call-1');
      expect(inFlight.partialToolCalls.single.name, 'bash');
      expect(
          inFlight.partialToolCalls.single.argsRaw, '{"command":"ls"}');

      // The settled message supersedes the partial projection.
      folder.add(SessionEventEnvelope.fromJson({
        'type': 'assistant/message',
        'seq': 7,
        'time': 0,
        'sourceEventSeqs': [5, 6],
        'data': {
          'turn': 1,
          'step': 1,
          'message': {'role': 'assistant', 'content': []},
        },
      }));
      final settled = folder.snapshot().nodes.whereType<AssistantNode>()
          .singleWhere((n) => n.key == 'a-turn1-step1');
      expect(settled.streaming, isFalse);
      expect(settled.partialToolCalls, isEmpty);
    });

    test('text chunks keep their historical append behavior byte-for-byte',
        () {
      final folder = ConversationNodeFolder();
      folder.add(SessionEventEnvelope.fromJson(_chunkEvent(
        seq: 1,
        chunk: const {'type': 'text-delta', 'text': 'Hel'},
      )));
      folder.add(SessionEventEnvelope.fromJson(_chunkEvent(
        seq: 2,
        chunk: const {'type': 'reasoning-delta', 'text': 'why'},
      )));

      final node = folder.snapshot().nodes.whereType<AssistantNode>()
          .singleWhere((n) => n.key == 'a-turn1-step1');
      expect(node.text, 'Helwhy');
      expect(node.partialToolCalls, isEmpty);
    });
  });
}
