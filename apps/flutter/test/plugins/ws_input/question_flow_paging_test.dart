/// Generic question-flow behavior beyond submit/cancel coverage: the
/// recommended-suffix split, the one-question-per-page flow with the pager,
/// skip (including skip-on-last-page submitting), and the custom answer
/// replacing a single-select choice.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/user_questions/locales.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/question_node_card.dart'
    show QuestionNodeCard, bindQuestionClient, parseRecommendedLabel;
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

SessionSummary _summary(String id) => SessionSummary(
  sessionId: SessionId(id),
  updatedAt: 0,
  running: false,
  blank: false,
);

ProviderContainer _containerWithSession(String sid) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(sessionsProvider.notifier).addSession(_summary(sid));
  container.read(sessionsProvider.notifier).setCurrent(SessionId(sid));
  container.read(localeServiceProvider).register(kQuestionNamespace, {
    'zh': kQuestionZh,
    'en': kQuestionEn,
  });
  container.read(localeServiceProvider).setLocale('en');
  return container;
}

List<QuestionItem> _twoQuestions() => [
  QuestionItem.fromJson(const {
    'id': 'q1',
    'question': 'Which database?',
    'options': [
      {'label': 'Postgres'},
      {'label': 'SQLite'},
    ],
  }),
  QuestionItem.fromJson(const {
    'id': 'q2',
    'question': 'Which cache?',
    'options': [
      {'label': 'Redis'},
      {'label': 'Memcached'},
    ],
  }),
];

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: QuestionNodeCard())),
  ),
);

void main() {
  test('recommended suffix splits from the answer label', () {
    expect(parseRecommendedLabel('Mobile app (Recommended)'), (
      label: 'Mobile app',
      recommended: true,
    ));
    expect(parseRecommendedLabel('低端 Android（推荐）'), (
      label: '低端 Android',
      recommended: true,
    ));
    expect(parseRecommendedLabel('Web console'), (
      label: 'Web console',
      recommended: false,
    ));
  });

  testWidgets('single-select advances to the next page and skip submits the rest', (
    tester,
  ) async {
    final client = WsInputRecordingClient();
    bindQuestionClient(client);
    addTearDown(() => bindQuestionClient(null));
    final container = _containerWithSession('s-100');
    container
        .read(pendingQuestionsProvider.notifier)
        .requested('s-100', rpcId: 'm10', questions: _twoQuestions());

    await _pump(tester, container);
    expect(find.text('1 / 2'), findsOneWidget);

    // Choosing a single-select option advances immediately (React `choose`).
    await tester.tap(find.byKey(const ValueKey('option-q1-Postgres')));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Which cache?'), findsOneWidget);

    // Skipping the last page submits the batch: q1 answered, q2 empty.
    await tester.tap(find.byKey(const ValueKey('question-skip')));
    await tester.pumpAndSettle();
    expect(client.responds.single.decodedValue, {
      'sessionId': 's-100',
      'answer': {
        'answers': [
          {
            'id': 'q1',
            'selected': ['Postgres'],
          },
          {'id': 'q2', 'selected': <String>[]},
        ],
      },
    });
    expect(find.byKey(const ValueKey('question-card')), findsNothing);
  });

  testWidgets('custom answer replaces a single-select choice on the wire', (
    tester,
  ) async {
    final client = WsInputRecordingClient();
    bindQuestionClient(client);
    addTearDown(() => bindQuestionClient(null));
    final container = _containerWithSession('s-100');
    container
        .read(pendingQuestionsProvider.notifier)
        .requested(
          's-100',
          rpcId: 'm10',
          questions: [
            QuestionItem.fromJson(const {
              'id': 'q1',
              'question': 'Which database?',
              'options': [
                {'label': 'Postgres'},
                {'label': 'SQLite'},
              ],
            }),
          ],
        );

    await _pump(tester, container);
    await tester.tap(find.byKey(const ValueKey('option-q1-Postgres')));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      'DuckDB please',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-submit')));
    await tester.pumpAndSettle();

    // React `submitDrafts`: a non-empty custom clears the selection unless
    // the question is multi-select.
    expect(client.responds.single.decodedValue, {
      'sessionId': 's-100',
      'answer': {
        'answers': [
          {
            'id': 'q1',
            'selected': <String>[],
            'custom': 'DuckDB please',
          },
        ],
      },
    });
  });

  testWidgets('multi-select keeps every checked label', (tester) async {
    final client = WsInputRecordingClient();
    bindQuestionClient(client);
    addTearDown(() => bindQuestionClient(null));
    final container = _containerWithSession('s-100');
    container
        .read(pendingQuestionsProvider.notifier)
        .requested(
          's-100',
          rpcId: 'm10',
          questions: [
            QuestionItem.fromJson(const {
              'id': 'q1',
              'question': 'What hurts?',
              'multiSelect': true,
              'options': [
                {'label': 'Jank'},
                {'label': 'Latency'},
              ],
            }),
          ],
        );

    await _pump(tester, container);
    await tester.tap(find.byKey(const ValueKey('option-q1-Jank')));
    await tester.tap(find.byKey(const ValueKey('option-q1-Latency')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-submit')));
    await tester.pumpAndSettle();

    expect(client.responds.single.decodedValue, {
      'sessionId': 's-100',
      'answer': {
        'answers': [
          {
            'id': 'q1',
            'selected': ['Jank', 'Latency'],
          },
        ],
      },
    });
  });
}
