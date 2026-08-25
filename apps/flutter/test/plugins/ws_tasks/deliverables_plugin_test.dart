import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/deliverables/deliverables_mentions.dart';
import 'package:dsh_flutter/src/plugins/deliverables/deliverables_plugin.dart';
import 'package:dsh_flutter/src/plugins/deliverables/locales.dart';
import 'package:dsh_flutter/src/plugins/deliverables/ui/deliverables_screen.dart';
import 'package:dsh_flutter/src/plugins/deliverables/ui/produced_files_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

void main() {
  test('activation provides the chatFileMentions service and the dictionaries',
      () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    final locale = host.service<LocaleService>('locale')!;
    host.register(const DeliverablesPlugin());
    await host.activateAll();

    expect(host.service<ChatFileMentions>(kChatFileMentionsServiceName),
        isNotNull);
    expect(locale.bind(kDeliverablesNamespace)('produced.label'), '产物');
    locale.setLocale('en');
    expect(locale.bind(kDeliverablesNamespace)('produced.label'), 'Produced');
    expect(kDeliverablesEn.keys.toSet(), kDeliverablesZh.keys.toSet());

    host.deactivate(kDeliverablesPluginId);
    expect(
        host.service<ChatFileMentions>(kChatFileMentionsServiceName), isNull);
  });

  test('mentions resolve by exact path, then unique basename; ambiguity stays inert',
      () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(const DeliverablesPlugin());
    await host.activateAll();

    final mentions =
        host.service<ChatFileMentions>(kChatFileMentionsServiceName)!;
    final opened = <String>[];
    void open(String path) => opened.add(path);

    const paths = ['out/index.html', 'src/app.css', 'a/README.md', 'b/README.md'];
    expect(mentions.resolve(paths: paths, token: 'src/app.css', openFile: open)!.path,
        'src/app.css');
    expect(mentions.resolve(paths: paths, token: 'index.html', openFile: open)!.path,
        'out/index.html');
    // A basename two produced paths share never guesses.
    expect(mentions.resolve(paths: paths, token: 'README.md', openFile: open), isNull);
    expect(mentions.resolve(paths: paths, token: 'nope.txt', openFile: open), isNull);

    mentions.resolve(paths: paths, token: 'index.html', openFile: open)!.open();
    expect(opened, ['out/index.html']);
  });

  test('producedForClosing keeps first-seen order, dedupes, and respects the closing seq', () {
    expect(producedForClosing(null), isEmpty);
    final data = DeliverablesTurnData(const [
      (seq: 2, path: 'out/index.html'),
      (seq: 5, path: 'src/app.css'),
      (seq: 7, path: 'out/index.html'),
      (seq: 9, path: 'late.txt'),
    ]);
    expect(producedForClosing(data),
        ['out/index.html', 'src/app.css', 'late.txt']);
    // The closing assistant's seq excludes later Tool settlements.
    expect(producedForClosing(data, closingSeq: 6),
        ['out/index.html', 'src/app.css']);
  });

  testWidgets('the row renders basename chips with a counted remainder and gated folder action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProducedFilesRow(
          paths: [
            for (var i = 0; i < 8; i++) 'dist/asset$i.js',
          ],
          canOpenPath: true,
          onOpenFile: (_) {},
        ),
      ),
    ));

    expect(find.text('Produced'), findsOneWidget);
    expect(find.text('asset0.js'), findsOneWidget);
    expect(find.text('asset5.js'), findsOneWidget);
    expect(find.text('asset6.js'), findsNothing); // six-chip cap
    expect(find.text('+ 2 files'), findsOneWidget);
    expect(find.text('Show in folder'), findsOneWidget);
  });

  testWidgets('without the Host capability the folder action stays off; empty turns render the screen empty state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProducedFilesRow(paths: ['only.md']),
      ),
    ));
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.text('Show in folder'), findsNothing);

    // The empty state resolves deliverables.empty.title through the shared
    // LocaleService; register the namespace like the owning plugin's apply.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(localeServiceProvider).register(
        kDeliverablesNamespace, {'zh': kDeliverablesZh, 'en': kDeliverablesEn});
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DeliverablesScreen()),
    ));
    expect(find.text('暂无产物'), findsOneWidget);
  });
}
