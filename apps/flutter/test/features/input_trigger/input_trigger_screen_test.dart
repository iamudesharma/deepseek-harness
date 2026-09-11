import 'package:dsh_flutter/src/features/input_trigger/input_trigger_screen.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picking a suggestion shows the inline selection result', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const InputTriggerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected'), findsNothing);

    // The slash demo list renders without a query; tap its first row.
    await tester.tap(find.text('/goal'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected /goal'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected'), findsNothing);
  });
}
