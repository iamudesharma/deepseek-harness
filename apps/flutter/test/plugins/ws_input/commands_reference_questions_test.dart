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
      final service = CommandUiService(directory: dir, execute: (_, __) async => CommandExecutionOutcome.success());
      const contrib = CommandContribution(name: 'my-cmd', description: 'desc', available: _always);
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
      host.register(ReferencePlugin(
        fetchFiles: files ?? (_, __) async => const [],
        fetchSessions: sessions ?? (_, __) async => const [],
      ));
      await host.activateAll();
      return (registry, registry.sources('@').single);
    }

    test(
        'candidates merge file and session namespaces; quoted path suppresses sessions',
        () async {
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
          const CandidateRequest(
              query: '', position: TriggerPosition.leading));
      expect(rows.map((r) => r.name),
          ['File · main.dart', 'Folder · assets/', 'Session · Fix bug']);
      expect(rows.map((r) => r.section),
          ['Files', 'Files', 'Sessions']);

      // Inside an open quoted path token sessions never answer.
      final quoted = await source.candidates('s1',
          const CandidateRequest(
              query: 'my folder',
              quoted: true,
              position: TriggerPosition.leading));
      expect(quoted.map((r) => r.section), everyElement('Files'));
    });

    test('pick decision table: directory splices text; file/session insert chips',
        () async {
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
          },
        ],
      );
      final rows = await source.candidates(
          's1',
          const CandidateRequest(
              query: '', position: TriggerPosition.leading));
      InputTriggerPick pickOf(InputTriggerCandidate c) => InputTriggerPick(
            candidate: c,
            sessionId: 's1',
            position: TriggerPosition.leading,
            via: 'menu',
            span: const TokenSpan(start: 0, end: 5, draftRev: 0),
          );

      // Directory → literal splice keeping completion open (descent). The
      // unquoted grammar: quotes appear only for whitespace paths.
      final dir = source.onPick(pickOf(rows[1])) as TextOutcome;
      expect(dir.text, '@assets/');
      expect(dir.continueTracking, isTrue);

      // File → reference chip with clipboard projection.
      final file = source.onPick(pickOf(rows[0])) as InsertOutcome;
      expect(file.insert.ref, '@lib/main.dart');
      expect(file.insert.appearance, 'file');
      expect(file.insert.clipboardText, '@lib/main.dart');

      // Session → reference chip.
      final session = source.onPick(pickOf(rows[2])) as InsertOutcome;
      expect(session.insert.ref, '@session:s9');
      expect(session.insert.appearance, 'session');
    });

    test('failing namespaces degrade to an empty candidate list', () async {
      final (_, source) = await boot(
        files: (_, __) async => throw StateError('namespace absent'),
        sessions: (_, __) async => throw StateError('namespace absent'),
      );
      final rows = await source.candidates(
          's1',
          const CandidateRequest(
              query: '', position: TriggerPosition.leading));
      expect(rows, isEmpty);
    });
  });

  group('ui-user-questions QuestionsController', () {
    test('folds requested then resolved', () async {
      final controller = QuestionsController();
      controller.requested('s1',
          rpcId: 'r1', questions: [QuestionItem(id: 'q1', question: 'Q1')]);
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

