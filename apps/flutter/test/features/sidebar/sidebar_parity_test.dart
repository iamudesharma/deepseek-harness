import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/sidebar/sidebar.dart';
import 'package:dsh_flutter/src/utils/workspace_labels.dart';
import 'package:dsh_flutter/src/plugins/workspace/locales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TEST D — updatedAt preserved', () {
    test('SessionSummary decodes authoritative milliseconds', () {
      final json = {
        'sessionId': 'session-c656cad5-4bf1-473d-b146-2291e65e7d16',
        'updatedAt': 1787934157394,
        'running': false,
        'blank': true,
        'cwd': '/Volumes/AppleExpanded/Code/untitled folder',
        'projections': {
          'asOfSeq': -1,
          'values': {}
        }
      };
      final s = SessionSummary.fromJson(json);
      expect(s.updatedAt, 1787934157394);
      expect(s.cwd, '/Volumes/AppleExpanded/Code/untitled folder');
      expect(s.blank, true);
      expect(s.sessionId.value, 'session-c656cad5-4bf1-473d-b146-2291e65e7d16');
    });

    test('SessionSummary handles num (double) updatedAt', () {
      final json = {
        'sessionId': 's1',
        'updatedAt': 1787928901804.0,
        'running': false,
        'blank': false,
      };
      final s = SessionSummary.fromJson(json);
      expect(s.updatedAt, 1787928901804);
    });

    test('SessionSummary second example', () {
      final json = {
        'sessionId': 'session-1e4b0e4c-8332-4670-a30c-538ca4941e5c',
        'updatedAt': 1787928901804,
        'running': false,
        'blank': true,
        'cwd': '/Volumes/AppleExpanded/Download/hhh',
      };
      final s = SessionSummary.fromJson(json);
      expect(s.updatedAt, 1787928901804);
      expect(s.cwd, '/Volumes/AppleExpanded/Download/hhh');
    });
  });

  group('TEST E/F — timestamp conversion', () {
    test('old timestamp does NOT return now', () {
      final now = DateTime(2026, 5, 26, 12, 0).millisecondsSinceEpoch;
      final old = now - 2 * 24 * 60 * 60 * 1000; // 2 days old
      final label = timeLabel(old, now);
      expect(label, isNot('now'));
      expect(label, '2d');
      // workspaceTimeLabel via dictionary
      String t(String k) => k == 'time.now' ? 'now' : k == 'time.days' ? '{n}d' : k;
      final wsLabel = workspaceTimeLabel(old, now, (k, {args}) {
        if (k == 'time.now') return 'now';
        if (k.startsWith('time.')) {
          // simplified
          return k == 'time.days' ? '2d' : k;
        }
        return k;
      });
      // Use real relativeTime check
      final r = relativeTime(old, now);
      expect(r.unit, 'days');
      expect(r.n, 2);
    });

    test('recent timestamp matches now bucket (<1min)', () {
      final now = DateTime(2026, 5, 26, 12, 0).millisecondsSinceEpoch;
      final recent = now - 10 * 1000; // 10 seconds ago
      final r = relativeTime(recent, now);
      expect(r.unit, 'now');
      expect(timeLabel(recent, now), 'now');
    });

    test('1 minute bucket', () {
      final now = 1000000000000;
      final at = now - 5 * 60 * 1000;
      expect(relativeTime(at, now).unit, 'minutes');
      expect(timeLabel(at, now), '5m');
    });

    test('hours bucket', () {
      final now = 1000000000000;
      final at = now - 3 * 60 * 60 * 1000;
      expect(relativeTime(at, now).unit, 'hours');
      expect(timeLabel(at, now), '3h');
    });

    test('fromMillisecondsSinceEpoch preserves semantics', () {
      const ms = 1787934157394;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      expect(dt.millisecondsSinceEpoch, ms);
      // Ensure not interpreting as seconds
      final wrong = DateTime.fromMillisecondsSinceEpoch(ms ~/ 1000);
      expect(wrong.millisecondsSinceEpoch, isNot(ms));
    });
  });

  group('TEST A — workspace grouping with real path', () {
    test('session with cwd matching workspace path appears under workspace', () {
      final workspace = WorkspaceView(
        workspaceId: WorkspaceId('w-hhh'),
        name: 'hhh',
        cwd: '/Volumes/AppleExpanded/Download/hhh',
        sessionIds: [SessionId('session-1e4b0e4c-8332-4670-a30c-538ca4941e5c')],
      );
      final session = SessionSummary(
        sessionId: SessionId('session-1e4b0e4c-8332-4670-a30c-538ca4941e5c'),
        updatedAt: 1787928901804,
        running: false,
        blank: false,
        cwd: '/Volumes/AppleExpanded/Download/hhh',
      );
      final groups = deriveWorkspaceGroups(
        [session],
        [workspace],
        null,
        {'w-hhh'},
        '',
      );
      expect(groups.length, 1);
      expect(groups.first.key, 'w-hhh');
      expect(groups.first.label, 'hhh');
      expect(groups.first.sessions.length, 1);
      expect(groups.first.sessions.first.sessionId.value,
          'session-1e4b0e4c-8332-4670-a30c-538ca4941e5c');
      // Not under Ungrouped
      expect(groups.where((g) => g.key == '').isEmpty, true);
    });

    test('physical real data: hhh workspace', () {
      final workspaces = [
        WorkspaceView(
          workspaceId: WorkspaceId('ws-hhh'),
          name: 'hhh',
          cwd: '/Volumes/AppleExpanded/Download/hhh',
          sessionIds: [SessionId('session-1e4b0e4c-8332-4670-a30c-538ca4941e5c')],
        ),
        WorkspaceView(
          workspaceId: WorkspaceId('ws-untitled'),
          name: 'untitled folder',
          cwd: '/Volumes/AppleExpanded/Code/untitled folder',
          sessionIds: [SessionId('session-c656cad5-4bf1-473d-b146-2291e65e7d16')],
        ),
      ];
      final sessions = [
        SessionSummary(
          sessionId: SessionId('session-1e4b0e4c-8332-4670-a30c-538ca4941e5c'),
          updatedAt: 1787928901804,
          running: false,
          blank: true,
          cwd: '/Volumes/AppleExpanded/Download/hhh',
        ),
        SessionSummary(
          sessionId: SessionId('session-c656cad5-4bf1-473d-b146-2291e65e7d16'),
          updatedAt: 1787934157394,
          running: false,
          blank: true,
          cwd: '/Volumes/AppleExpanded/Code/untitled folder',
        ),
      ];
      // Make one current to allow blank visibility
      final groups = deriveWorkspaceGroups(
        sessions,
        workspaces,
        SessionId('session-1e4b0e4c-8332-4670-a30c-538ca4941e5c'),
        {'ws-hhh', 'ws-untitled'},
        '',
      );
      // hhh group should contain its session
      final hhhGroup = groups.firstWhere((g) => g.key == 'ws-hhh');
      expect(hhhGroup.sessions.any((s) => s.sessionId.value == 'session-1e4b0e4c-8332-4670-a30c-538ca4941e5c'), true);
      // untitled group should have its session only if current matches? second session blank not current -> hidden
      final untitled = groups.firstWhere((g) => g.key == 'ws-untitled');
      // second session blank true but not current -> should be hidden (0)
      expect(untitled.sessions.length, 0);
      // Make second current
      final groups2 = deriveWorkspaceGroups(
        sessions,
        workspaces,
        SessionId('session-c656cad5-4bf1-473d-b146-2291e65e7d16'),
        {'ws-hhh', 'ws-untitled'},
        '',
      );
      final untitled2 = groups2.firstWhere((g) => g.key == 'ws-untitled');
      expect(untitled2.sessions.length, 1);
    });
  });

  group('TEST B — different workspace', () {
    test('session appears under untitled folder workspace', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w2'),
        name: 'untitled folder',
        cwd: '/Volumes/AppleExpanded/Code/untitled folder',
        sessionIds: [SessionId('s-c656')],
      );
      final sess = SessionSummary(
        sessionId: SessionId('s-c656'),
        updatedAt: 1000,
        running: false,
        blank: false,
        cwd: '/Volumes/AppleExpanded/Code/untitled folder',
      );
      final groups = deriveWorkspaceGroups([sess], [ws], null, {'w2'}, '');
      expect(groups.first.sessions.length, 1);
      expect(groups.first.key, 'w2');
    });
  });

  group('TEST C — genuinely ungrouped', () {
    test('session not in any workspace appears under Ungrouped', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'hhh',
        cwd: '/Volumes/AppleExpanded/Download/hhh',
        sessionIds: [SessionId('s-other')],
      );
      final sess = SessionSummary(
        sessionId: SessionId('s-unmatched'),
        updatedAt: 1000,
        running: false,
        blank: false,
        cwd: '/Volumes/AppleExpanded/Other/path',
      );
      final groups = deriveWorkspaceGroups([sess], [ws], null, {'w1', ''}, '');
      expect(groups.length, 2);
      expect(groups[1].key, '');
      expect(groups[1].label, 'Ungrouped');
      expect(groups[1].sessions.length, 1);
      expect(groups[1].sessions.first.sessionId.value, 's-unmatched');
      // workspace group empty
      expect(groups[0].sessions.length, 0);
    });

    test('cwd matching but not in sessionIds stays Ungrouped (authoritative)', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'hhh',
        cwd: '/Volumes/AppleExpanded/Download/hhh',
        sessionIds: [], // no membership
      );
      final sess = SessionSummary(
        sessionId: SessionId('s1'),
        updatedAt: 1000,
        running: false,
        blank: false,
        cwd: '/Volumes/AppleExpanded/Download/hhh',
      );
      final groups = deriveWorkspaceGroups([sess], [ws], null, {'w1', ''}, '');
      // No sessionIds membership -> should be Ungrouped (React authoritative)
      expect(groups[1].key, '');
      expect(groups[1].sessions.length, 1);
      expect(groups[0].sessions.length, 0);
    });
  });

  group('TEST G — ordering', () {
    test('workspace groups preserve account order (sessionIds), not recency', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'One',
        cwd: '/work/one',
        sessionIds: [SessionId('s2'), SessionId('s1')],
      );
      final s1 = SessionSummary(
        sessionId: SessionId('s1'),
        updatedAt: 3000,
        running: false,
        blank: false,
      );
      final s2 = SessionSummary(
        sessionId: SessionId('s2'),
        updatedAt: 1000,
        running: false,
        blank: false,
      );
      final groups = deriveWorkspaceGroups([s1, s2], [ws], null, {'w1'}, '');
      // Account order is s2, s1 regardless of updatedAt
      expect(groups.first.sessions.map((s) => s.sessionId.value).toList(), ['s2', 's1']);
    });

    test('Ungrouped sorted by recency descending', () {
      final s1 = SessionSummary(
        sessionId: SessionId('s1'),
        updatedAt: 1000,
        running: false,
        blank: false,
      );
      final s2 = SessionSummary(
        sessionId: SessionId('s2'),
        updatedAt: 3000,
        running: false,
        blank: false,
      );
      final groups = deriveWorkspaceGroups([s1, s2], [], null, {''}, '');
      expect(groups.length, 1);
      expect(groups.first.key, '');
      expect(groups.first.sessions.first.sessionId.value, 's2');
      expect(groups.first.sessions[1].sessionId.value, 's1');
    });

    test('host list order updatedAt descending', () {
      final sessions = [
        SessionSummary(sessionId: SessionId('a'), updatedAt: 100, running: false, blank: false),
        SessionSummary(sessionId: SessionId('b'), updatedAt: 300, running: false, blank: false),
        SessionSummary(sessionId: SessionId('c'), updatedAt: 200, running: false, blank: false),
      ];
      // Simulate sortedSessionsProvider: sorted descending
      final sorted = sessions.toList()..sort((a,b)=> b.updatedAt.compareTo(a.updatedAt));
      expect(sorted.map((s)=>s.sessionId.value).toList(), ['b','c','a']);
    });
  });

  group('TEST H — live update', () {
    test('changing updatedAt changes ordering', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'ws',
        cwd: '/a',
        sessionIds: [],
      );
      // Initially s1 newer
      var s1 = SessionSummary(sessionId: SessionId('s1'), updatedAt: 2000, running: false, blank: false);
      var s2 = SessionSummary(sessionId: SessionId('s2'), updatedAt: 1000, running: false, blank: false);
      var groups = deriveWorkspaceGroups([s1, s2], [], null, {''}, '');
      expect(groups.first.sessions.first.sessionId.value, 's1');
      // Update s2 to be newer
      s2 = s2.copyWith(updatedAt: 3000);
      groups = deriveWorkspaceGroups([s1, s2], [], null, {''}, '');
      expect(groups.first.sessions.first.sessionId.value, 's2');
      // Timestamp formatter should reflect new time with distinct buckets
      var s1old = SessionSummary(sessionId: SessionId('s1'), updatedAt: 0, running: false, blank: false);
      var s2new = SessionSummary(sessionId: SessionId('s2'), updatedAt: 100000, running: false, blank: false);
      const now = 200000;
      expect(timeLabel(s1old.updatedAt, now), isNot(timeLabel(s2new.updatedAt, now)));
      final labelBefore = timeLabel(1000, now);
      final labelAfter = timeLabel(190000, now);
      expect(labelBefore, isNot(labelAfter));
    });
  });

  group('TEST I — authoritative host data', () {
    test('does not inject synthetic workspace membership', () {
      final hostWorkspaces = [
        WorkspaceView(
          workspaceId: WorkspaceId('real-hhh'),
          name: 'hhh',
          cwd: '/Volumes/AppleExpanded/Download/hhh',
          sessionIds: [SessionId('s1')],
        ),
      ];
      final sess = SessionSummary(
        sessionId: SessionId('s1'),
        updatedAt: 1000,
        running: false,
        blank: false,
        cwd: '/Volumes/AppleExpanded/Download/hhh',
      );
      final groups = deriveWorkspaceGroups([sess], hostWorkspaces, null, {'real-hhh'}, '');
      expect(groups.length, 1);
      expect(groups.first.label, 'hhh');
      expect(groups.first.sessions.length, 1);
      // Ensure no Default/Project A synthetic
      expect(groups.any((g) => g.label == 'Default'), false);
      expect(groups.any((g) => g.label == 'Project A'), false);
    });
  });

  group('blank handling', () {
    test('blank not current hidden', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'ws',
        cwd: '/ws',
        sessionIds: [SessionId('s1'), SessionId('s2')],
      );
      final blank = SessionSummary(sessionId: SessionId('s1'), updatedAt: 1000, running: false, blank: true);
      final visible = SessionSummary(sessionId: SessionId('s2'), updatedAt: 2000, running: false, blank: false);
      final groups = deriveWorkspaceGroups([blank, visible], [ws], null, {'w1'}, '');
      expect(groups.first.sessions.length, 1);
      expect(groups.first.sessions.first.sessionId.value, 's2');
    });

    test('blank current visible', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'ws',
        cwd: '/ws',
        sessionIds: [SessionId('s1')],
      );
      final blank = SessionSummary(sessionId: SessionId('s1'), updatedAt: 1000, running: false, blank: true);
      final groups = deriveWorkspaceGroups([blank], [ws], SessionId('s1'), {'w1'}, '');
      expect(groups.first.sessions.length, 1);
    });
  });

  group('archived filtering', () {
    test('archived hidden everywhere', () {
      final ws = WorkspaceView(
        workspaceId: WorkspaceId('w1'),
        name: 'ws',
        cwd: '/ws',
        sessionIds: [SessionId('s1'), SessionId('s2')],
      );
      final s1 = SessionSummary(sessionId: SessionId('s1'), updatedAt: 1000, running: false, blank: false);
      final s2 = SessionSummary(sessionId: SessionId('s2'), updatedAt: 2000, running: false, blank: false);
      final groups = deriveWorkspaceGroups([s1, s2], [ws], null, {'w1'}, '', archivedIds: {SessionId('s1')});
      expect(groups.first.sessions.length, 1);
      expect(groups.first.sessions.first.sessionId.value, 's2');
      // Also test ungrouped archived
      final groups2 = deriveWorkspaceGroups([s1], [], null, {''}, '', archivedIds: {SessionId('s1')});
      expect(groups2.isEmpty || groups2.first.sessions.isEmpty, true);
    });
  });
}
