/// Subcall + compaction goldens — representative P2/P3 states after the
/// remediation: depth 1,2,3 chains, error styling, and compaction marker
/// (collapsed vs expanded, manual, markdown, i18n zh, out-of-order).
/// Rendered through production ChatView + liveHistory.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data,
        {Object? surfaceOp, List<int>? sourceSeqs}) =>
    SessionEvent(
      type: type,
      seq: seq,
      time: seq * 1000,
      data: data,
    );

HistoryEntry _h(SessionEvent e, {Map<String, dynamic>? view}) =>
    HistoryEntry(event: e, view: view);

List<HistoryEntry> _depth1() => [
      _h(_ev('turn/start', 1, {'turn': 1})),
      _h(SessionEvent(
          type: 'user/message',
          seq: 2,
          time: 2000,
          data: {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'run code?'}
            ],
            'source': {'kind': 'user'}
          })),
      _h(_ev('tool/call', 3, {'callId': 'root-1', 'name': 'run-code', 'arguments': {}})),
      _h(_ev('tool/code-dispatch-start', 4,
          {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:1', 'name': 'bash', 'arguments': {'command': 'ls'}})),
      _h(_ev('tool/code-dispatch', 5, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1',
        'subCallId': 'root-1:code:1',
        'name': 'bash',
        'isError': false,
        'content': [
          {'type': 'text', 'text': 'ok-out'}
        ]
      })),
      _h(_ev('tool/code-dispatch-start', 6,
          {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:2', 'name': 'node', 'arguments': {'script': 'b'}})),
      _h(_ev('tool/code-dispatch', 7, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1',
        'subCallId': 'root-1:code:2',
        'name': 'node',
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'boom'}
        ]
      })),
      _h(SessionEvent(
          type: 'tool/result',
          seq: 8,
          time: 8000,
          data: {
            'message': {
              'role': 'user',
              'source': {'kind': 'tool', 'callId': 'root-1'},
              'content': [
                {
                  'type': 'tool-result',
                  'toolCallId': 'root-1',
                  'content': [
                    {'type': 'text', 'text': 'final'}
                  ]
                }
              ]
            },
            'isError': false
          })),
    ];

List<HistoryEntry> _depth2() => [
      _h(_ev('turn/start', 1, {'turn': 1})),
      _h(_ev('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'})),
      _h(_ev('tool/code-dispatch-start', 3,
          {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:1', 'name': 'bash', 'arguments': {'command': 'ls'}})),
      _h(_ev('tool/code-dispatch-start', 4, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'arguments': {}
      })),
      _h(_ev('tool/code-dispatch', 5, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'isError': false,
        'content': [
          {'type': 'text', 'text': 'deep-out'}
        ]
      })),
      _h(SessionEvent(type: 'tool/result', seq: 6, time: 6000, data: {
        'message': {
          'role': 'user',
          'source': {'kind': 'tool', 'callId': 'root-1'},
          'content': [
            {'type': 'tool-result', 'toolCallId': 'root-1', 'content': []}
          ]
        }
      })),
    ];

List<HistoryEntry> _depth3() => [
      _h(_ev('turn/start', 1, {'turn': 1})),
      _h(_ev('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'})),
      _h(_ev('tool/code-dispatch-start', 3,
          {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:1', 'name': 'bash', 'arguments': {}})),
      _h(_ev('tool/code-dispatch-start', 4, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'arguments': {}
      })),
      _h(_ev('tool/code-dispatch', 5, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'isError': false,
        'content': [
          {'type': 'text', 'text': 'deep-out'}
        ]
      })),
      _h(_ev('tool/code-dispatch-start', 6, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1:code:1',
        'subCallId': 'root-1:code:1:code:1:code:1',
        'name': 'deep',
        'arguments': {}
      })),
      _h(_ev('tool/code-dispatch', 7, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1:code:1',
        'subCallId': 'root-1:code:1:code:1:code:1',
        'name': 'deep',
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'deep-err'}
        ]
      })),
      _h(SessionEvent(type: 'tool/result', seq: 8, time: 8000, data: {
        'message': {
          'role': 'user',
          'source': {'kind': 'tool', 'callId': 'root-1'},
          'content': [
            {'type': 'tool-result', 'toolCallId': 'root-1', 'content': []}
          ]
        }
      })),
    ];

