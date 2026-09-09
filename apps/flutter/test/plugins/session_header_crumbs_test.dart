/// Session-header breadcrumb tests — Flutter port of React
/// `ConversationSessionHeader` ancestry (`deriveAncestry` in
/// `ConversationSession.tsx`): subagent lineage renders `/`-separated crumb
/// buttons ending at the current title; unknown ids fall back to the raw id.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/session_header.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _summary({
  required String id,
  String? title,
  String? origin,
  String? parent,
}) => SessionSummary(
  sessionId: SessionId(id),
  updatedAt: 0,
  running: false,
  blank: false,
  title: title,
  origin: origin,
  parentSessionId: parent == null ? null : SessionId(parent),
);

void main() {
  group('deriveHeaderAncestry', () {
    test('single ordinary session yields itself', () {
      final byId = {const SessionId('s1'): _summary(id: 's1', title: 'One')};
      final chain = deriveHeaderAncestry(byId, const SessionId('s1'));
      expect(chain.map((c) => c.displayTitle), ['One']);
      expect(chain.single.subagent, isFalse);
    });

    test('subagent chain walks parents until a non-subagent root', () {
      final byId = {
        const SessionId('root'): _summary(id: 'root', title: 'Root'),
        const SessionId('a'): _summary(
          id: 'a',
          title: 'A',
          origin: 'subagent',
          parent: 'root',
        ),
        const SessionId('b'): _summary(
          id: 'b',
          title: 'B',
          origin: 'subagent',
          parent: 'a',
        ),
      };
      final chain = deriveHeaderAncestry(byId, const SessionId('b'));
      expect(chain.map((c) => c.displayTitle), ['Root', 'A', 'B']);
      expect(chain.map((c) => c.subagent), [false, true, true]);
    });

    test('unknown id and cycles terminate', () {
      expect(
        deriveHeaderAncestry(const {}, const SessionId('missing')),
        isEmpty,
      );
      final byId = {
        const SessionId('x'): _summary(
          id: 'x',
          title: 'X',
          origin: 'subagent',
          parent: 'y',
        ),
        const SessionId('y'): _summary(
          id: 'y',
          title: 'Y',
          origin: 'subagent',
          parent: 'x',
        ),
      };
      final chain = deriveHeaderAncestry(byId, const SessionId('x'));
      expect(chain.length, 2);
    });
  });

  group('SessionHeaderView crumbs', () {
    Future<void> pumpHeader(
      WidgetTester tester,
      List<SessionSummary> seeds,
      String active,
    ) async {
      final seeded = ProviderContainer();
      addTearDown(seeded.dispose);
      for (final s in seeds) {
        seeded.read(sessionsProvider.notifier).addSession(s);
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: seeded,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(body: SessionHeaderView(sessionId: active)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('subagent chain renders separators and current title', (
      tester,
    ) async {
      await pumpHeader(tester, [
        _summary(id: 'root', title: 'Root'),
        _summary(id: 'a', title: 'A', origin: 'subagent', parent: 'root'),
      ], 'a');
      expect(find.text('Root'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unknown session falls back to the raw id', (tester) async {
      await pumpHeader(tester, const [], 'ghost-id');
      expect(find.text('ghost-id'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
