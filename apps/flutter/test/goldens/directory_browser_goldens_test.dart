/// Miller-column goldens — 680×500 DirectoryBrowser states pinned as golden
/// evidence for the directory-picker completion workstream.
///
/// Each variant renders the production [DirectoryBrowser] through the same
/// listing fixture the widget tests use, but isolates one visual state per
/// golden: light/dark, one vs two pane, show-hidden, dot filtered (hidden
/// dot-reveal), truncated notice, and nested create dialog. The goldens
/// document the 680×500 clamped dialog, header/breadcrumb/edit zone, Miller
/// row 2×320 split around divider (256 floor honored via 320), footer wrap,
/// and dark/light aliases. They are the visual parity evidence for
/// `platform.ui-directory-picker-browse` / `platform.directoryPicker` →
/// Integrated.
library;

import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show DirectoryListSignal;
import 'package:dsh_flutter/src/plugins/directory_picker/directory_browser.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _home = '/home/u';
String _docs = '/home/u/Documents';
String _harness = '/home/u/Documents/harness';

DirectoryListing _listingFor(String? path, {bool truncated = false}) {
  final asked = path ?? _home;
  final target = asked.length > 1 && asked.endsWith('/')
      ? asked.substring(0, asked.length - 1)
      : asked;
  final entriesForHome = [
    const DirectoryEntry(
      name: '.config',
      path: '/home/u/.config',
      hidden: true,
    ),
    DirectoryEntry(name: 'Documents', path: _docs, hidden: false),
    const DirectoryEntry(
      name: 'very-long-directory-name-that-should-truncate-with-ellipsis-when-overflow',
      path: '/home/u/very-long-directory-name-that-should-truncate-with-ellipsis-when-overflow',
      hidden: false,
    ),
  ];
  final tree = <String, DirectoryListing>{
    _home: DirectoryListing(
      path: _home,
      home: _home,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: _home, hidden: false),
      ],
      entries: entriesForHome,
      truncated: truncated,
    ),
    _docs: DirectoryListing(
      path: _docs,
      home: _home,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: _home, hidden: false),
        DirectoryEntry(name: 'Documents', path: _docs, hidden: false),
      ],
      entries: [DirectoryEntry(name: 'harness', path: _harness, hidden: false)],
      truncated: false,
    ),
    _harness: DirectoryListing(
      path: _harness,
      home: _home,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: _home, hidden: false),
        DirectoryEntry(name: 'Documents', path: _docs, hidden: false),
        DirectoryEntry(name: 'harness', path: _harness, hidden: false),
      ],
      entries: const [],
      truncated: false,
    ),
    '/home/u/.config': DirectoryListing(
      path: '/home/u/.config',
      home: _home,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: _home, hidden: false),
        const DirectoryEntry(
          name: '.config',
          path: '/home/u/.config',
          hidden: true,
        ),
      ],
      entries: const [],
      truncated: false,
    ),
  };
  final found = tree[target];
  if (found == null) throw DirectoryBrowseError('cannot list $target');
  return found;
}

Widget _wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? buildDarkTheme() : buildLightTheme(),
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: Center(child: child)),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}

Future<void> _pumpBrowser(
  WidgetTester tester, {
  bool dark = false,
  Future<DirectoryListing> Function({
    String? path,
    DirectoryListSignal? signal,
  })?
  list,
  String? showHiddenAction,
  String? dotPrefix,
  bool truncated = false,
  bool twoPane = false,
  bool nestedCreate = false,
}) async {
  _setViewport(tester, const Size(720, 600));
  final listFn =
      list ??
      ({String? path, DirectoryListSignal? signal}) async =>
          _listingFor(path, truncated: truncated);
  await tester.pumpWidget(
    _wrap(
      DirectoryBrowser(
        open: true,
        listDirectory: listFn,
        createDirectory: ({required String path, required String name}) async =>
            '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      ),
      dark: dark,
    ),
  );
  await tester.pumpAndSettle();
  if (twoPane) {
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
  }
  if (showHiddenAction != null) {
    await tester.tap(find.text('Show hidden files'));
    await tester.pump();
  }
  if (dotPrefix != null) {
    await tester.tap(find.byTooltip('Edit path'));
    await tester.pump();
    final field = find.byKey(const ValueKey('pathInput'));
    await tester.enterText(field, '$_home/$dotPrefix');
    await tester.pump();
  }
  if (nestedCreate) {
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('directory browser - single pane light 680x500', (tester) async {
    await _pumpBrowser(tester, dark: false, twoPane: false);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_single_light.png'),
    );
  });

  testWidgets('directory browser - single pane dark 680x500', (tester) async {
    await _pumpBrowser(tester, dark: true, twoPane: false);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_single_dark.png'),
    );
  });

  testWidgets('directory browser - two pane light (Documents selected)', (
    tester,
  ) async {
    await _pumpBrowser(tester, dark: false, twoPane: true);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_two_pane_light.png'),
    );
  });

  testWidgets('directory browser - two pane dark', (tester) async {
    await _pumpBrowser(tester, dark: true, twoPane: true);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_two_pane_dark.png'),
    );
  });

  testWidgets('directory browser - show hidden reveals dot file', (
    tester,
  ) async {
    await _pumpBrowser(tester, dark: false, showHiddenAction: 'tap');
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_show_hidden_light.png'),
    );
  });

  testWidgets('directory browser - dot prefix filters hidden reveal', (
    tester,
  ) async {
    await _pumpBrowser(tester, dark: false, dotPrefix: '.co');
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_dot_filtered_light.png'),
    );
  });

  testWidgets('directory browser - truncated notice', (tester) async {
    await _pumpBrowser(tester, dark: false, truncated: true);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_truncated_light.png'),
    );
  });

  testWidgets('directory browser - nested create dialog', (tester) async {
    await _pumpBrowser(tester, dark: false, nestedCreate: true);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_nested_create_light.png'),
    );
  });

  testWidgets('directory browser - truncated ellipsis for long name', (
    tester,
  ) async {
    await _pumpBrowser(tester, dark: false, twoPane: false);
    // The home listing contains a very long name that should ellipsize
    expect(find.textContaining('very-long'), findsOneWidget);
    await expectLater(
      find.byType(DirectoryBrowser),
      matchesGoldenFile('goldens/directory_browser_long_name_light.png'),
    );
  });
}
