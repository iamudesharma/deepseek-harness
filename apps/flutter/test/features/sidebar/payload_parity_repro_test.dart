import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/sidebar/sidebar.dart';
import 'package:dsh_flutter/src/utils/workspace_labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 0 repro: payload from http://127.0.0.1:3080/api/session/list
/// (truncated to first 22 items for deterministic repro).
/// Demonstrates Flutter vs React divergence: dummy workspaces → all 53
/// Ungrouped + every row `now`; real workspaces → `hhh`/`untitled folder`
/// partitions with `1d`/`3d`.

List<Map<String, dynamic>> _payloadItems() => [
      {
        'sessionId': 'session-b9c982f5-5176-4979-8472-7faeb9c5c5ab',
        'updatedAt': 1788226858979,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 1309,
          'values': {'title': 'Hello AI coding session'}
        }
      },
      {
        'sessionId': 'session-387a0bb2-2e41-4eb0-81f0-4f25cb262170',
        'updatedAt': 1788111986893,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 51,
          'values': {'title': 'Greeting and starting session'}
        }
      },
      {
        'sessionId': 'session-8adbbcf8-67c0-4626-ab78-d82ba08b8c67',
        'updatedAt': 1788111888532,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 39,
          'values': {'title': 'hi'}
        }
      },
      {
        'sessionId': 'session-0d2c81f2-ad3e-4921-b665-c9c43764041b',
        'updatedAt': 1788111082936,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 68,
          'values': {'title': 'hi'}
        }
      },
      {
        'sessionId': 'session-839fd509-cd0a-4da3-9cdb-1ce5d612e4e2',
        'updatedAt': 1788110972766,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Download/hhh',
        'projections': {
          'asOfSeq': 339,
          'values': {'title': 'hi'}
        }
      },
      {
        'sessionId': 'session-1c256b7d-06db-481e-a59b-6f12538a5eaa',
        'updatedAt': 1788110928195,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Download/hhh',
        'projections': {
          'asOfSeq': 256,
          'values': {'title': 'Greeting and starting session'}
        }
      },
      {
        'sessionId': 'session-e53dcf14-4983-433a-a1aa-d7c9507541a0',
        'updatedAt': 1788095263677,
        'running': false,
        'blank': true,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 2,
          'values': {'title': null}
        }
      },
      {
        'sessionId': 'session-8123574a-5c70-49c1-82e0-3a8a69795e6d',
        'updatedAt': 1788063967665,
        'running': false,
        'blank': false,
        'cwd': '/tmp',
        'projections': {
          'asOfSeq': 16,
          'values': {'title': 'hello'}
        }
      },
      {
        'sessionId': 'session-8783ab23-d0a2-41b1-a480-3151dc1e16df',
        'updatedAt': 1788063576706,
        'running': false,
        'blank': false,
        'cwd': '/tmp',
        'projections': {
          'asOfSeq': 16,
          'values': {'title': 'hello live test'}
        }
      },
      {
        'sessionId': 'session-a3c50dd7-220b-4d6b-8452-cc0878cfd5a1',
        'updatedAt': 1788019388013,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/deepseek harness/deepseek-harness',
        'projections': {
          'asOfSeq': 19,
          'values': {'title': 'hi'}
        }
      },
      {
        'sessionId': 'session-c656cad5-4bf1-473d-b146-2291e65e7d16',
        'updatedAt': 1787934157394,
        'running': false,
        'blank': true,
        'cwd': '/Volumes/AppleExpanded/Code/untitled folder',
        'projections': {
          'asOfSeq': 3,
          'values': {'title': null}
        }
      },
      {
        'sessionId': 'session-cefc0aef-6842-4035-93d1-0a8f911b0bc9',
        'updatedAt': 1787931491404,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/AppleExpanded/Code/untitled folder',
        'projections': {
          'asOfSeq': 5470,
          'values': {'title': 'Why I am adding the'}
        }
      },
    ];

List<SessionSummary> _sessions() =>
    _payloadItems().map((j) => SessionSummary.fromJson(j)).toList();

