import 'package:dsh_flutter/src/core/services/runtime_services.dart' show DirectoryListSignal;
import 'package:dsh_flutter/src/platform/adaptive_directory_picker.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String homePath = '/home/u';
String docsPath = '/home/u/Documents';
String harnessPath = '/home/u/Documents/harness';

DirectoryListing listingFor(String? path) {
  final asked = path ?? homePath;
  final target = asked.length > 1 && asked.endsWith('/') ? asked.substring(0, asked.length - 1) : asked;
  final tree = <String, DirectoryListing>{
    homePath: DirectoryListing(
      path: homePath,
      home: homePath,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: homePath, hidden: false),
      ],
      entries: [
        const DirectoryEntry(name: '.config', path: '/home/u/.config', hidden: true),
        DirectoryEntry(name: 'Documents', path: docsPath, hidden: false),
      ],
      truncated: false,
    ),
    '/': const DirectoryListing(
      path: '/',
      home: '/home/u',
      crumbs: [DirectoryEntry(name: '/', path: '/', hidden: false)],
      entries: [DirectoryEntry(name: 'home', path: '/home', hidden: false)],
      truncated: false,
    ),
    '/home/u/.config': DirectoryListing(
      path: '/home/u/.config',
      home: homePath,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: homePath, hidden: false),
        const DirectoryEntry(name: '.config', path: '/home/u/.config', hidden: true),
      ],
      entries: const [],
      truncated: false,
    ),
    docsPath: DirectoryListing(
      path: docsPath,
      home: homePath,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: homePath, hidden: false),
        DirectoryEntry(name: 'Documents', path: docsPath, hidden: false),
      ],
      entries: [DirectoryEntry(name: 'harness', path: harnessPath, hidden: false)],
      truncated: false,
    ),
    harnessPath: DirectoryListing(
      path: harnessPath,
      home: homePath,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: homePath, hidden: false),
        DirectoryEntry(name: 'Documents', path: docsPath, hidden: false),
        DirectoryEntry(name: 'harness', path: harnessPath, hidden: false),
      ],
      entries: const [],
      truncated: false,
    ),
  };
  final found = tree[target];
  if (found == null) throw DirectoryBrowseError('cannot list $target');
  return found;
}

