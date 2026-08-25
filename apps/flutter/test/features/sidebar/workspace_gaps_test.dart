import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/sidebar/search_derive.dart';
import 'package:dsh_flutter/src/features/sidebar/sidebar.dart';
import 'package:dsh_flutter/src/utils/abbreviate_home_path.dart';
import 'package:dsh_flutter/src/utils/workspace_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('abbreviateHomePath parity — runtime path.ts', () {
    test('POSIX home abbreviation', () {
      expect(abbreviateHomePath('/Users/u', '/Users/u'), '~');
      expect(abbreviateHomePath('/Users/u/', '/Users/u'), '~');
      expect(abbreviateHomePath('/Users/u/Documents/project', '/Users/u'), '~/Documents/project');
      expect(abbreviateHomePath('/Users/u2/a.ts', '/Users/u'), '/Users/u2/a.ts');
      expect(abbreviateHomePath('/etc/hosts', '/Users/u'), '/etc/hosts');
      expect(abbreviateHomePath('src/a.ts', '/Users/u'), 'src/a.ts');
      expect(abbreviateHomePath('~/already', '/Users/u'), '~/already');
      expect(abbreviateHomePath('/Users/u/a.ts', ''), '/Users/u/a.ts');
      expect(abbreviateHomePath('/Users/u/a.ts'), '/Users/u/a.ts');
    });

    test('Windows paths stay verbatim', () {
      expect(abbreviateHomePath(r'C:\Users\u\project', r'C:\Users\u'), r'C:\Users\u\project');
      expect(abbreviateHomePath('/Users/u/project', r'C:\Users\u'), '/Users/u/project');
    });

    test('root home does not become ~', () {
      expect(abbreviateHomePath('/etc/hosts', '/'), '/etc/hosts');
      expect(abbreviateHomePath('/etc/hosts', '///'), '/etc/hosts');
    });
  });

  group('workspace_labels parity — Rows.tsx / tree.ts', () {
    test('relativeTime buckets', () {
      final now = DateTime(2024, 8, 24, 12, 0).millisecondsSinceEpoch;
      expect(relativeTime(now - 30 * 1000, now).unit, 'now');
      final r = relativeTime(now - 5 * 60 * 1000, now);
      expect(r.unit, 'minutes');
      expect(r.n, 5);
      expect(relativeTime(now - 3 * 60 * 60 * 1000, now).unit, 'hours');
      expect(relativeTime(now - 2 * 24 * 60 * 60 * 1000, now).unit, 'days');
      expect(relativeTime(now - 40 * 24 * 60 * 60 * 1000, now).unit, 'months');
      expect(relativeTime(now - 400 * 24 * 60 * 60 * 1000, now).unit, 'years');
    });

    test('createdLabel formats via dictionary contract', () {
      final millis = DateTime(2024, 8, 24, 14, 30).millisecondsSinceEpoch;
      final label = createdLabel(millis);
      expect(label, contains('2024'));
      expect(label, contains('Created'));
      expect(label, contains('14:30'));
    });

    test('workspaceLabel basename', () {
      expect(workspaceLabel('/home/u/project'), 'project');
      expect(workspaceLabel('/home/u/project/'), 'project');
      expect(workspaceLabel(null), 'Ungrouped');
      expect(workspaceLabel(''), 'Ungrouped');
      expect(workspaceLabel('/'), '/');
    });
  });

  group('Session status precedence — Rows.tsx sessionStatuses', () {
    SessionSummary base({String? pending, bool running = false, bool completed = false, int subagents = 0}) {
      return SessionSummary(
        sessionId: SessionId('s1'),
        updatedAt: 1000,
        running: running,
        blank: false,
        pendingInteraction: pending,
        completed: completed,
        runningSubagentCount: subagents,
      );
    }

    test('approval outranks all', () {
      final s = base(pending: 'approval', running: true, subagents: 2, completed: true);
      final statuses = s.sessionStatuses();
      expect(statuses.first.label, 'Waiting approval');
      expect(statuses.first.state, 'warning');
      expect(statuses.length, 2); // plus subagents
      expect(statuses[1].label, contains('subagent'));
    });

    test('plan-review outranks question and running', () {
      final s = base(pending: 'plan-review', running: true);
      expect(s.sessionStatuses().first.label, 'Plan review');
    });

    test('question outranks running', () {
      final s = base(pending: 'question', running: true);
      expect(s.sessionStatuses().first.label, 'Waiting answer');
    });

    test('running outranks subagents and completed', () {
      final s = base(running: true, subagents: 1, completed: true);
      final statuses = s.sessionStatuses();
      expect(statuses.first.label, 'Running');
      expect(statuses.length, 2);
      expect(statuses[1].label, contains('subagent'));
    });

    test('subagents without running', () {
      final s = base(subagents: 3);
      expect(s.sessionStatuses().first.label, contains('subagent'));
    });

    test('completed outranks idle', () {
      final s = base(completed: true);
      expect(s.sessionStatuses().first.label, 'Completed');
      expect(s.sessionStatuses().first.state, 'done');
    });

    test('idle is done without completed flag', () {
      final s = base();
      final statuses = s.sessionStatuses();
      expect(statuses.length, 1);
      expect(statuses.first.label, 'Idle');
      expect(statuses.first.state, 'done');
    });
  });

  group('deriveWorkspaceGroups parity', () {
    List<SessionSummary> sessions(List<String> ids) => ids
        .map((id) => SessionSummary(
              sessionId: SessionId(id),
              updatedAt: int.parse(id.substring(1)) * 1000,
              running: false,
              blank: false,
              cwd: '/work/default',
            ))
        .toList();

    test('groups by workspace order with session membership', () {
      final workspaces = [
        const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s1'), SessionId('s2')]),
        const WorkspaceView(workspaceId: WorkspaceId('w2'), name: 'Two', cwd: '/work/two', sessionIds: [SessionId('s3')]),
      ];
      final sess = [
        SessionSummary(sessionId: SessionId('s1'), updatedAt: 3000, running: false, blank: false, cwd: '/work/one'),
        SessionSummary(sessionId: SessionId('s2'), updatedAt: 2000, running: false, blank: false, cwd: '/work/one'),
        SessionSummary(sessionId: SessionId('s3'), updatedAt: 1000, running: false, blank: false, cwd: '/work/two'),
        SessionSummary(sessionId: SessionId('s4'), updatedAt: 4000, running: false, blank: false, cwd: '/work/other'),
      ];
      final groups = deriveWorkspaceGroups(sess, workspaces, null, {}, '');
      expect(groups.length, 3); // w1, w2, Ungrouped
      expect(groups[0].key, 'w1');
      expect(groups[0].sessions.length, 2);
      expect(groups[1].key, 'w2');
      expect(groups[2].key, '');
      expect(groups[2].label, 'Ungrouped');
    });

    test('blank filtering respects current', () {
      final workspaces = [
        const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s1'), SessionId('s2')]),
      ];
      final sess = [
        SessionSummary(sessionId: SessionId('s1'), updatedAt: 1000, running: false, blank: true, cwd: '/work/one'),
        SessionSummary(sessionId: SessionId('s2'), updatedAt: 2000, running: false, blank: false, cwd: '/work/one'),
      ];
      // No current -> blank hidden
      final groupsNoCurrent = deriveWorkspaceGroups(sess, workspaces, null, {'w1'}, '');
      expect(groupsNoCurrent[0].sessions.length, 1);
      expect(groupsNoCurrent[0].sessions.first.sessionId.value, 's2');
      // Current is blank -> blank visible
      final groupsWithCurrent = deriveWorkspaceGroups(sess, workspaces, SessionId('s1'), {'w1'}, '');
      expect(groupsWithCurrent[0].sessions.length, 2);
    });
  });

  group('deriveSearchResults parity — tree.ts', () {
    List<SessionSummary> sess(List<String> titles) => titles
        .asMap()
        .entries
        .map((e) => SessionSummary(
              sessionId: SessionId('s${e.key}'),
              updatedAt: (100 - e.key) * 1000,
              running: false,
              blank: false,
              title: e.value,
              cwd: '/work/one',
            ))
        .toList();

    test('local title match leads newest-first', () {
      final sessions = sess(['done task', 'plain', 'DONE again']);
      final workspaces = [const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s0'), SessionId('s1'), SessionId('s2')])];
      final result = deriveSearchResults(sessions, workspaces, 'done', [], false, 10, <SessionId>{});
      expect(result.items.length, 2);
      // Both contain done, newest first: s0 (done task) before s2 (DONE again) because updatedAt larger
      expect(result.items.first.title, 'done task');
    });

    test('host snippet overlay and hasMore', () {
      final sessions = sess(['alpha', 'beta']);
      final workspaces = [const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s0'), SessionId('s1')])];
      final content = [SessionSearchItem(sessionId: SessionId('s1'), snippet: 'host snippet')];
      final result = deriveSearchResults(sessions, workspaces, 'beta', content, false, 10, <SessionId>{});
      expect(result.items.length, 1);
      expect(result.items.first.snippet, 'host snippet');
      expect(result.hasMore, false);

      final overflow = deriveSearchResults(sessions, workspaces, 'alpha', content, false, 1, <SessionId>{});
      expect(overflow.hasMore, true);
    });

    test('dedup local + content retains backend order for content-only', () {
      final sessions = sess(['match local', 'only content']);
      final workspaces = [const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s0'), SessionId('s1')])];
      // local matches s0 via title, content matches s1 via host
      final content = [SessionSearchItem(sessionId: SessionId('s1'), snippet: 'x')];
      final result = deriveSearchResults(sessions, workspaces, 'match', content, false, 10, <SessionId>{});
      // Local leads, content follows
      expect(result.items.map((r) => r.id.value).toList(), ['s0', 's1']);
    });

    test('archived filtered everywhere', () {
      final sessions = sess(['visible', 'hidden']);
      final workspaces = [const WorkspaceView(workspaceId: WorkspaceId('w1'), name: 'One', cwd: '/work/one', sessionIds: [SessionId('s0'), SessionId('s1')])];
      final archived = {SessionId('s1')};
      final result = deriveSearchResults(sessions, workspaces, 'hidden', [], false, 10, archived);
      expect(result.items, isEmpty);
    });
  });

  group('sanitizeSearchQuery parity — WorkspaceBrowser.tsx', () {
    test('NUL removal and 500 code unit cap with surrogate safety', () {
      String sanitize(String v) {
        final withoutNul = v.replaceAll('\u0000', '');
        if (withoutNul.length <= 500) return withoutNul;
        var end = 500;
        final last = withoutNul.codeUnitAt(end - 1);
        final next = withoutNul.codeUnitAt(end);
        if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) end--;
        return withoutNul.substring(0, end);
      }

      expect(sanitize('a\u0000b'), 'ab');
      final long = 'a' * 501;
      expect(sanitize(long).length, 500);
      // Surrogate pair test: 500 'a' + high surrogate at 499
      final withSurrogate = 'a' * 499 + '\uD83D' + '\uDE00' + 'b';
      final sanitized = sanitize(withSurrogate);
      expect(sanitized.length <= 500, true);
      // Ensure no lone surrogate
      expect(sanitized.contains(RegExp(r'[\uD800-\uDFFF]')), false);
    });
  });
}
