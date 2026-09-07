import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SlotRegistry registry;

  setUp(() => registry = SlotRegistry());

  Future<void> declareAndPump(
    WidgetTester tester, {
    WidgetBuilder? fallback,
  }) async {
    registry.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'app.banner': SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
          'chat.node': SlotSpec(kind: SlotKind.keyed, scope: SlotScope.session),
        },
      ),
      (context, props) => Text('shell:${props.slotKey}'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SlotVersionBuilder(
          registry: registry,
          builder: (context, version) => Column(
            children: [
              Text('v$version'),
              SlotOutlet(
                registry: registry,
                slotKey: 'app.banner',
                fallback: fallback,
              ),
              SlotOutlet(
                registry: registry,
                slotKey: 'missing.slot',
                fallback: fallback,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('outlet renders winners and falls back while empty', (
    tester,
  ) async {
    await declareAndPump(tester);
    expect(find.text('banner-one'), findsNothing);

    final dispose = registry.register(
      const RegistrationOptions(
        name: 'app.banner',
        id: 'one',
        registrant: 'p1',
      ),
      (context, props) => const Text('banner-one'),
    );
    await tester.pump();

    expect(find.text('banner-one'), findsOneWidget);
    dispose();
    await tester.pump();
    expect(find.text('banner-one'), findsNothing);
  });

  testWidgets('ledger mutation rebuilds SlotVersionBuilder', (tester) async {
    await declareAndPump(tester);
    final versionBefore = int.parse(
      tester.widget<Text>(find.textStartingWith('v')).data!.substring(1),
    );

    registry.register(
      const RegistrationOptions(name: 'app.banner', id: 'two'),
      (context, props) => const SizedBox.shrink(),
    );
    await tester.pump();

    final versionAfter = int.parse(
      tester.widget<Text>(find.textStartingWith('v')).data!.substring(1),
    );
    expect(versionAfter, greaterThan(versionBefore));
  });

  testWidgets('keyed outlet passes cellKey through props', (tester) async {
    registry.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'chat.node': const SlotSpec(
            kind: SlotKind.keyed,
            scope: SlotScope.session,
          ),
        },
      ),
      (context, props) => const SizedBox.shrink(),
    );
    String? renderedKey;
    registry.register(
      RegistrationOptions(name: 'chat.node', key: 'tool-call'),
      (BuildContext context, SlotComponentProps props) {
        renderedKey = props.cellKey;
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SlotOutlet(registry: registry, slotKey: 'chat.node'),
      ),
    );
    expect(renderedKey, 'tool-call');
  });

  testWidgets('non-builder components fail with a directed assert', (
    tester,
  ) async {
    registry.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'bad.slot': const SlotSpec(
            kind: SlotKind.single,
            scope: SlotScope.root,
          ),
        },
      ),
      (context, props) => const SizedBox.shrink(),
    );
    registry.register(
      const RegistrationOptions(name: 'bad.slot'),
      'not-a-builder',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SlotOutlet(registry: registry, slotKey: 'bad.slot'),
      ),
    );
    expect(tester.takeException(), isAssertionError);
  });
}

extension on CommonFinders {
  Finder textStartingWith(String prefix) => find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data?.startsWith(prefix) ?? false),
  );
}
