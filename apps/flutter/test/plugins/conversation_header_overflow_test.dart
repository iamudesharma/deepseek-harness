import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/slots/hole_outlet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HoleOutlet horizontal lays out actions in a Row',
      (tester) async {
    final registry = SlotRegistry();
    registry.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'conversation.session.header.actions': SlotSpec(
            kind: SlotKind.list,
            scope: SlotScope.session,
          ),
        },
      ),
      (context, props) => const SizedBox.shrink(),
    );
    // Register two header actions.
    registry.register(
      const RegistrationOptions(
        name: 'conversation.session.header.actions',
        id: 'a',
        order: 1,
      ),
      (context, props) => const Text('A'),
    );
    registry.register(
      const RegistrationOptions(
        name: 'conversation.session.header.actions',
        id: 'b',
        order: 2,
      ),
      (context, props) => const Text('B'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 44,
            child: Row(
              children: [
                const Expanded(child: Text('title')),
                HoleOutlet(
                  registry: registry,
                  slotKey: 'conversation.session.header.actions',
                  direction: Axis.horizontal,
                  spacing: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // Horizontal outlet must be a Row, not a Column that overflows 44px.
    final outlet = find.byWidgetPredicate((w) => w is HoleOutlet);
    expect(outlet, findsOneWidget);
    final rowInOutlet = find.descendant(
      of: outlet,
      matching: find.byType(Row),
    );
    expect(rowInOutlet, findsOneWidget);
    final row = tester.widget<Row>(rowInOutlet);
    expect(row.mainAxisSize, MainAxisSize.min);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HoleOutlet vertical defaults to Column', (tester) async {
    final registry = SlotRegistry();
    registry.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'test.list': SlotSpec(
            kind: SlotKind.list,
            scope: SlotScope.session,
          ),
        },
      ),
      (context, props) => const SizedBox.shrink(),
    );
    registry.register(
      const RegistrationOptions(name: 'test.list', id: 'a'),
      (context, props) => const Text('A'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoleOutlet(registry: registry, slotKey: 'test.list'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Column), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
