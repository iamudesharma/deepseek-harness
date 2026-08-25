import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';

void main() {
  test('chrome messagesFromHistory with real history', () async {
    const raw = r"""[
  {
    "event": {
      "type": "permission/preset",
      "seq": 0,
      "time": 1787210597318,
      "data": {"preset": "workspace-write"}
    }
  },
  {
    "event": {
      "type": "assistant/chunk",
      "seq": 6,
      "time": 1787210597513,
      "data": {"turn": 1, "step": 1, "chunk": {"type": "usage", "usage": {"inputTokens": 0, "outputTokens": 0}}}
    }
  }
]""";
    final List<dynamic> arr = jsonDecode(raw) as List;
    final entries = arr.map((e) => HistoryEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
    final messages = messagesFromHistory(entries);
    expect(messages, isA<List<Message>>());
  });
}
