import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/api/host_description.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/transcript_fold.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0 exit criterion (migration/plan.md): one real live-host path proving
/// live frames flow through the same protocol parsers and the same runtime
/// fold as the replay harness — no second parsing path.
///
/// Boots the production `dsh web` binary keylessly (placeholder API key; the
/// prompt's provider call fails, which is itself real live frame traffic:
/// turn lifecycle + error finalization), connects the app's own
/// [ConnectionClient], folds every mux frame through [TranscriptFolder], and
/// asserts the structural transcript invariants.
void main() {
  final binPath = File('../../apps/cli/lib/bin.js').absolute.path;
  final built = File(binPath).existsSync();

  test('live host: describe → session → prompt frames fold through the P0 pipeline', () async {
    if (!built) {
      // Loud, explicit skip posture mirroring apps/web/tests requireDist():
      // the lane needs the built workspace, never a silent pass.
      fail('live-host E2E needs the built dsh bin at apps/cli/lib/bin.js — run pnpm run build');
    }

    final world = await Directory.systemTemp.createTemp('dsh-flutter-live-');
    final process = await Process.start(
      'node',
      [binPath, 'web', '--no-open', '--port', '0'],
      workingDirectory: world.path,
      environment: {
        'DEEPSEEK_API_KEY': 'keyless-p0-live-no-call',
        'DSH_HOME': '${world.path}/.dsh',
      },
    );
    final baseUrl = await _waitForBaseUrl(process.stdout);
    final client = ConnectionClient(baseUrl: baseUrl);

    try {
      // 1. Unary carrier through the RPC envelope parser.
      final description = HostDescription.fromJson(await client.hostDescribe());
      expect(description.version, isNotEmpty);
      expect(description.canOpenPath, isA<bool>());

      // 2. Live mux stream folded exactly like replay: controller-style pump →
      // MuxFrame.fromJson → TranscriptFolder. No raw-map side channel exists.
      final folder = TranscriptFolder();
      final rawFrames = <Map<String, dynamic>>[];
      final sawSubscribe = Completer<void>();
      final sub = client.eventsMux().listen((envelope) {
        rawFrames.add(envelope);
        final frame = MuxFrame.fromJson(envelope);
        folder.add(frame);
        if (frame is SessionSubscribedFrame && !sawSubscribe.isCompleted) {
          sawSubscribe.complete();
        }
      });

      // 3. Drive a real session with a prompt whose provider call fails on the
      // placeholder key — the failure path still emits the full turn lifecycle.
      final sessionId = await client.createSession(cwd: world.path);
      await client.sendMessage(sessionId: sessionId, content: 'ping');

      await sawSubscribe.future.timeout(const Duration(seconds: 15));
      await _waitForCondition(
        () => folder.snapshot().contains('turn/end'),
        timeout: const Duration(seconds: 45),
      );

      // 4. Structural transcript invariants over LIVE traffic.
      final snapshot = folder.snapshot();
      expect(snapshot, contains('subscribe $sessionId lastSeq='));
      expect(snapshot, contains('user/message append'));
      expect(snapshot, contains('turn/start turn='));
      expect(snapshot, contains('turn/end turn='));
      // Typed-node pipeline: the same frames also fold through
      // ConversationNodeFolder (shared with the replay harness) without any
      // refusal — proving one parsing path across live and replay.
      // Typed-node pipeline: the same live frames fold through
      // ConversationNodeFolder (shared with the replay harness) without any
      // refusal — one parsing path across live and replay.
      final nodeFolder = ConversationNodeFolder();
      for (final frame in rawFrames) {
        if ((frame['type'] as String?) != 'session/event') continue;
        final inner = (frame['event'] as Map).cast<String, Object?>();
        nodeFolder.add(SessionEventEnvelope.fromJson(inner));
      }
      expect(nodeFolder.snapshot().nodes, isNotEmpty,
          reason: 'live session events must fold into typed nodes');
      // Every envelope decoded as a known-or-ignorable event: the folder
      // throws on unrecognized required types, so reaching here proves the
      // required-on-read gate held across the whole live stream.

      // 5. Determinism: refolding the captured raw frames reproduces the
      // snapshot byte-for-byte (same parsers, same fold).
      final refolded = TranscriptFolder();
      for (final envelope in rawFrames) {
        refolded.add(MuxFrame.fromJson(envelope));
      }
      expect(refolded.snapshot(), folder.snapshot());

      sub.cancel();
    } finally {
      client.dispose();
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await world.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Parses stdout until the host prints its bind URL (`dsh web: http://…`).
Future<String> _waitForBaseUrl(Stream<List<int>> out) async {
  final completer = Completer<String>();
  late final StreamSubscription<String> sub;
  sub = out
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    final match = RegExp(r'dsh web: (http://\S+)').firstMatch(line);
    if (match != null && !completer.isCompleted) completer.complete(match.group(1)!);
  });
  final url = await completer.future.timeout(const Duration(seconds: 60));
  await sub.cancel();
  return url;
}

Future<void> _waitForCondition(bool Function() condition, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within ${timeout.inSeconds}s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
