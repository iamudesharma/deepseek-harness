/// P2.2 surface goldens — representative migrated-surface states rendered
/// through the production widgets and pinned as golden evidence.
///
/// Chat goldens fold the canonical `parity-stream.jsonl` fixture (the same
/// bytes the semantic-parity drivers consume) through the production parsers
/// into `liveHistoryProvider`, so the pixels come from the real replay state:
/// user bubble, assistant reasoning+text, tool ok/error cards, model-retry
/// marker (started), and the recovered second-turn assistant. Subcall rows
/// inside tool cards are NOT rendered yet — that is the tracked
/// `tool.subcall-topology` UI leg; this suite documents today's flat card.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart'
    show liveHistoryProvider;
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/layout/app_frame.dart';
import 'package:dsh_flutter/src/widgets/primitives/pill.dart';
import 'package:dsh_flutter/src/widgets/primitives/state_dot.dart';
import 'package:dsh_flutter/src/widgets/primitives/terminal_block.dart';
import 'package:dsh_flutter/src/widgets/primitives/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canonical fixture's session-event payloads, in stream order.
List<HistoryEntry> loadParityHistory() {
  final lines = File('test/goldens/replay/parity-stream.jsonl')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty);
  final entries = <HistoryEntry>[];
  for (final line in lines) {
    final wire = jsonDecode(line) as Map<String, dynamic>;
    if (wire['stream'] != 'mux') continue;
    final frame = MuxFrame.fromJson(
        (wire['frame'] as Map).cast<String, Object?>());
    if (frame is SessionEventFrame) {
      entries.add(HistoryEntry(event: SessionEvent.fromJson(frame.event)));
    }
  }
  return entries;
}

Widget _app(Widget child, {bool dark = false}) => ProviderScope(
      child: MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: child),
      ),
    );

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}

void main() {
  final history = loadParityHistory();
  test('fixture yields the parity event set', () {
    // 37 session/event frames of the canonical fixture (turns 1–2).
    expect(history.length, 35);
  });

  testWidgets('chat fixture light', (tester) async {
    _setViewport(tester, const Size(900, 1400));
    await tester.pumpWidget(_app(
      SizedBox(
        width: 760,
        child: ChatView(sessionId: 's-200'),
      ),
      dark: false,
    ));
    // Seed after first frame: ChatView watches liveHistoryProvider.
    containerOf(tester)
        .read(liveHistoryProvider('s-200').notifier)
        .replaceAll(history);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ChatView),
      matchesGoldenFile('goldens/chat_fixture_light.png'),
    );
  });

  testWidgets('chat fixture dark', (tester) async {
    _setViewport(tester, const Size(900, 1400));
    await tester.pumpWidget(_app(
      SizedBox(
        width: 760,
        child: ChatView(sessionId: 's-200'),
      ),
      dark: true,
    ));
    containerOf(tester)
        .read(liveHistoryProvider('s-200').notifier)
        .replaceAll(history);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ChatView),
      matchesGoldenFile('goldens/chat_fixture_dark.png'),
    );
  });

  testWidgets('app frame expanded light', (tester) async {
    _setViewport(tester, const Size(1680, 1000));
    await tester.pumpWidget(_app(
      const MediaQuery(
        data: MediaQueryData(size: Size(1680, 1000)),
        child: Scaffold(body: AppFrame()),
      ),
      dark: false,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppFrame),
      matchesGoldenFile('goldens/appframe_light_1680.png'),
    );
  });

  testWidgets('app frame collapsed dark', (tester) async {
    _setViewport(tester, const Size(400, 800));
    await tester.pumpWidget(_app(
      const MediaQuery(
        data: MediaQueryData(size: Size(400, 800)),
        child: Scaffold(body: AppFrame()),
      ),
      dark: true,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppFrame),
      matchesGoldenFile('goldens/appframe_dark_collapsed_400.png'),
    );
  });

  testWidgets('terminal ANSI block light', (tester) async {
    _setViewport(tester, const Size(760, 400));
    const ansiOutput =
        '\u001b[32m✓ 12 passing\u001b[0m\n\u001b[31m✗ 1 failing\u001b[0m\n'
        '\u001b[90m  at Context.<anonymous> (test/a.spec.js:12:9)\u001b[0m\n'
        'npm ERR! Test failed.  See above for more details.\n';
    await tester.pumpWidget(_app(
      const DsTerminalBlock(
        command: 'pnpm -s vitest run',
        cwd: '/repo/packages/llm',
        output: ansiOutput,
        exitCode: 1,
      ),
      dark: false,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DsTerminalBlock),
      matchesGoldenFile('goldens/terminal_ansi_light.png'),
    );
  });

  testWidgets('primitives row light', (tester) async {
    _setViewport(tester, const Size(700, 220));
    await tester.pumpWidget(_app(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Pill(label: 'Active plan', active: true),
              SizedBox(width: 8),
              Pill(label: 'Idle'),
              SizedBox(width: 16),
              StateDot(state: StateDotState.done),
              SizedBox(width: 6),
              StateDot(state: StateDotState.error),
            ]),
            const SizedBox(height: 12),
            const DsToast(
              data: DsToastData(id: 't-1', message: 'Workspace attached'),
            ),
          ],
        ),
      ),
      dark: false,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/primitives_row_light.png'),
    );
  });
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
