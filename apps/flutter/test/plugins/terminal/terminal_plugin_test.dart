import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/jobs/jobs_plugin.dart';
import 'package:dsh_flutter/src/plugins/terminal/locales.dart';
import 'package:dsh_flutter/src/plugins/terminal/terminal_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ws_tasks/host_fixture.dart';

void main() {
  test('activation installs the terminal action after job-list and leaves on deactivation', () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    declareHeaderActionsHole(host);
    host.register(const JobsPlugin());
    host.register(const TerminalPlugin());
    await host.activateAll();

    final ids = [
      for (final w in host.slots.winnersOfSlot(
        'conversation.session.header.actions',
      ))
        w.options.id,
    ];
    // Terminal follows process work (React has no entry; order 21 trails
    // the job-list entry at 20).
    expect(ids, [kJobListActionId, kTerminalActionId]);

    host.deactivate(kTerminalPluginId);
    expect(
      [
        for (final w in host.slots.winnersOfSlot(
          'conversation.session.header.actions',
        ))
          w.options.id,
      ],
      [kJobListActionId],
    );
  });

  test('dictionaries register under the terminal namespace with key parity', () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    final locale = host.service<LocaleService>('locale')!;
    host.register(const TerminalPlugin());
    await host.activateAll();

    expect(locale.bind(kTerminalNamespace)('list.aria'), '终端');
    locale.setLocale('en');
    expect(locale.bind(kTerminalNamespace)('list.aria'), 'Terminal');
    expect(kTerminalEn.keys.toSet(), kTerminalZh.keys.toSet());
  });
}
