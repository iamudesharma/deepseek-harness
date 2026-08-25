import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repro fold', () {
    final lines = File('test/goldens/replay/parity-stream.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty);
    final folder = ConversationNodeFolder();
    for (final line in lines) {
      final wire = jsonDecode(line) as Map<String, dynamic>;
      if (wire['stream'] != 'mux') continue;
      final frame = MuxFrame.fromJson((wire['frame'] as Map).cast<String, Object?>());
      if (frame is! SessionEventFrame) continue;
      final ev = frame.event;
      if (ev['type'] == 'assistant/chunk') {
        // ignore: avoid_print
        print('CHUNK seq=${ev['seq']} turn=${(ev['data'] as Map)['turn']}');
      }
      try {
        folder.add(SessionEventEnvelope.fromJson(ev));
      } catch (e) {
        fail('seq=${ev['seq']} type=${ev['type']} → $e');
      }
    }
  });
}