List<HistoryEntry> _compaction() => [
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 1, time: 1000, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'keep this history'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 2, time: 2000, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'shadow this'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'compaction/summary', seq: 3, time: 3000, data: {
        'compactionId': 'c-1',
        'summary': [
          {'type': 'text', 'text': 'condensed history of 1 item'}
        ],
        'shadowedSeqs': [2],
        'shadowedTokenCount': 512,
        'provider': 'stub',
        'model': 'm'
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 4, time: 4000, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'condensed history of 1 item'}
        ],
        'source': {'kind': 'plugin', 'plugin': 'compact', 'compactionId': 'c-1'},
        // Surface metadata carried in data for HistoryEntry → envelope fallback (SessionEvent doesn't store it).
        'surfaceOp': {'op': 'replace', 'start': 1, 'end': 1},
        'sourceEventSeqs': [2],
      })),
      HistoryEntry(event: SessionEvent(type: 'compaction/end', seq: 5, time: 5000, data: {'compactionId': 'c-1', 'turn': null})),
    ];

List<HistoryEntry> _manualCompaction() => [
      HistoryEntry(event: SessionEvent(type: 'command/run', seq: 1, time: 1000, data: {'commandId': 'cmd-1', 'name': 'compact', 'args': ''})),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 2, time: 1500, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'keep'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 3, time: 1600, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'shadow me'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'compaction/summary', seq: 4, time: 2000, data: {
        'compactionId': 'manual-1',
        'sourceCommandId': 'cmd-1',
        'summary': [
          {'type': 'text', 'text': 'manual summary with **bold** and `code`'}
        ],
        'shadowedSeqs': [3],
        'shadowedTokenCount': 256,
        'provider': 'stub',
        'model': 'm'
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 5, time: 2500, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'checkpoint'}
        ],
        'source': {'kind': 'plugin', 'plugin': 'compact', 'compactionId': 'manual-1', 'sourceCommandId': 'cmd-1'},
        'surfaceOp': {'op': 'replace', 'start': 3, 'end': 3},
        'sourceEventSeqs': [3],
      })),
      HistoryEntry(event: SessionEvent(type: 'command/done', seq: 6, time: 3000, data: {'commandId': 'cmd-1', 'kind': 'success', 'text': 'compacted', 'sourceEventSeq': 4})),
      HistoryEntry(event: SessionEvent(type: 'compaction/end', seq: 7, time: 3100, data: {'compactionId': 'manual-1', 'sourceCommandId': 'cmd-1', 'turn': null})),
    ];

List<HistoryEntry> _markdownCompaction() => [
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 1, time: 1000, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'keep'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 2, time: 1100, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'shadow'}
        ],
        'source': {'kind': 'user'}
      })),
      HistoryEntry(
          event: SessionEvent(type: 'compaction/summary', seq: 3, time: 2000, data: {
        'compactionId': 'md-1',
        'summary': [
          {'type': 'text', 'text': '# Summary\n\n- item one\n- item two\n\n```dart\nvoid main() {}\n```\n\n**bold** and *italic*'}
        ],
        'shadowedSeqs': [2],
        'shadowedTokenCount': 100,
        'provider': 'stub',
        'model': 'm'
      })),
      HistoryEntry(
          event: SessionEvent(type: 'user/message', seq: 4, time: 2500, data: {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'md summary'}
        ],
        'source': {'kind': 'plugin', 'plugin': 'compact', 'compactionId': 'md-1'},
        'surfaceOp': {'op': 'replace', 'start': 2, 'end': 2},
        'sourceEventSeqs': [2],
      })),
      HistoryEntry(event: SessionEvent(type: 'compaction/end', seq: 5, time: 3000, data: {'compactionId': 'md-1', 'turn': null})),
    ];