void main() {
  group('Phase 0 payload repro — workspace grouping divergence', () {
    test('with synthetic fallback (Default/Project A) all visible go to Ungrouped — bug', () {
      final sessions = _sessions();
      const fallback = [
        WorkspaceView(workspaceId: WorkspaceId('default'), name: 'Default', cwd: '/work/default'),
        WorkspaceView(workspaceId: WorkspaceId('project-a'), name: 'Project A', cwd: '/work/project-a'),
      ];
      // Filter as sidebar does: blank hidden unless current
      final groups = deriveWorkspaceGroups(sessions, fallback, null, {'default', 'project-a', ''}, '');
      // No session is member of fallback workspaces → only Ungrouped holds visible.
      // Expected visible: blank:false only = 10 of 12 (2 blanks hidden)
      final ungrouped = groups.firstWhere((g) => g.key == '');
      expect(ungrouped.sessions.length, 10,
          reason: 'With fallback, hhh/untitled sessions are forced into Ungrouped (flutter bug)');
      // The two hhh cwd sessions are currently mis-classified as Ungrouped:
      final hhhIds = {'session-839fd509-cd0a-4da3-9cdb-1ce5d612e4e2', 'session-1c256b7d-06db-481e-a59b-6f12538a5eaa'};
      for (final id in hhhIds) {
        expect(ungrouped.sessions.any((s) => s.sessionId.value == id), true,
            reason: 'hhh session $id stranded in Ungrouped due to dummy workspaces');
      }
      // Print diagnostic matching screenshot 53 count analogy
      // ignore: avoid_print
      print('[repro] fallback groups=${groups.map((g) => "${g.label}(${g.sessionCount})").join(", ")} ungroupedTitles=${ungrouped.sessions.map((s) => s.title).join("|")}');
    });

    test('with real host workspaces (hhh + untitled folder) grouping is correct — React parity', () {
      final sessions = _sessions();
      final workspaces = [
        WorkspaceView(
          workspaceId: WorkspaceId('ws-hhh'),
          name: 'hhh',
          cwd: '/Volumes/AppleExpanded/Download/hhh',
          sessionIds: [SessionId('session-839fd509-cd0a-4da3-9cdb-1ce5d612e4e2'), SessionId('session-1c256b7d-06db-481e-a59b-6f12538a5eaa')],
        ),
        WorkspaceView(
          workspaceId: WorkspaceId('ws-untitled'),
          name: 'untitled folder',
          cwd: '/Volumes/AppleExpanded/Code/untitled folder',
          sessionIds: [SessionId('session-cefc0aef-6842-4035-93d1-0a8f911b0bc9')],
        ),
      ];
      final groups = deriveWorkspaceGroups(sessions, workspaces, null, {'ws-hhh', 'ws-untitled', ''}, '');
      expect(groups.length, 3); // hhh, untitled folder, Ungrouped
      final hhh = groups.firstWhere((g) => g.key == 'ws-hhh');
      expect(hhh.sessions.length, 2);
      final untitled = groups.firstWhere((g) => g.key == 'ws-untitled');
      expect(untitled.sessions.length, 1);
      final ungrouped = groups.firstWhere((g) => g.key == '');
      // Deepseek-harness + /tmp sessions correctly in Ungrouped (not in any workspace)
      expect(ungrouped.sessions.length, 7); // 10 visible - 3 accounted = 7
      // ignore: avoid_print
      print('[repro] real groups=${groups.map((g) => "${g.label}(${g.sessionCount})").join(", ")}');
    });

    test('cwd-synthesis fallback (Phase 1) would also partition correctly when host has zero workspaces', () {
      final sessions = _sessions().where((s) => !s.blank).toList();
      // Simulate synthesis: group by cwd basename → one WorkspaceView per distinct cwd
      final byCwd = <String, List<SessionId>>{};
      for (final s in sessions) {
        final cwd = s.cwd ?? '';
        byCwd.putIfAbsent(cwd, () => []).add(s.sessionId);
      }
      final synthesized = byCwd.entries.map((e) {
        final base = e.key.split('/').where((p) => p.isNotEmpty).toList().lastOrNull ?? e.key;
        return WorkspaceView(
          workspaceId: WorkspaceId('synth-${base.hashCode}'),
          name: base,
          cwd: e.key,
          sessionIds: e.value,
        );
      }).toList();
      final groups = deriveWorkspaceGroups(sessions, synthesized, null, synthesized.map((w) => w.workspaceId.value).toSet()..add(''), '');
      // Should produce ~4 groups: deepseek-harness, hhh, /tmp, untitled folder
      expect(groups.length, 4);
      expect(groups.any((g) => g.label == 'hhh'), true);
      expect(groups.any((g) => g.label == 'untitled folder'), true);
      // ignore: avoid_print
      print('[repro] synthesized groups=${groups.map((g) => "${g.label}(${g.sessionCount})").join(", ")}');
    });
  });

  group('Phase 0 payload repro — timestamp divergence', () {
    test('timeLabel with deviceNow correctly yields 1d/3d, not now for stale rows', () {
      // Simulate deviceNow ~ payload newest + 24min (as in log: 1788228295130)
      const deviceNow = 1788228295130;
      const nowRow = 1788226858979; // most recent → ~23m
      const dayOld = 1788111986893; // ~1.3d
      const threeDays = 1788019388013; // ~2.x d (payload: 1788019388013)
      expect(timeLabel(nowRow, deviceNow), '23m');
      expect(timeLabel(dayOld, deviceNow), '1d');
      // threeDays diff ~2.4d → 2d bucket
      expect(relativeTime(threeDays, deviceNow).unit, 'days');
      // ignore: avoid_print
      print('[repro] time nowRow=${timeLabel(nowRow, deviceNow)} dayOld=${timeLabel(dayOld, deviceNow)} threeDays=${timeLabel(threeDays, deviceNow)}');
    });

    test('hostSyncedNow with max == newest still yields same buckets (host not ahead)', () {
      const deviceNow = 1788228295130;
      const maxUpdatedAt = 1788226858979; // newest from payload
      // hostSynced logic: max < device → deviceNow
      final hostSynced = maxUpdatedAt > deviceNow ? maxUpdatedAt : deviceNow;
      expect(hostSynced, deviceNow);
      // So buckets above still 23m/1d
      expect(timeLabel(1788111986893, hostSynced), '1d');
    });

    test('host ahead (future) clamp would produce now for all — bug scenario', () {
      const deviceNow = 1788000000000; // device behind host newest
      const maxUpdatedAt = 1788226858979; // host newest in future vs device
      final hostSynced = maxUpdatedAt > deviceNow ? maxUpdatedAt : deviceNow;
      expect(hostSynced, maxUpdatedAt);
      // Old row 1788019388013 is 2.4d before max → should still be 2d, not now
      expect(timeLabel(1788019388013, hostSynced), '2d');
      // Only the max row itself is now
      expect(timeLabel(maxUpdatedAt, hostSynced), 'now');
      // If we had NOT synced (used deviceNow), many rows would clamp to now
      expect(timeLabel(maxUpdatedAt, deviceNow), 'now');
      expect(timeLabel(1788111986893, deviceNow), 'now'); // device behind → future → now (bug)
    });
  });
}
