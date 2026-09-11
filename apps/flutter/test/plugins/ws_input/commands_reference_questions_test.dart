import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/commands/command_directory.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:dsh_flutter/src/plugins/reference/reference_plugin.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

void main() {
  group('ui-commands CommandUiService', () {
    test('register duplicate throws; disposer removes', () {
      final dir = CommandDirectory(fetchCommands: (_) async => []);
      final service = CommandUiService(
        directory: dir,
        execute: (_, __) async => CommandExecutionOutcome.success(),
      );
      const contrib = CommandContribution(
        name: 'my-cmd',
        description: 'desc',
        available: _always,
      );
      final dispose = service.register(contrib);
      expect(() => service.register(contrib), throwsStateError);
      dispose();
      expect(service.contributionNames, isEmpty);
    });

    test('fuzzyScore ranks prefix before substring', () {
      final candidates = [
        const InputTriggerCandidate(name: 'my-cmd'),
        const InputTriggerCandidate(name: 'my-cmd-long'),
      ];
      final ranked = fuzzyCandidates(candidates, 'my');
      expect(ranked.first.name, 'my-cmd');
    });
  });

  group('ui-reference real plugin (apply → @ source → decision table)', () {
    Future<(TriggerSourceRegistry, InputTriggerSource)> boot({
      Future<List<Map<String, Object?>>> Function(String, String)? files,
      Future<List<Map<String, Object?>>> Function(String, String)? sessions,
    }) async {
      final host = PluginHost();
      host.provide('slots', host.slots);
      host.provide('connection', WsInputRecordingClient());
      final registry = TriggerSourceRegistry();
      host.provide('inputTriggers', registry);
      host.register(
        ReferencePlugin(
          fetchFiles: files ?? (_, __) async => const [],
          fetchSessions: sessions ?? (_, __) async => const [],
        ),
      );
      await host.activateAll();
      return (registry, registry.sources('@').single);
    }

    test('candidates merge file and session namespaces; quoted path suppresses sessions', () async {
      final (_, source) = await boot(
        files: (_, __) async => [
          {'path': 'lib/main.dart', 'kind': 'file'},
          {'path': 'assets', 'kind': 'directory'},
        ],
        sessions: (_, __) async => [
          {
            'sessionId': 's9',
            'label': 'Fix bug',
            'mention': '@session:s9',
            'cwd': '/w',
            'createdAt': 1724000000000,
          },
        ],
      );
      final rows = await source.candidates(
        's1',
        const CandidateRequest(query: '', position: TriggerPosition.leading),
      );
      // React fileCandidate shapes: the name carries the trailing slash for
      // directories, the location is the parent alone (nothing at the root),
      // icons drill/section/value ride the candidate.
      expect(rows.map((r) => r.name), ['main.dart', 'assets/', 'Fix bug']);
      expect(rows.map((r) => r.section), ['Files', 'Files', 'Sessions']);
      expect(rows.map((r) => r.icon), ['file', 'folder', 'session']);
      expect(rows[1].drill, isTrue);
      expect(rows[0].drill, isNull);
      expect(rows[0].description, 'lib');
      expect(rows[2].description, isNotNull);

      // Inside an open quoted path token sessions never answer.
      final quoted = await source.candidates(
        's1',
        const CandidateRequest(
          query: 'my folder',
          quoted: true,
          position: TriggerPosition.leading,
        ),
      );
      expect(quoted.map((r) => r.section), everyElement('Files'));
    });

    test(
      'pick decision table: drill descends, settling pick inserts chips',
      () async {
        final (_, source) = await boot(
          files: (_, __) async => [
            {'path': 'lib/main.dart', 'kind': 'file'},
            {'path': 'assets', 'kind': 'directory'},
          ],
          sessions: (_, __) async => [
            {'sessionId': 's9', 'label': 'Fix bug', 'mention': '@session:s9'},
          ],
        );
        final rows = await source.candidates(
          's1',
          const CandidateRequest(query: '', position: TriggerPosition.leading),
        );
        InputTriggerPick pickOf(
          InputTriggerCandidate c, [
          PickAction action = PickAction.pick,
        ]) =>
            InputTriggerPick(
              candidate: c,
              sessionId: 's1',
              position: TriggerPosition.leading,
              via: 'menu',
              action: action,
              span: const TokenSpan(start: 0, end: 5, draftRev: 0),
            );

        // Directory drill → literal splice keeping completion open. The
        // unquoted grammar: quotes appear only for whitespace paths.
        final descent =
            source.onPick(pickOf(rows[1], PickAction.drill)) as TextOutcome;
        expect(descent.text, '@assets/');
        expect(descent.continueTracking, isTrue);

        // Directory settling pick → atomic folder reference chip with the
        // trailing slash on the label (React onPick).
        final folder =
            source.onPick(pickOf(rows[1])) as InsertOutcome;
        expect(folder.insert.appearance, 'folder');
        expect(folder.insert.label, 'assets/');
        expect(folder.insert.ref, '@assets/');

        // File → reference chip with clipboard projection.
        final file = source.onPick(pickOf(rows[0])) as InsertOutcome;
        expect(file.insert.ref, '@lib/main.dart');
        expect(file.insert.appearance, 'file');
        expect(file.insert.clipboardText, '@lib/main.dart');

        // Session → reference chip.
        final session = source.onPick(pickOf(rows[2])) as InsertOutcome;
        expect(session.insert.ref, '@session:s9');
        expect(session.insert.appearance, 'session');
      },
    );

    test('header crumbs: only drilled slash queries publish a trail', () async {
      final (_, source) = await boot(
        files: (_, __) async => [
          {'path': 'assets/logo.png', 'kind': 'file'},
        ],
        sessions: (_, __) async => const [],
      );
      // Typing never publishes: the draft carries its own context.
      expect(
        source.header?.call(
          's1',
          const HeaderRequest(query: 'assets/', drilled: false),
        ),
        isNull,
      );
      // A drill without a slash has no trail either.
      expect(
        source.header?.call(
          's1',
          const HeaderRequest(query: 'assets', drilled: true),
        ),
        isNull,
      );
      // A drill descent publishes root + segments with the last current.
      final crumbs = source.header?.call(
        's1',
        const HeaderRequest(query: 'assets/', drilled: true),
      );
      expect(crumbs, isNotNull);
      expect(crumbs!.first.label, 'Workspace');
      expect(crumbs.last.label, 'assets');
      expect(crumbs.last.current, isTrue);
      // While drilled, rows drop their location (the header carries it).
      final drilledRows = await source.candidates(
        's1',
        const CandidateRequest(
          query: 'assets/',
          position: TriggerPosition.leading,
          drilled: true,
        ),
      );
      expect(
        drilledRows
            .where((r) => r.section == 'Files')
            .map((r) => r.description),
        everyElement(isNull),
      );
    });

    test('failing namespaces degrade to an empty candidate list', () async {
      final (_, source) = await boot(
        files: (_, __) async => throw StateError('namespace absent'),
        sessions: (_, __) async => throw StateError('namespace absent'),
      );
      final rows = await source.candidates(
        's1',
        const CandidateRequest(query: '', position: TriggerPosition.leading),
      );
      expect(rows, isEmpty);
    });
  });

  group('ui-user-questions QuestionsController', () {
    test('folds requested then resolved', () async {
      final controller = QuestionsController();
      controller.requested(
        's1',
        rpcId: 'r1',
        questions: [QuestionItem(id: 'q1', question: 'Q1')],
      );
      expect(controller.state['s1'], isNotNull);
      expect(controller.state['s1']!.rpcId, 'r1');
      controller.resolved('s1', 'r1', 'answered');
      expect(controller.state['s1'], isNull);
    });

    test('user_questions host provides pending question carrier', () async {
      final host = wsInputHost();
      await host.activateAll();
      expect(host.slots.isDeclared('root'), isTrue);
    });
  });
}

bool _always(SessionId _) => true;
