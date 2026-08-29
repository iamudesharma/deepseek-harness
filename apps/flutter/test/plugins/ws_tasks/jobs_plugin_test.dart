import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/conversation/jobs_state.dart';
import 'package:dsh_flutter/src/plugins/jobs/jobs_plugin.dart';
import 'package:dsh_flutter/src/plugins/jobs/job_models.dart';
import 'package:dsh_flutter/src/plugins/jobs/locales.dart';
import 'package:dsh_flutter/src/plugins/jobs/ui/job_list_action.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_link.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

Map<String, Object?> rawJob({
  required String id,
  required String label,
  required String status,
  int startedAt = 1_000,
  int? finishedAt,
  String? detail,
}) => {
  'id': id,
  'kind': id.split('-').first,
  'label': label,
  'status': status,
  'startedAt': startedAt,
  'finishedAt': finishedAt,
  'detail': detail,
};

void main() {
  test('activation installs the header action after the subagent catalog and leaves on deactivation', () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    declareHeaderActionsHole(host);
    host.register(
      SubagentPlugin(
        link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
      ),
    );
    host.register(const JobsPlugin());
    await host.activateAll();

    final ids = [
      for (final w in host.slots.winnersOfSlot(
        'conversation.session.header.actions',
      ))
        w.options.id,
    ];
    // Session lineage reads before process work (React order: 10 then 20).
    expect(ids, [kSubagentCatalogId, kJobListActionId]);

    host.deactivate(kJobsPluginId);
    expect(
      [
        for (final w in host.slots.winnersOfSlot(
          'conversation.session.header.actions',
        ))
          w.options.id,
      ],
      [kSubagentCatalogId],
    );
  });

  test('dictionaries register under the job namespace', () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    final locale = host.service<LocaleService>('locale')!;
    host.register(const JobsPlugin());
    await host.activateAll();

    expect(locale.bind(kJobNamespace)('status.running'), '运行中');
    locale.setLocale('en');
    expect(locale.bind(kJobNamespace)('status.killed'), 'cancelled');
    expect(kJobEn.keys.toSet(), kJobZh.keys.toSet());
  });

  test('rows order live-first by start, settled newest-first; forged statuses fail loud', () {
    final rows = [
      JobViewRow.fromJson(
        rawJob(
          id: 'bash-2',
          label: 'settled old',
          status: 'completed',
          startedAt: 1_000,
          finishedAt: 5_000,
        ),
      ),
      JobViewRow.fromJson(
        rawJob(
          id: 'bash-3',
          label: 'live late',
          status: 'running',
          startedAt: 9_000,
        ),
      ),
      JobViewRow.fromJson(
        rawJob(
          id: 'bash-1',
          label: 'live early',
          status: 'stopping',
          startedAt: 2_000,
        ),
      ),
      JobViewRow.fromJson(
        rawJob(
          id: 'bash-4',
          label: 'settled new',
          status: 'failed',
          startedAt: 3_000,
          finishedAt: 8_000,
          detail: 'exit code: 1',
        ),
      ),
    ];
    expect(
      [for (final r in ordered(rows)) r.id],
      ['bash-1', 'bash-3', 'bash-4', 'bash-2'],
    );

    expect(
      () =>
          JobViewRow.fromJson(rawJob(id: 'x-1', label: '?', status: 'pending')),
      throwsFormatException,
    );

    expect(dotState(JobStatus.killed), 'warning');
    expect(formatDuration(59_000), '59s');
    expect(formatDuration(61_000), '1 m 1s');
    expect(formatDuration(3_600_000), '1h 0m');
    expect(countLabel(0, 1), '1 background job');
    expect(countLabel(2, 5), '2 background jobs running');
  });

  testWidgets('the header action renders nothing for a session without jobs', (
    tester,
  ) async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(const JobsPlugin());
    await host.activateAll();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsProvider.overrideWith((ref) => JobsController()),
          currentSessionIdProvider.overrideWithValue(const SessionId('s1')),
        ],
        child: const MaterialApp(home: Scaffold(body: JobListAction())),
      ),
    );

    expect(find.text('background job'), findsNothing);
    expect(find.byType(JobListAction), findsOneWidget);
  });

  testWidgets('a seeded jobsProvider shows the chip and opens the row list', (
    tester,
  ) async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(const JobsPlugin());
    await host.activateAll();

    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsProvider.overrideWith((ref) {
            final controller = JobsController();
            controller.replace('s1', [
              rawJob(
                id: 'bash-1',
                label: 'pnpm run test:coverage',
                status: 'running',
                startedAt: now - 65_000,
              ),
              rawJob(
                id: 'bash-2',
                label: 'pnpm run lint',
                status: 'failed',
                startedAt: now - 200_000,
                finishedAt: now - 120_000,
                detail: 'exit code: 1',
              ),
            ]);
            return controller;
          }),
          currentSessionIdProvider.overrideWithValue(const SessionId('s1')),
        ],
        child: const MaterialApp(home: Scaffold(body: JobListAction())),
      ),
    );
    await tester.pump();

    // Trigger chip: live count wins the label, dot marks liveness.
    expect(find.text('1 background job running'), findsOneWidget);

    await tester.tap(find.text('1 background job running'));
    // Fixed pump: the popup's entrance animation plus the pulsing live-dot
    // mean pumpAndSettle would never settle.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // Rows carry kind, label, detail-over-status, and elapsed duration.
    expect(find.text('pnpm run test:coverage'), findsOneWidget);
    expect(find.text('pnpm run lint'), findsOneWidget);
    expect(find.text('exit code: 1'), findsOneWidget);
    expect(
      find.text('failed'),
      findsNothing,
    ); // detail replaces the status word
    expect(find.textContaining('m '), findsWidgets);
  });
}
