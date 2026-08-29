/// ChatView scroll-ownership contract — the behaviors the mobile
/// conversation depends on, locked by test:
///
/// - new content while pinned → follow automatically;
/// - reader scrolls up → follow released (jump-to-bottom FAB appears);
/// - streaming while reading history → NO jump;
/// - reader returns near bottom → follow restored;
/// - per-session position restore across switches (incl. the route-param
///   `didUpdateWidget` path, which historically saved under the wrong key).
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data) =>
    SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

HistoryEntry _h(SessionEvent e) => HistoryEntry(event: e);

/// A transcript long enough to overflow the 420px test viewport.
List<SessionEvent> _longHistory({int count = 14}) =>
    List<SessionEvent>.generate(
      count,
      (int i) => _ev('user/message', i + 1, {'content': 'message number $i'}),
    );

ProviderContainer _seed(String sid, List<SessionEvent> events) {
  final c = ProviderContainer();
  c
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: SessionId(sid),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: false,
          blank: false,
          title: 'S $sid',
        ),
      );
  c.read(liveHistoryProvider(sid).notifier).replaceAll(events.map(_h).toList());
  return c;
}

/// Pumps ChatView inside a stateful harness whose [sessionId] can change —
/// the route-param path (`didUpdateWidget`), not a remount.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.container,
    required this.sid,
    this.height = 420,
  });

  final ProviderContainer container;
  final String sid;
  final double height;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late String sid = widget.sid;

  void switchTo(String id) => setState(() => sid = id);

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.container,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          height: widget.height,
          child: ChatView(sessionId: sid),
        ),
      ),
    ),
  );
}

Future<_HarnessState> _pump(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
  return tester.state<_HarnessState>(find.byType(_Harness));
}

void main() {
  testWidgets('pinned: appended user message auto-follows', (tester) async {
    final c = _seed('follow-a', _longHistory());
    addTearDown(c.dispose);
    await _pump(tester, _Harness(container: c, sid: 'follow-a'));

    // Pinned at the tip: the last message is visible, no FAB.
    expect(find.text('message number 13'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

    // Append a new user message while pinned → follows automatically.
    c
        .read(liveHistoryProvider('follow-a').notifier)
        .appendLive(_h(_ev('user/message', 15, {'content': 'fresh tail'})));
    await tester.pumpAndSettle();
    expect(find.text('fresh tail'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
  });

  testWidgets('reader scrolls up: follow released, FAB appears', (
    tester,
  ) async {
    final c = _seed('release-a', _longHistory());
    addTearDown(c.dispose);
    await _pump(tester, _Harness(container: c, sid: 'release-a'));

    await tester.drag(find.text('message number 13'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('message number 0'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('streaming while reading history does not jump', (tester) async {
    final c = _seed('nojump-a', _longHistory());
    addTearDown(c.dispose);
    await _pump(tester, _Harness(container: c, sid: 'nojump-a'));

    await tester.drag(find.text('message number 13'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('message number 0'), findsOneWidget);

    // Streaming growth at the tip while the reader is in history: the
    // viewport must not move.
    c
        .read(liveHistoryProvider('nojump-a').notifier)
        .appendLive(
          _h(
            _ev('assistant/chunk', 15, {
              'turn': 2,
              'step': 1,
              'chunk': {
                'type': 'text-delta',
                'index': 0,
                'text': 'streaming tail',
              },
            }),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('message number 0'), findsOneWidget);
    expect(find.textContaining('streaming tail'), findsNothing);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('returning near bottom restores follow', (tester) async {
    final c = _seed('return-a', _longHistory());
    addTearDown(c.dispose);
    await _pump(tester, _Harness(container: c, sid: 'return-a'));

    await tester.drag(find.text('message number 13'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    // Reader returns to the tip via the FAB → follow restored.
    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

    // New tail content follows again without a FAB.
    c
        .read(liveHistoryProvider('return-a').notifier)
        .appendLive(_h(_ev('user/message', 15, {'content': 'after return'})));
    await tester.pumpAndSettle();
    expect(find.text('after return'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
  });

  testWidgets('session switch: per-session restore on the param path', (
    tester,
  ) async {
    final c = _seed('switch-a', _longHistory());
    addTearDown(c.dispose);
    c
        .read(sessionsProvider.notifier)
        .addSession(
          SessionSummary(
            sessionId: SessionId('switch-b'),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            running: false,
            blank: false,
            title: 'S switch-b',
          ),
        );
    c.read(liveHistoryProvider('switch-b').notifier).replaceAll(<HistoryEntry>[
      _h(_ev('user/message', 1, {'content': 'B tail message'})),
    ]);

    final state = await _pump(tester, _Harness(container: c, sid: 'switch-a'));

    // Reader scrolls A into history.
    await tester.drag(find.text('message number 13'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    // A → B: B mounts pinned at its own tip.
    state.switchTo('switch-b');
    await tester.pumpAndSettle();
    expect(find.text('B tail message'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

    // B → A: the saved reader position comes back (FAB present, first
    // message visible again) — not the tip.
    state.switchTo('switch-a');
    await tester.pumpAndSettle();
    expect(find.text('message number 0'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });
}
