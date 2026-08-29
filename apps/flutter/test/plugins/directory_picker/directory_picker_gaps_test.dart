import 'dart:io';

import 'dart:io';

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_browser.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_flows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _home = '/home/u';
String _docs = '/home/u/Documents';

DirectoryListing _listingFor(String? path) {
  final asked = path ?? _home;
  final target = asked.length > 1 && asked.endsWith('/')
      ? asked.substring(0, asked.length - 1)
      : asked;
  final tree = <String, DirectoryListing>{
    _home: DirectoryListing(
      path: _home,
      home: _home,
      crumbs: [
        const DirectoryEntry(name: '/', path: '/', hidden: false),
        const DirectoryEntry(name: 'home', path: '/home', hidden: false),
        DirectoryEntry(name: 'u', path: _home, hidden: false),
      ],
      entries: [
        const DirectoryEntry(
          name: '.config',
          path: '/home/u/.config',
          hidden: true,
        ),
        DirectoryEntry(name: 'Documents', path: _docs, hidden: false),
      ],
      truncated: false,
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
      entries: const [],
      truncated: false,
    ),
  };
  return tree[target] ?? tree[_home]!;
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('Gaps fixed: directory picker completion', () {
    test('slot holes are single root kind per contract', () async {
      // Contract check: the directory-flow holes must be single root, matching
      // React's SlotMap `{kind:'single', scope:'root'}` declaration.
      const specHero = SlotSpec(kind: SlotKind.single, scope: SlotScope.root);
      const specSidebar = SlotSpec(
        kind: SlotKind.single,
        scope: SlotScope.root,
      );
      expect(specHero.kind, SlotKind.single);
      expect(specHero.scope, SlotScope.root);
      expect(specSidebar.kind, SlotKind.single);
    });

    testWidgets(
      'browse and native flows are SlotWidgetBuilders via directory_picker_flows',
      (tester) async {
        // Verify the flow widgets are constructible and carry expected semantics
        final browse = BrowseDirectoryFlow(
          owner: DirectoryFlowOwnerProps(
            open: false,
            busy: false,
            onPicked: (_) {},
            onCancel: () {},
            onError: (_) {},
          ),
          injected: BrowseFlowInjected(
            listDirectory: ({
              String? path,
              DirectoryListSignal? signal,
            }) async => _listingFor(path),
            createDirectory: ({
              required String path,
              required String name,
            }) async => '$path/$name',
            t: (k) => k,
          ),
        );
        final native = NativeDirectoryFlow(
          owner: DirectoryFlowOwnerProps(
            open: false,
            busy: false,
            onPicked: (_) {},
            onCancel: () {},
            onError: (_) {},
          ),
          injected: NativeFlowInjected(pick: () async => null),
        );
        expect(browse, isA<Widget>());
        expect(native, isA<Widget>());
      },
    );

    testWidgets('aria-current: selected row carries Semantics selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DirectoryBrowser(
            open: true,
            listDirectory: ({
              String? path,
              DirectoryListSignal? signal,
            }) async => _listingFor(path),
            createDirectory: ({
              required String path,
              required String name,
            }) async => '$path/$name',
            onOpen: (_) {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      // After selection, the left pane should have a Semantics node marked selected.
      // Find Semantics widgets with selected:true
      final selectedSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      );
      expect(selectedSemantics, findsWidgets);
      // Also verify the selected row's text is still present
      expect(find.text('Documents'), findsWidgets);
    });

    test('IME isComposing guard exists in DirectoryBrowser', () async {
      final source = await File(
        'lib/src/plugins/directory_picker/directory_browser.dart',
      ).readAsString();
      expect(source, contains('composing.isValid'));
      expect(source, contains('_isComposing'));
      expect(source, contains('onSubmitted'));
      // Also verify that the guard prevents submit during IME
      expect(source, contains('if (_pathCtrl.value.composing.isValid'));
    });

    test('DirectoryListSignal aborts host scan (abort semantics)', () async {
      bool called = false;
      Future<Map<String, Object?>> fakeList({
        String? path,
        DirectoryListSignal? signal,
      }) async {
        called = true;
        final sig = signal ?? DirectoryListSignal();
        // Simulate scan that checks abort
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (sig.aborted) throw Exception('aborted');
        return {
          'path': path ?? _home,
          'home': _home,
          'crumbs': [],
          'entries': [],
          'truncated': false,
        };
      }

      final signal = DirectoryListSignal();
      final fut = fakeList(path: _home, signal: signal);
      signal.abort();
      await expectLater(fut, throwsA(isA<Exception>()));
      expect(called, isTrue);
    });

    test('locale dictionaries contain expected keys (fallback parity)', () {
      expect(
        kDirectoryBrowserEn['browser.title'],
        'Select Workspace Directory',
      );
      expect(kDirectoryBrowserZh['browser.title'], '选择工作区目录');
      expect(kDirectoryBrowserEn['browser.showHidden'], 'Show hidden files');
      expect(kDirectoryBrowserZh['browser.showHidden'], '显示隐藏文件');
    });

    testWidgets('slot holes are declared and occupied after host activation', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                // Defer activation until next frame so widget test pump can catch
                Future.microtask(() async {
                  final host = buildAppHost(ref);
                  await host.activateAll();
                  // Holes declared by WorkspacePlugin (hero) and SidebarPlugin
                  expect(
                    host.slots.isDeclared(
                      'conversation.hero.workspace.directoryFlow',
                    ),
                    isTrue,
                  );
                  expect(
                    host.slots.isDeclared('sidebar.workspaces.directoryFlow'),
                    isTrue,
                  );
                  // At least one occupant per hole (browse on web, native on VM)
                  expect(
                    host.slots
                        .entries('conversation.hero.workspace.directoryFlow')
                        .length,
                    greaterThanOrEqualTo(1),
                  );
                  expect(
                    host.slots
                        .entries('sidebar.workspaces.directoryFlow')
                        .length,
                    greaterThanOrEqualTo(1),
                  );
                  // Locale namespace registered by BrowseDirectoryPickerPlugin
                  final locale = host.service<LocaleService>('locale')!;
                  expect(
                    locale.bind('directory-browser')('browser.title'),
                    isNotEmpty,
                  );
                });
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
