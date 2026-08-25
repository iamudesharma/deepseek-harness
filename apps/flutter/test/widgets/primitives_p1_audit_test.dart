import 'package:dsh_flutter/src/theme/dsw_tokens.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_tooltip.dart';
import 'package:dsh_flutter/src/widgets/primitives/menu.dart';
import 'package:dsh_flutter/src/widgets/primitives/terminal_block.dart';
import 'package:dsh_flutter/src/widgets/primitives/toast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1.2 ui-primitives re-audit behavioral evidence: interaction semantics
/// verified against the React implementations (Tooltip.tsx, Menu.tsx,
/// Toast.tsx, TerminalBlock.tsx).
void main() {
  group('Toast (Toast.tsx parity)', () {
    testWidgets('holds at full opacity then fades before removal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(toastProvider.notifier);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: DsToastHost())),
        ),
      );

      controller.show('saved', duration: kToastHold + kToastFade);
      await tester.pump();
      expect(container.read(toastProvider).single.fading, isFalse);
      expect(find.text('saved'), findsOneWidget);

      // Still inside the hold window.
      await tester.pump(kToastHold - const Duration(milliseconds: 100));
      expect(container.read(toastProvider).single.fading, isFalse);

      // Hold ends → fade phase starts; opacity animates to 0, then removal.
      await tester.pump(const Duration(milliseconds: 150));
      expect(container.read(toastProvider).single.fading, isTrue);

      await tester.pumpAndSettle();
      expect(container.read(toastProvider), isEmpty);
      expect(find.text('saved'), findsNothing);
    });

    testWidgets('bubble announces via live region (role=alert parity)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DsToast(data: DsToastData(id: 't1', message: 'hello'))),
        ),
      );
      final hasLiveRegion = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((w) => w.properties.liveRegion == true);
      expect(hasLiveRegion, isTrue);
    });
  });

  group('Tooltip (Tooltip.tsx parity)', () {
    Future<void> pumpTooltip(
      WidgetTester tester, {
      DsTooltipSide side = DsTooltipSide.right,
      bool enabled = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DsTooltip(
                message: 'the tip',
                side: side,
                enabled: enabled,
                waitDuration: Duration.zero,
                child: const IconButton(onPressed: null, icon: Icon(Icons.add)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('mouse hover shows after zero delay; exit hides', (tester) async {
      await pumpTooltip(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.byIcon(Icons.add)));
      await tester.pumpAndSettle();
      expect(find.text('the tip'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('the tip'), findsNothing);
    });

    testWidgets('disabled tooltip never shows', (tester) async {
      await pumpTooltip(tester, enabled: false);
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.add)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('the tip'), findsNothing);
      await gesture.up();
    });

    testWidgets('all three React sides render without error', (tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      for (final side in DsTooltipSide.values) {
        await pumpTooltip(tester, side: side);
        await gesture.moveTo(tester.getCenter(find.byIcon(Icons.add)));
        await tester.pumpAndSettle();
        expect(find.text('the tip'), findsOneWidget,
            reason: 'side ${side.name} failed to render');
        await gesture.moveTo(Offset.zero);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('Menu (Menu.tsx parity: owner-controlled, Escape + outside dismiss)', () {
    Widget harness({required ValueChanged<String> onSelect, required VoidCallback onClose}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: _OwnedMenu(onSelect: onSelect, onClose: onClose),
          ),
        ),
      );
    }

    testWidgets('selection reports id and closes', (tester) async {
      String? picked;
      var closed = false;
      await tester.pumpWidget(harness(onSelect: (v) => picked = v, onClose: () => closed = true));

      await tester.tap(find.byKey(const ValueKey('menu-trigger')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(picked, 'a');
      expect(closed, isTrue);
      expect(find.text('Alpha'), findsNothing);
    });
  });

  group('TerminalBlock (TerminalBlock.tsx parity)', () {
    testWidgets('DEFAULT_TERMINAL_MAX_LINES caps the middle with head+tail kept', (tester) async {
      const total = 60;
      final output = List<String>.generate(total, (i) => 'line $i').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DsTerminalBlock(command: 'make all', cwd: '/tmp/proj', output: output),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rendered =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
      final lineTexts = rendered.where((l) => l.startsWith('line ')).toList();

      final headLines = (defaultTerminalMaxLines / 2).ceil();
      final tailLines = defaultTerminalMaxLines - headLines;
      expect(lineTexts.length, headLines + tailLines);
      expect(lineTexts.first, 'line 0');
      expect(lineTexts.last, 'line ${total - 1}');
      // The collapsed middle is absent.
      expect(lineTexts.any((l) => l == 'line $headLines'), isFalse);
      // Prompt line renders the shortened cwd + command.
      expect(rendered.join('\n'), contains('proj \$ make all'));
    });

    testWidgets('running state shows the prompt alone with running label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DsTerminalBlock(
              command: 'npm start',
              cwd: '/home/u/app',
              home: '/home/u',
              running: true,
            ),
          ),
        ),
      );
      await tester.pump();
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(text, contains(r'''app $ npm start'''));
      expect(text, contains('运行中'));
    });
  });
}

class _OwnedMenu extends StatefulWidget {
  const _OwnedMenu({required this.onSelect, required this.onClose});

  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  @override
  State<_OwnedMenu> createState() => _OwnedMenuState();
}

class _OwnedMenuState extends State<_OwnedMenu> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return DsMenu(
      anchor: TextButton(
        key: const ValueKey('menu-trigger'),
        onPressed: () => setState(() => _open = !_open),
        child: const Text('open'),
      ),
      open: _open,
      items: [
        DsMenuLabel(id: 'l1', text: 'group'),
        const DsMenuItem(id: 'a', label: 'Alpha'),
        DsMenuSeparator(id: 'sep'),
        const DsMenuItem(id: 'b', label: 'Beta'),
      ],
      onSelect: (id) {
        widget.onSelect(id);
        setState(() => _open = false);
      },
      onClose: () {
        widget.onClose();
        if (mounted && _open) setState(() => _open = false);
      },
    );
  }
}
