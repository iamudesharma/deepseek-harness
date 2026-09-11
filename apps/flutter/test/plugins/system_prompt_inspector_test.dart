import 'package:dsh_flutter/src/plugins/conversation/nodes/system_prompt_inspector.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// System-prompt inspector parity vectors (React `system-prompt.ts`
/// `inspectSystemPrompt` at upstream 5dda764).
SessionEventEnvelope _event(
  String type,
  int seq,
  Map<String, Object?> data, {
  Object? surfaceOp,
}) => SessionEventEnvelope.fromJson({
  'type': type,
  'seq': seq,
  'time': seq * 1000,
  'data': data,
  if (surfaceOp != null) 'surfaceOp': surfaceOp,
});

Map<String, Object?> _systemData(String text) => {
  'turn': 0,
  'step': 0,
  'message': {
    'role': 'system',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

Object _replace(int startSeq, int endSeq) =>
    {'op': 'replace', 'startSeq': startSeq, 'endSeq': endSeq};

void main() {
  group('inspectSystemPrompt', () {
    test('first append introduces without update', () {
      final state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Be brief.'),
            surfaceOp: 'append'),
      );
      expect(state.uncertain, isFalse);
      expect(state.firstSeq, 0);
      expect(state.introduced?.text, 'Be brief.');
      expect(state.introduced?.update, isFalse);
      expect(state.effective?.text, 'Be brief.');
      expect(state.nodes, hasLength(1));
      expect(state.nodes.single.position, 0);
    });

    test('append after a shown prompt flags update', () {
      var state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Be brief.'),
            surfaceOp: 'append'),
      );
      state = inspectSystemPrompt(
        state,
        _event('system/message', 6, _systemData('Be very brief.'),
            surfaceOp: 'append'),
      );
      expect(state.introduced?.update, isTrue);
      expect(state.effective?.text, 'Be very brief.');
      expect(state.effective, same(state.introduced));
    });

    test('empty content records removal', () {
      var state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Be brief.'),
            surfaceOp: 'append'),
      );
      // Removal rides a replace covering the old node (an append only
      // adds a dormant empty node; the prompt survives).
      state = inspectSystemPrompt(
        state,
        _event('system/message', 6, {
          'message': {'role': 'system', 'content': []},
        }, surfaceOp: _replace(0, 0)),
      );
      expect(state.effective, isNull);
      expect(state.nodes.where((n) => n.node.text.isNotEmpty), isEmpty);
    });

    test('replace inherits the start endpoint and prunes coverage', () {
      var state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Old.'),
            surfaceOp: 'append'),
      );
      state = inspectSystemPrompt(
        state,
        _event('system/message', 5, _systemData('New.'),
            surfaceOp: _replace(0, 0)),
      );
      expect(state.uncertain, isFalse);
      expect(state.effective?.text, 'New.');
      // Position inherited from the replaced start endpoint, not seq 5.
      expect(
        state.nodes.where((n) => n.node.text == 'New.').single.position,
        0,
      );
      expect(state.replacements[5], 0);
    });

    test('unknown older endpoint withholds until replay', () {
      // Window starts at seq 4 (firstSeq); a replace citing unseen seq 1
      // cannot be placed: the prompt is unavailable, not guessed.
      var state = inspectSystemPrompt(
        null,
        _event('user/message', 4, {'content': 'hi'}, surfaceOp: 'append'),
      );
      state = inspectSystemPrompt(
        state,
        _event('system/message', 6, _systemData('New.'),
            surfaceOp: _replace(1, 1)),
      );
      expect(state.uncertain, isTrue);
      expect(state.effective, isNull);
      expect(state.nodes, isEmpty);
    });

    test('effective identity preserved when unchanged', () {
      var state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Same.'),
            surfaceOp: 'append'),
      );
      final first = state.effective;
      state = inspectSystemPrompt(
        state,
        _event('user/message', 2, {'content': 'hi'}, surfaceOp: 'append'),
      );
      expect(state.effective, same(first));
    });

    test('non-system replace prunes covered system nodes', () {
      var state = inspectSystemPrompt(
        null,
        _event('system/message', 0, _systemData('Old.'),
            surfaceOp: 'append'),
      );
      state = inspectSystemPrompt(
        state,
        _event('user/message', 5, {'content': 'condensed'},
            surfaceOp: _replace(0, 0)),
      );
      expect(state.effective, isNull);
    });
  });
}
