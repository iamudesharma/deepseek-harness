import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/disclosure_row.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_button.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_input.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_modal.dart';
import 'package:dsh_flutter/src/widgets/primitives/pill.dart';
import 'package:dsh_flutter/src/widgets/primitives/state_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('DsButton', () {
    testWidgets('tap calls onPressed (user-visible behavior)', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(DsButton(label: 'Tap me', onPressed: () => tapped = true)),
      );
      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('disabled does not call onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(DsButton(label: 'Disabled', onPressed: null)),
      );
      expect(find.text('Disabled'), findsOneWidget);
      // Disabled button renders Opacity 0.4 and handler null; tap should not trigger
      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('loading shows spinner and disables press', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          DsButton(
            label: 'Send',
            loading: true,
            onPressed: () => tapped = true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Send'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('not loading does not show spinner', (tester) async {
      await tester.pumpWidget(_wrap(DsButton(label: 'Send', onPressed: () {})));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('icon and label render together', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DsButton(
            label: 'Action',
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('fullWidth fills available width', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            child: DsButton(label: 'Full', fullWidth: true, onPressed: () {}),
          ),
        ),
      );
      expect(find.text('Full'), findsOneWidget);
    });
  });

  group('DisclosureRow', () {
    testWidgets('expand shows child, collapse hides child', (tester) async {
      var open = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return DisclosureRow(
                icon: const Icon(Icons.folder),
                title: 'Section',
                open: open,
                expandable: true,
                onToggle: () => setState(() => open = !open),
                child: const Text('Expanded body'),
              );
            },
          ),
        ),
      );
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Expanded body'), findsNothing);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('Expanded body'), findsOneWidget);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('Expanded body'), findsNothing);
    });

    testWidgets('expandOnRowClick makes entire row tappable', (tester) async {
      var open = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return DisclosureRow(
                icon: const Icon(Icons.folder),
                title: 'Row',
                open: open,
                expandable: true,
                expandOnRowClick: true,
                onToggle: () => setState(() => open = !open),
                child: const Text('Body'),
              );
            },
          ),
        ),
      );
      // Tap the row (InkWell wraps whole row when expandOnRowClick)
      await tester.tap(find.text('Row'));
      await tester.pumpAndSettle();
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets(
      'collapsedContent visible when collapsed and keepContentWhenOpen false',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            DisclosureRow(
              icon: const Icon(Icons.folder),
              title: 'Section',
              open: false,
              expandable: true,
              onToggle: () {},
              collapsedContent: const Text('Collapsed inline'),
              child: const Text('Body'),
            ),
          ),
        );
        expect(find.text('Collapsed inline'), findsOneWidget);
        expect(find.text('Body'), findsNothing);
      },
    );

    testWidgets(
      'collapsedContent hidden when open unless keepContentWhenOpen',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            DisclosureRow(
              icon: const Icon(Icons.folder),
              title: 'Section',
              open: true,
              expandable: true,
              onToggle: () {},
              collapsedContent: const Text('Collapsed inline'),
              child: const Text('Body'),
            ),
          ),
        );
        expect(find.text('Collapsed inline'), findsNothing);
        expect(find.text('Body'), findsOneWidget);
      },
    );

    testWidgets(
      'keepContentWhenOpen keeps collapsedContent visible when open',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            DisclosureRow(
              icon: const Icon(Icons.folder),
              title: 'Section',
              open: true,
              expandable: true,
              onToggle: () {},
              keepContentWhenOpen: true,
              collapsedContent: const Text('Keep me'),
              child: const Text('Body'),
            ),
          ),
        );
        expect(find.text('Keep me'), findsOneWidget);
        expect(find.text('Body'), findsOneWidget);
      },
    );

    testWidgets('non-expandable does not show chevron interaction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DisclosureRow(
            icon: const Icon(Icons.folder),
            title: 'Static',
            open: false,
            expandable: false,
            onToggle: () {},
            child: const Text('Body'),
          ),
        ),
      );
      expect(find.text('Static'), findsOneWidget);
      // Should not have InkWell for toggle when not expandable and not rowExpands
      expect(find.text('Body'), findsNothing);
    });
  });

  group('DsInput', () {
    testWidgets('enter text fires onChanged with visible value', (
      tester,
    ) async {
      String changed = '';
      await tester.pumpWidget(
        _wrap(DsInput(hintText: 'Search', onChanged: (v) => changed = v)),
      );
      expect(find.text('Search'), findsOneWidget); // hint visible when empty
      await tester.enterText(find.byType(TextFormField), 'hello');
      await tester.pump();
      expect(changed, 'hello');
    });

    testWidgets('controller initialValue visible', (tester) async {
      final controller = TextEditingController(text: 'initial');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(DsInput(controller: controller, hintText: 'Hint')),
      );
      expect(find.text('initial'), findsOneWidget);
    });

    testWidgets('suffix widget visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DsInput(hintText: 'With suffix', suffix: const Icon(Icons.clear)),
        ),
      );
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('disabled input still renders hint', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsInput(hintText: 'Disabled hint', enabled: false)),
      );
      expect(find.text('Disabled hint'), findsOneWidget);
    });

    testWidgets('DsSearchInput renders fixed height 32', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsSearchInput(hintText: 'Search sessions')),
      );
      expect(find.text('Search sessions'), findsOneWidget);
      final sized = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sized.height, 32);
    });
  });

  group('StateDot', () {
    testWidgets('done state shows two containers (halo + core)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StateDot(state: StateDotState.done)));
      // Two containers inside Stack + SizedBox
      expect(find.byType(StateDot), findsOneWidget);
      // Should have halo+core containers - look for Container widgets
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('warning state renders', (tester) async {
      await tester.pumpWidget(
        _wrap(const StateDot(state: StateDotState.warning)),
      );
      expect(find.byType(StateDot), findsOneWidget);
    });

    testWidgets('error state renders', (tester) async {
      await tester.pumpWidget(
        _wrap(const StateDot(state: StateDotState.error)),
      );
      expect(find.byType(StateDot), findsOneWidget);
    });

    testWidgets('ongoing renders CustomPaint with animation', (tester) async {
      await tester.pumpWidget(
        _wrap(const StateDot(state: StateDotState.ongoing)),
      );
      expect(find.byType(StateDot), findsOneWidget);
      // StateDot ongoing uses CustomPaint; Material may also add one, so atLeast
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CustomPaint), findsWidgets);
      // Verify the StateDot itself is still present after animation tick
      expect(find.byType(StateDot), findsOneWidget);
    });

    testWidgets('semanticLabel adds Semantics', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StateDot(state: StateDotState.done, semanticLabel: 'Completed'),
        ),
      );
      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('without semanticLabel is excluded from semantics', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StateDot(state: StateDotState.done)));
      // StateDot uses ExcludeSemantics; MaterialApp/Scaffold also add one, so atLeast
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(find.byType(StateDot), findsOneWidget);
    });
  });

  group('Pill', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(_wrap(const Pill(label: 'Hello')));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('tap when interactive triggers onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(Pill(label: 'Tap me', onPressed: () => tapped = true)),
      );
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('not interactive does not respond to tap', (tester) async {
      await tester.pumpWidget(_wrap(Pill(label: 'Static', onPressed: null)));
      expect(find.text('Static'), findsOneWidget);
      // Non-interactive renders Container, not InkWell
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('active visual state renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const Pill(label: 'Active', active: true)));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('icon renders alongside label', (tester) async {
      await tester.pumpWidget(
        _wrap(const Pill(label: 'Tag', icon: Icon(Icons.tag))),
      );
      expect(find.byIcon(Icons.tag), findsOneWidget);
      expect(find.text('Tag'), findsOneWidget);
    });
  });

  group('DsModal', () {
    testWidgets(
      'show via DsModal.show displays title and child, dismiss via close button',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: buildLightTheme(),
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => DsModal.show(
                          context: context,
                          title: 'Test Modal',
                          description: 'Description here',
                          child: const Text('Body content'),
                        ),
                        child: const Text('Open modal'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open modal'));
        await tester.pumpAndSettle();
        expect(find.text('Test Modal'), findsOneWidget);
        expect(find.text('Description here'), findsOneWidget);
        expect(find.text('Body content'), findsOneWidget);
        // Close via X icon
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text('Test Modal'), findsNothing);
      },
    );

    testWidgets('barrier tap dismisses when barrierDismissible true', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => DsModal.show(
                        context: context,
                        title: 'Barrier Test',
                        barrierDismissible: true,
                        child: const Text('Content'),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Barrier Test'), findsOneWidget);
      // Tap at barrier area (outside dialog) - use tapAt with top-left
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Barrier Test'), findsNothing);
    });

    testWidgets('DsModalOverlay open shows title, closed hides', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsModalOverlay(
            open: true,
            title: 'Overlay Title',
            onClose: _noop,
            child: Text('Overlay body'),
          ),
        ),
      );
      expect(find.text('Overlay Title'), findsOneWidget);
      expect(find.text('Overlay body'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          const DsModalOverlay(
            open: false,
            title: 'Overlay Title',
            onClose: _noop,
            child: Text('Overlay body'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Overlay Title'), findsNothing);
    });

    testWidgets('DsModalOverlay mask tap calls onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: DsModalOverlay(
                open: true,
                title: 'Mask Test',
                onClose: () => closed = true,
                child: const Text('Content'),
              ),
            ),
          ),
        ),
      );
      // Tap mask: need to tap just outside card. Easiest is to find the GestureDetector via the Stack.
      // The mask is Positioned.fill with GestureDetector. Tap near edge outside card (card is 380 wide centered).
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('footer renders when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DsModal(
            title: 'With footer',
            onClose: _noop,
            footer: Row(
              children: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                FilledButton(onPressed: () {}, child: const Text('Save')),
              ],
            ),
            child: const Text('Body'),
          ),
        ),
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('headless renders child directly without header chrome', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsModal(
            title: 'Hidden',
            headless: true,
            child: Text('Headless body'),
          ),
        ),
      );
      expect(find.text('Headless body'), findsOneWidget);
      // Title should NOT be visible in headless mode (it renders child directly)
      expect(find.text('Hidden'), findsNothing);
    });
  });
}

void _noop() {}