List<HistoryEntry> _outOfOrderDepth2() => [
      _h(_ev('turn/start', 1, {'turn': 1})),
      _h(_ev('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'})),
      // inner first, then outer — out-of-order delivery
      _h(_ev('tool/code-dispatch-start', 3, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'arguments': {}
      })),
      _h(_ev('tool/code-dispatch-start', 4,
          {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:1', 'name': 'bash', 'arguments': {'command': 'ls'}})),
      _h(_ev('tool/code-dispatch', 5, {
        'rootCallId': 'root-1',
        'parentCallId': 'root-1:code:1',
        'subCallId': 'root-1:code:1:code:1',
        'name': 'inner',
        'isError': false,
        'content': [
          {'type': 'text', 'text': 'deep-out'}
        ]
      })),
      _h(SessionEvent(type: 'tool/result', seq: 6, time: 6000, data: {
        'message': {
          'role': 'user',
          'source': {'kind': 'tool', 'callId': 'root-1'},
          'content': [
            {'type': 'tool-result', 'toolCallId': 'root-1', 'content': []}
          ]
        }
      })),
    ];

Widget _app(Widget child, {Locale locale = const Locale('en')}) => ProviderScope(
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildLightTheme(),
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

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChatView)));

void main() {
  testWidgets('subcall depth1 light', (tester) async {
    _setViewport(tester, const Size(900, 700));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'sub-1'))));
    _containerOf(tester).read(liveHistoryProvider('sub-1').notifier).replaceAll(_depth1());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/subcall_depth1_light.png'));
  });

  testWidgets('subcall depth2 light', (tester) async {
    _setViewport(tester, const Size(900, 700));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'sub-2'))));
    _containerOf(tester).read(liveHistoryProvider('sub-2').notifier).replaceAll(_depth2());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/subcall_depth2_light.png'));
  });

  testWidgets('subcall depth3 error light', (tester) async {
    _setViewport(tester, const Size(900, 780));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'sub-3'))));
    _containerOf(tester).read(liveHistoryProvider('sub-3').notifier).replaceAll(_depth3());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/subcall_depth3_light.png'));
  });

  testWidgets('subcall depth2 out-of-order light', (tester) async {
    _setViewport(tester, const Size(900, 700));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'sub-oo'))));
    _containerOf(tester).read(liveHistoryProvider('sub-oo').notifier).replaceAll(_outOfOrderDepth2());
    await tester.pumpAndSettle();
    // Out-of-order dispatch must render identically to the in-order depth2 case
    // (parent-key divergence fixed: childrenByParent at parent key, not root).
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/subcall_depth2_out_of_order_light.png'));
  });

  testWidgets('compaction collapsed light', (tester) async {
    _setViewport(tester, const Size(900, 500));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-1'))));
    _containerOf(tester).read(liveHistoryProvider('cmp-1').notifier).replaceAll(_compaction());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/compaction_light.png'));
  });

  testWidgets('compaction expanded light', (tester) async {
    _setViewport(tester, const Size(900, 600));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-2'))));
    _containerOf(tester).read(liveHistoryProvider('cmp-2').notifier).replaceAll(_compaction());
    await tester.pumpAndSettle();
    // Tap the compaction button to expand.
    final btn = find.byType(InkWell).first;
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/compaction_expanded_light.png'));
  });

  testWidgets('manual compaction collapsed light', (tester) async {
    _setViewport(tester, const Size(900, 600));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-manual-1'))));
    _containerOf(tester).read(liveHistoryProvider('cmp-manual-1').notifier).replaceAll(_manualCompaction());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/manual_compaction_light.png'));
  });

  testWidgets('manual compaction expanded light', (tester) async {
    _setViewport(tester, const Size(900, 700));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-manual-2'))));
    _containerOf(tester).read(liveHistoryProvider('cmp-manual-2').notifier).replaceAll(_manualCompaction());
    await tester.pumpAndSettle();
    final btn = find.byType(InkWell).first;
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/manual_compaction_expanded_light.png'));
  });

  testWidgets('markdown compaction expanded light', (tester) async {
    _setViewport(tester, const Size(900, 750));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-md'))));
    _containerOf(tester).read(liveHistoryProvider('cmp-md').notifier).replaceAll(_markdownCompaction());
    await tester.pumpAndSettle();
    final btn = find.byType(InkWell).first;
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/compaction_markdown_light.png'));
  });

  testWidgets('compaction zh collapsed light', (tester) async {
    _setViewport(tester, const Size(900, 500));
    await tester.pumpWidget(_app(SizedBox(width: 760, child: ChatView(sessionId: 'cmp-zh')), locale: const Locale('zh')));
    _containerOf(tester).read(liveHistoryProvider('cmp-zh').notifier).replaceAll(_compaction());
    await tester.pumpAndSettle();
    await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/compaction_zh_light.png'));
  });
}
