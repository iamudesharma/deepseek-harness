import 'package:dsh_flutter/src/platform/clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final setDataCalls = <String?>[];

  setUp(() {
    setDataCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<Object?, Object?>?;
            setDataCalls.add(data?['text'] as String?);
            return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('ClipboardHelper.copy', () {
    testWidgets('writes text through the platform channel', (tester) async {
      final ok = await ClipboardHelper.copy('hello harness');
      expect(ok, isTrue);
      expect(setDataCalls, ['hello harness']);
    });

    testWidgets('empty input returns false without touching the channel', (
      tester,
    ) async {
      final ok = await ClipboardHelper.copy('');
      expect(ok, isFalse);
      expect(setDataCalls, isEmpty);
    });

    testWidgets('platform denial reports failure without throwing', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              throw PlatformException(code: 'denied');
            return null;
          });
      final ok = await ClipboardHelper.copy('blocked');
      expect(ok, isFalse);
    });
  });

  group('copyWithFeedback', () {
    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
    }

    testWidgets('success shows the floating copied SnackBar', (tester) async {
      await pumpHost(tester);
      final ok = await ClipboardHelper.copyWithFeedback(
        tester.element(find.byType(Scaffold)),
        'path/to/file',
      );
      await tester.pump();
      expect(ok, isTrue);
      expect(find.text('Copied to clipboard'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
        SnackBarBehavior.floating,
      );
    });

    testWidgets('success message override wins when provided', (tester) async {
      await pumpHost(tester);
      await ClipboardHelper.copyWithFeedback(
        tester.element(find.byType(Scaffold)),
        'x',
        successMessage: 'Path copied',
      );
      await tester.pump();
      expect(find.text('Path copied'), findsOneWidget);
    });

    testWidgets('failure shows platform-tuned error copy', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              throw PlatformException(code: 'fail');
            return null;
          });
      await pumpHost(tester);
      final ok = await ClipboardHelper.copyWithFeedback(
        tester.element(find.byType(Scaffold)),
        'x',
      );
      await tester.pump();
      // Reset before the test body ends — the binding asserts foundation
      // debug vars are unset at test end, ahead of tearDown.
      debugDefaultTargetPlatformOverride = null;
      expect(ok, isFalse);
      expect(find.text('Copy failed — pasteboard unavailable'), findsOneWidget);
    });
  });

  testWidgets('top-level convenience delegates to the helper', (tester) async {
    final ok = await copyToClipboard('top-level');
    expect(ok, isTrue);
    expect(setDataCalls, ['top-level']);
  });
}
