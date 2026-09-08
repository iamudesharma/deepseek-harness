/// Session stats line widget tests — bounds, empty collapse, and a
/// single-turn stream rendering through the real folder fold.
library;

import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart'
    show kConversationEn, kConversationNamespace, kConversationZh;
import 'package:dsh_flutter/src/plugins/conversation/ui/session_stats_line.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStatsHistory extends LiveHistory {
  FakeStatsHistory(this.entries);

  final List<HistoryEntry> entries;

  @override
  List<HistoryEntry> build(String arg) => entries;
}

HistoryEntry _event(String type, int seq, Map<String, dynamic> data, int time) {
  return HistoryEntry(
    event: SessionEvent(type: type, data: data, seq: seq, time: time),
  );
}

Future<void> pumpLine(
  WidgetTester tester,
  List<HistoryEntry> entries,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveHistoryProvider.overrideWith(() => FakeStatsHistory(entries)),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: SessionStatsLine(sessionId: 's-stats')),
      ),
    ),
  );
  // The bare scope has no plugin activation: register the conversation
  // dictionaries the line's copy comes from (production does this in
  // `ConversationPlugin.apply`).
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SessionStatsLine)),
  );
  container
      .read(localeServiceProvider)
      .register(kConversationNamespace, {'zh': kConversationZh, 'en': kConversationEn});
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty history renders nothing', (tester) async {
    await pumpLine(tester, const []);
    expect(find.textContaining('turn'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one turn renders the counts group in composer bounds', (
    tester,
  ) async {
    await pumpLine(tester, [
      _event('turn/start', 1, {'turn': 1}, 0),
      _event('step/start', 2, {'turn': 1, 'step': 1}, 0),
      _event('turn/end', 3, {'turn': 1}, 8000),
    ]);
    // Default locale is zh: '1 轮 · 1 步' (+ 'LLM 8s' from runMs).
    expect(find.textContaining('轮'), findsOneWidget);
    // Same horizontal bounds as the composer card and todo panel.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Padding &&
            w.padding == const EdgeInsets.fromLTRB(16, 0, 16, 8),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 780,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
