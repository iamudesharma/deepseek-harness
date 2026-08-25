import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';

void main() {
  test('history for failing session', () async {
    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:8080');
    // Self-skip when the live host is down (matches real-API e2e posture).
    try {
      await client.hostDescribe();
    } catch (_) {
      return;
    }
    final id = SessionId('session-d68d3474-b4e6-4172-9dbb-0c41ce7d8773');
    final events = await client.getSessionEvents(id);
    print('events ${events.length}');
    for (final e in events.take(3)) {
      print('${e.event.type} ${e.event.data}');
    }
    // Also test fromJson for SessionSummary
    final sessions = await client.getSessions();
    print('sessions ${sessions.length}');
    for (final s in sessions.take(2)) {
      print('session ${s.sessionId} title ${s.title}');
    }
  });
}