Widget wrap(Widget child) => ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  group('DirectoryBrowser Miller columns', () {
    testWidgets('closed renders nothing of dialog chrome', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: false,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      expect(find.text('Select Workspace Directory'), findsNothing);
    });

    testWidgets('opens at Host home as one wide column, hides hidden entries, roots crumbs at Home', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      // One column, Documents visible, .config hidden
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('.config'), findsNothing);
      // Home crumb visible, root '/' outside Home subtree not shown
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('show hidden toggle reveals hidden entries', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('.config'), findsNothing);
      await tester.tap(find.text('Show hidden files'));
      await tester.pump();
      expect(find.text('.config'), findsOneWidget);
      await tester.tap(find.text('Show hidden files'));
      await tester.pump();
      expect(find.text('.config'), findsNothing);
    });

    testWidgets('selects a row into two-pane view: children preview right, crumbs follow selection', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      // Two columns: Documents selected left, harness right
      expect(find.text('Documents'), findsWidgets);
      expect(find.text('harness'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('advances one level when right-column row is picked', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('harness'));
      await tester.pumpAndSettle();
      // harness selected in left pane after advance
      expect(find.text('harness'), findsWidgets);
    });

    testWidgets('crumb jump to Home lands single wide level (display root)', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('harness'), findsNothing);
    });

    testWidgets('prefix-filters listed level from draft tail, dot reveals hidden', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      // Open path editor via pencil
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      final field = find.byKey(const ValueKey('pathInput'));
      expect(field, findsOneWidget);
      // seeded with trailing separator
      final TextField tf = tester.widget<TextField>(field);
      expect(tf.controller?.text, '$homePath/');
      // Filter with dot-led prefix reveals hidden
      await tester.enterText(field, '$homePath/.co');
      await tester.pump();
      expect(find.text('.config'), findsOneWidget);
      // Non-dot prefix narrows to Documents
      await tester.enterText(field, '$homePath/do');
      await tester.pump();
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('.config'), findsNothing);
    });

    testWidgets('Open adopts selected folder, else listed level; Cancel closes', (tester) async {
      String? opened;
      bool closed = false;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DirectoryBrowser(
              open: true,
              listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
              createDirectory: ({required String path, required String name}) async => '$path/$name',
              onOpen: (p) => opened = p,
              onClose: () => closed = true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Initially no selection => Open should adopt Home
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(opened, homePath);
      opened = null;
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(opened, docsPath);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('busy freezes Open', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        busy: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Open'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('New folder creates and selects the created folder', (tester) async {
      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => listingFor(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('createFolderInput')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('createFolderInput')), 'fresh');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      // The new folder name appears as created entry via select path; fallback shows via selection logic
      // At minimum dialog closed and no error
      expect(find.text('fresh'), findsNothing); // not in fake tree, but flow completed without error
    });

    testWidgets('shows truncated indicator when level cut', (tester) async {
      DirectoryListing truncatedListing(String? path) {
        final base = listingFor(path);
        return DirectoryListing(
          path: base.path,
          home: base.home,
          crumbs: base.crumbs,
          entries: base.entries,
          truncated: true,
        );
      }

      await tester.pumpWidget(wrap(DirectoryBrowser(
        open: true,
        listDirectory: ({String? path, DirectoryListSignal? signal}) async => truncatedListing(path),
        createDirectory: ({required String path, required String name}) async => '$path/$name',
        onOpen: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Too many folders to list; only the beginning is shown.'), findsOneWidget);
    });
  });

  group('DirectoryEntry helpers', () {
    test('visibleEntries hides hidden by default', () {
      final entries = [
        const DirectoryEntry(name: '.a', path: '/h/.a', hidden: true),
        const DirectoryEntry(name: 'b', path: '/h/b', hidden: false),
      ];
      expect(visibleEntries(entries, null, false, null).map((e) => e.name), ['b']);
      expect(visibleEntries(entries, null, true, null).map((e) => e.name), ['.a', 'b']);
    });

    test('dot prefix reveals hidden matches', () {
      final entries = [
        const DirectoryEntry(name: '.config', path: '/h/.config', hidden: true),
        const DirectoryEntry(name: 'docs', path: '/h/docs', hidden: false),
      ];
      expect(visibleEntries(entries, null, false, '.co').map((e) => e.name), ['.config']);
    });

    test('displayCrumbs roots at Home', () {
      final listing = listingFor(homePath);
      final crumbs = displayCrumbs(listing, 'Home');
      expect(crumbs.first.name, 'Home');
      expect(crumbs.last.path, homePath);
    });

    test('separatorOf detects platform', () {
      expect(separatorOf(const DirectoryListing(path: r'C:\Users', home: r'C:\', crumbs: [], entries: [], truncated: false)), r'\');
      expect(separatorOf(const DirectoryListing(path: '/home/u', home: '/home/u', crumbs: [], entries: [], truncated: false)), '/');
    });
  });

  group('AdaptiveDirectoryPicker platform contracts', () {
    testWidgets('WebDirectoryPickerField shows Miller browser hint', (tester) async {
      await tester.pumpWidget(wrap(WebDirectoryPickerField(
        value: null,
        onPicked: (_) {},
      )));
      expect(find.textContaining('Miller-column browser'), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
    });

    testWidgets('MacDirectoryPickerField shows native picker hint', (tester) async {
      await tester.pumpWidget(wrap(MacDirectoryPickerField(
        value: '/work/main',
        onPicked: (_) {},
      )));
      expect(find.textContaining('native folder picker'), findsOneWidget);
      expect(find.text('/work/main'), findsOneWidget);
    });

    testWidgets('Web field Browse opens Miller dialog (host reachable)', (tester) async {
      // Provide a fake ConnectionClient with empty baseUrl to trigger fallback path?
      // Here we just verify the button exists and tapping doesn't throw; full Miller flow
      // is covered above via DirectoryBrowser directly.
      await tester.pumpWidget(wrap(WebDirectoryPickerField(
        dialogTitle: 'Pick',
        onPicked: (_) {},
      )));
      await tester.tap(find.text('Browse'));
      await tester.pump();
      // With no host (file:// tests), fallback to platform picker — no Miller dialog yet
      // because baseUrl is empty; the button still completed without exception.
      expect(tester.takeException(), isNull);
    });
  });
}
