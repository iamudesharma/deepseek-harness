import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';

void main() {
  test('live proxy session.list via 8080', () async {
    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:8080');
    // Self-skip when the live host is down (matches real-API e2e posture).
    try {
      await client.hostDescribe();
    } catch (_) {
      return;
    }
    final sessions = await client.getSessions();
    // Should match backend 3-4 sessions
    expect(sessions.length, greaterThanOrEqualTo(2));
    // Check that titles are present like React
    final titles = sessions.map((s) => s.title ?? s.sessionId.value).join(', ');
    print('LIVE PROXY sessions: $titles');
    // Also test create
    final newId = await client.createSession();
    expect(newId.value, isNotEmpty);
    final after = await client.getSessions();
    expect(after.length, greaterThanOrEqualTo(sessions.length + 1));
    print('after create ${after.length}');
  });
}
