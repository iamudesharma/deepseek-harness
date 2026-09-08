/// To-dos/composer alignment tests — the panel shares the composer's exact
/// horizontal bounds (`Padding(16,0,16,8)` + `Center` +
/// `ConstrainedBox(maxWidth:780)`; see `composer.dart` card), and keeps its
/// collapse/expand behavior.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/todo_panel.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canned history: one `todo_write` call with a single completed item.
class FakeLiveHistory extends LiveHistory {
  FakeLiveHistory(this.entries);

  final List<HistoryEntry> entries;

  @override
  List<HistoryEntry> build(String arg) => entries;
}

List<HistoryEntry> _history() => [
  HistoryEntry(
    event: SessionEvent(
      type: 'tool/call',
      data: const {
        'name': 'todo_write',
        'args': {
          'todos': [
            {'content': 'Write the alignment test', 'status': 'completed'},
          ],
        },
      },
      seq: 1,
      time: 0,
    ),
  ),
];

Future<void> pumpPanel(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveHistoryProvider.overrideWith(() => FakeLiveHistory(_history())),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: TodoPanel(sessionId: 's-todo')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('panel shares the composer content bounds', (tester) async {
    await pumpPanel(tester);
    // Outer clearance identical to the composer card wrap.
    final outer = find.byWidgetPredicate(
      (w) =>
          w is Padding &&
          w.padding == const EdgeInsets.fromLTRB(16, 0, 16, 8),
    );
    expect(outer, findsOneWidget);
    // Same centered cap as the composer card.
    final cap = find.byWidgetPredicate(
      (w) =>
          w is ConstrainedBox &&
          w.constraints.maxWidth == 780,
    );
    expect(cap, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel collapses and expands without layout errors', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.text('To-dos'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);
    // Collapsed: item body hidden.
    expect(find.text('Write the alignment test'), findsNothing);

    await tester.tap(find.text('To-dos'));
    await tester.pumpAndSettle();
    expect(find.text('Write the alignment test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
