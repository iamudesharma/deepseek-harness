import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_browser.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_flows.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_plugin.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/file_browser.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/file_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DirectoryListing _level(String path, List<DirectoryEntry> entries) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final crumbs = <DirectoryEntry>[
    const DirectoryEntry(name: '/', path: '/', hidden: false),
  ];
  var acc = '';
  for (final segment in segments) {
    acc += '/$segment';
    crumbs.add(DirectoryEntry(name: segment, path: acc, hidden: false));
  }
  return DirectoryListing(
    path: path,
    home: '/home/u',
    crumbs: crumbs,
    entries: entries,
    truncated: false,
  );
}

void main() {
  /// Pumps until [finder] matches; the screen loads asynchronously and the
  /// loading spinner never settles under `pumpAndSettle`.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('never settled for $finder');
  }

  testWidgets('directories navigate, files open the preview sheet', (
    tester,
  ) async {
    final levels = <String, DirectoryListing>{
      '/home/u/repo': _level('/home/u/repo', [
        const DirectoryEntry(
          name: 'src',
          path: '/home/u/repo/src',
          hidden: false,
        ),
        const DirectoryEntry(
          name: 'notes.txt',
          path: '/home/u/repo/notes.txt',
          hidden: false,
          kind: DirectoryEntryKind.file,
        ),
      ]),
      '/home/u/repo/src': _level('/home/u/repo/src', [
        const DirectoryEntry(
          name: 'main.dart',
          path: '/home/u/repo/src/main.dart',
          hidden: false,
          kind: DirectoryEntryKind.file,
        ),
      ]),
    };
    var reads = 0;
    Future<DirectoryListing> list({required String path}) async =>
        levels[path]!;
    Future<Map<String, Object?>> read({
      required String path,
      int? offset,
      int? count,
    }) async {
      reads++;
      return {
        'path': path,
        'text': 'hello $path',
        'truncated': false,
        'totalBytes': 20,
        'totalLines': 1,
      };
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kDirectoryBrowserLocaleNs, {
          'zh': kDirectoryBrowserZh,
          'en': kDirectoryBrowserEn,
        });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: FileBrowserScreen(
              rootPath: '/home/u/repo',
              listLevel: list,
              readFile: read,
            ),
          ),
        ),
      ),
    );
    await pumpUntil(tester, find.text('notes.txt'));

    // Root level: one directory and one file row.
    expect(find.text('src'), findsOneWidget);

    // Entering the directory navigates; the back button returns.
    await tester.tap(find.text('src'));
    await pumpUntil(tester, find.text('main.dart'));
    await tester.tap(find.byTooltip('Back'));
    await pumpUntil(tester, find.text('notes.txt'));

    // Tapping a file opens the preview sheet and reads exactly once.
    await tester.tap(find.text('notes.txt'));
    await pumpUntil(
      tester,
      find.text('hello /home/u/repo/notes.txt'),
    );
    expect(reads, 1);
  });

  testWidgets('preview pager turns pages and reports position', (
    tester,
  ) async {
    final calls = <int>[];
    Future<Map<String, Object?>> read({
      required String path,
      int? offset,
      int? count,
    }) async {
      calls.add(offset ?? 0);
      final last = (offset ?? 0) >= 100;
      return {
        'path': path,
        'text': last ? 'tail' : 'head',
        'truncated': !last,
        'totalBytes': 200,
        if (last) 'totalLines': 101,
      };
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kDirectoryBrowserLocaleNs, {
          'zh': kDirectoryBrowserZh,
          'en': kDirectoryBrowserEn,
        });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: FilePreviewSheet(path: '/home/u/repo/big.log', readFile: read),
          ),
        ),
      ),
    );
    await pumpUntil(tester, find.text('head'));

    // Next page reads at the next window; the last page reports totals.
    // Tooltips render the registered zh copy.
    await tester.tap(find.byTooltip(kDirectoryBrowserZh['preview.next']!));
    await pumpUntil(tester, find.text('tail'));
    expect(calls, [0, 100]);
    // Previous page returns to the head without totals.
    await tester.tap(find.byTooltip(kDirectoryBrowserZh['preview.prev']!));
    await pumpUntil(tester, find.text('head'));
    expect(calls, [0, 100, 0]);
  });

  testWidgets('preview failure surfaces with retry', (tester) async {
    var attempts = 0;
    Future<Map<String, Object?>> read({
      required String path,
      int? offset,
      int? count,
    }) async {
      attempts++;
      if (attempts == 1) throw Exception('cannot read it');
      return {
        'path': path,
        'text': 'recovered',
        'truncated': false,
        'totalBytes': 9,
        'totalLines': 1,
      };
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kDirectoryBrowserLocaleNs, {
          'zh': kDirectoryBrowserZh,
          'en': kDirectoryBrowserEn,
        });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: FilePreviewSheet(path: '/home/u/repo/x.txt', readFile: read),
          ),
        ),
      ),
    );
    await pumpUntil(tester, find.textContaining('cannot read it'));

    await tester.tap(find.text('Retry'));
    await pumpUntil(tester, find.text('recovered'));
    expect(attempts, 2);
  });
}
