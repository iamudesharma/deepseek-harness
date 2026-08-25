import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/transcript_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the recorded stream fixture: one JSON line per delivered frame,
/// tagged with its logical stream.
List<({String stream, Object frame})> loadRecordedStream() {
  const fixturePath = 'test/fixtures/session-stream.jsonl';
  final lines = File(fixturePath).readAsLinesSync().where((l) => l.trim().isNotEmpty);
  return [
    for (final line in lines)
      () {
        final wire = jsonDecode(line) as Map<String, dynamic>;
        final frameWire = (wire['frame'] as Map).cast<String, Object?>();
        return (
          stream: wire['stream'] as String,
          frame: switch (wire['stream']) {
            'mux' => MuxFrame.fromJson(frameWire),
            'host' => HostFrame.fromJson(frameWire),
            _ => throw ArgumentError('unknown stream tag ${wire['stream']}'),
          },
        );
      }(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final recorded = loadRecordedStream();

  test('fixture decodes entirely through the extracted protocol parsers', () {
    expect(recorded, hasLength(23));
    expect(recorded.where((r) => r.stream == 'mux'), hasLength(16));
    expect(recorded.where((r) => r.stream == 'host'), hasLength(7));
    // Every entry decoded to a sealed frame type — no raw maps survive.
    for (final entry in recorded) {
      expect(entry.frame, isA<Object>());
      expect(entry.frame is MuxFrame || entry.frame is HostFrame, isTrue);
    }
  });

  test('folding is deterministic across runs', () {
    final a = TranscriptFolder()..forEachRecorded(recorded);
    final b = TranscriptFolder()..forEachRecorded(recorded);
    expect(a.snapshot(), equals(b.snapshot()));
    expect(a.length, 20); // 23 frames: 3 chunks coalesce into their message.
  });

  group('streaming discipline', () {
    SessionEventFrame chunkFrame(int seq) => SessionEventFrame(
          sessionId: const SessionId('s-9'),
          event: {
            'type': 'assistant/chunk',
            'seq': seq,
            'time': 0,
            'data': {'turn': 2, 'step': 1, 'chunk': {'text': 'x'}},
          },
        );

    test('partial → cumulative → completed: chunks coalesce into the settled node', () {
      final folder = TranscriptFolder()
        ..add(chunkFrame(1))
        ..add(chunkFrame(2))
        ..add(SessionEventFrame(
          sessionId: const SessionId('s-9'),
          event: {
            'type': 'assistant/message',
            'seq': 3,
            'time': 0,
            'data': {'turn': 2, 'step': 1, 'message': {'role': 'assistant'}},
          },
        ));

      // No per-chunk lines: in-flight state stays out of the transcript until
      // the settled message lands, which reports the coalesced count.
      expect(folder.length, 1);
      expect(folder.snapshot(), contains('chunks=2'));
    });

    test('a chunk arriving after its step settled is a loud violation', () {
      final folder = TranscriptFolder()..add(chunkFrame(1));
      folder.add(SessionEventFrame(
        sessionId: const SessionId('s-9'),
        event: {
          'type': 'assistant/message',
          'seq': 2,
          'time': 0,
          'data': {'turn': 2, 'step': 1, 'message': {}},
        },
      ));
      expect(() => folder.add(chunkFrame(3)),
          throwsA(predicate((e) => e is StateError && e.message.contains('settled'))));
    });

    test('required-unknown events refuse; ignorable unknowns skip', () {
      final folder = TranscriptFolder();
      expect(
        () => folder.add(SessionEventFrame(
          sessionId: const SessionId('s-9'),
          event: {'type': 'agent-team/journal', 'seq': 1, 'time': 0, 'data': {}},
        )),
        throwsA(predicate((e) => e is StateError && e.message.contains('refusing reconstruction'))),
      );

      folder.add(SessionEventFrame(
        sessionId: const SessionId('s-9'),
        event: {'type': 'plugin/heartbeat', 'seq': 2, 'time': 0, 'data': {}, 'ignorable': true},
      ));
      expect(folder.snapshot(), contains('ignorable-skip'));
    });
  });

  testWidgets('recorded stream renders through host → slots → outlet as a stable snapshot',
      (tester) async {
    final folder = TranscriptFolder()..forEachRecorded(recorded);
    final host = buildReplayHost(folder);
    await host.activateAll();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlotVersionBuilder(
            registry: host.slots,
            builder: (context, version) =>
                SlotOutlet(registry: host.slots, slotKey: 'replay.transcript'),
          ),
        ),
      ),
    );
    await tester.pump();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    // Byte-stable transcript snapshot — change here means a contract or fold
    // change, never formatting drift.
    expect(rendered.join('\n'), kExpectedTranscriptSnapshot);

    host.deactivateAll();
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });
}

extension on TranscriptFolder {
  void forEachRecorded(List<({String stream, Object frame})> recorded) {
    for (final entry in recorded) {
      add(entry.frame);
    }
  }
}

const String kExpectedTranscriptSnapshot =
    'subscribe s-100 lastSeq=6\n'
    'host session-added s-100 blank=true\n'
    'event s-100 seq=1 turn/start turn=1\n'
    'event s-100 seq=2 user/message append\n'
    'event s-100 seq=3 tool/call call=c-1 name=bash\n'
    'event s-100 seq=4 tool/result result=c-1\n'
    'queue s-100 items=1\n'
    'approval-requested s-100 write\n'
    'approval-resolved s-100 approved-once\n'
    'projection s-100 todos@2\n'
    'event s-100 seq=8 assistant/message chunks=3\n'
    'event s-100 seq=9 turn/end turn=1 reason=completed\n'
    'event s-100 seq=10 plugin/heartbeat ignorable-skip\n'
    'jobs s-100 count=0\n'
    'host session-status s-100 running=true\n'
    'host workspace-changed w-9\n'
    'host workspace-order-changed count=1\n'
    'host archived-sessions-changed count=0\n'
    'host remote-event some/host/event\n'
    'host session-status s-100 running=false';
