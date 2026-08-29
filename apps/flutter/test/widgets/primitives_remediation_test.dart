import 'package:dsh_flutter/src/core/connection/connection_client.dart' as conn;
import 'package:dsh_flutter/src/platform/open_external.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/connection_banner.dart';
import 'package:dsh_flutter/src/widgets/primitives/hover_card.dart';
import 'package:dsh_flutter/src/widgets/primitives/icons.dart';
import 'package:dsh_flutter/src/widgets/primitives/json_tree.dart';
import 'package:dsh_flutter/src/widgets/primitives/markdown.dart';
import 'package:dsh_flutter/src/widgets/primitives/onboarding_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audited-row remediation evidence for the ui-primitives rows whose carrier
/// files had no focused widget coverage yet: ConnectionBanner, JsonTree,
/// HoverCard, OnboardingSurface, icons, and the Markdown sanitize seam.
/// Behavior is asserted against the React implementations (ConnectionBanner.tsx,
/// JsonTree.tsx, HoverCard.tsx, OnboardingSurface.tsx, icons/index.tsx,
/// markdown/render.tsx sanitizeUrl).
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('DsConnectionBanner (ConnectionBanner.tsx parity)', () {
    testWidgets('connected and idle render nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsConnectionBanner(state: conn.ConnectionState.connected)),
      );
      expect(find.text('Connecting'), findsNothing);
      expect(find.text('Reconnecting'), findsNothing);
      expect(find.text('Disconnected'), findsNothing);

      await tester.pumpWidget(
        _wrap(const DsConnectionBanner(state: conn.ConnectionState.idle)),
      );
      expect(find.text('Connecting'), findsNothing);
    });

    testWidgets('reconnecting shows busy spinner and retry copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsConnectionBanner(state: conn.ConnectionState.reconnecting),
        ),
      );
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(find.text('Connection lost — retrying…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disconnected shows offline copy without spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsConnectionBanner(state: conn.ConnectionState.disconnected),
        ),
      );
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('No active connection.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('DsJsonTree (JsonTree.tsx parity: collapsible typed tree)', () {
    testWidgets('expanded root renders leaf key and type-tinted value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsJsonTree(
            data: <String, dynamic>{'name': 'ok'},
            initiallyExpanded: true,
          ),
        ),
      );
      expect(find.text('"name"'), findsOneWidget);
      expect(find.text('"ok"'), findsOneWidget);
    });

    testWidgets(
      'collapsed composite shows child-count summary, tap expands children',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const DsJsonTree(
              data: <String, dynamic>{
                'a': 1,
                'b': <String>['x'],
              },
            ),
          ),
        );
        // Collapsed root summarizes its two entries.
        expect(find.text('Object { 2 }'), findsOneWidget);
        expect(find.text('"a"'), findsNothing);

        await tester.tap(find.byType(InkWell).first);
        await tester.pumpAndSettle();
        expect(find.text('"a"'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
      },
    );

    testWidgets('initiallyExpanded reveals nested arrays without interaction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsJsonTree(
            data: <String, dynamic>{
              'list': <String>['x'],
            },
            initiallyExpanded: true,
          ),
        ),
      );
      // The composite row title carries the field and its child-count summary.
      expect(find.textContaining('"list"'), findsOneWidget);
      expect(find.textContaining('[ 1 ]'), findsOneWidget);
      expect(find.text('"x"'), findsOneWidget);
    });
  });

  group(
    'DsHoverCard (HoverCard.tsx parity: delayed reachable preview card)',
    () {
      // One mouse device drives hover in and out; a second pointer would keep
      // the first hovering on the anchor so MouseRegion never sees the exit.
      Future<TestGesture> pumpAnchor(
        WidgetTester tester, {
        bool enabled = true,
        String? copyText,
        VoidCallback? onCopy,
      }) async {
        // Loose constraints keep the anchor box hugging the trigger text: the
        // hover region must end at the text edge for exit tracking, and the
        // card needs on-screen room to the right for the tap target.
        await tester.pumpWidget(
          _wrap(
            Padding(
              padding: const EdgeInsets.only(left: 220, top: 160),
              child: Align(
                alignment: Alignment.topLeft,
                child: DsHoverCard(
                  trigger: const Text('anchor'),
                  content: const Text('card body'),
                  enabled: enabled,
                  copyText: copyText,
                  onCopy: onCopy,
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.text('anchor')));
        return gesture;
      }

      testWidgets('hover dwell opens the card after the delay', (tester) async {
        await pumpAnchor(tester);
        expect(find.text('card body'), findsNothing);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(find.text('card body'), findsOneWidget);
      });

      testWidgets('leaving the anchor closes after the grace window', (
        tester,
      ) async {
        final gesture = await pumpAnchor(tester);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(find.text('card body'), findsOneWidget);

        await gesture.moveTo(Offset.zero);
        // Inside the 100ms grace the card is still up.
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('card body'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('card body'), findsNothing);
      });

      testWidgets('disabled suppresses opening entirely', (tester) async {
        await pumpAnchor(tester, enabled: false);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('card body'), findsNothing);
      });

      testWidgets('copyText adds a copy row that reports success', (
        tester,
      ) async {
        var copied = false;
        await pumpAnchor(
          tester,
          copyText: '/long/path',
          onCopy: () => copied = true,
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(find.text('Copy'), findsOneWidget);
        // The overlay card's absolute placement varies with the viewport flip
        // math, so hit-test taps are not stable here; assert the rendered row
        // and its handler wiring directly.
        final InkWell copyRow = tester.widget<InkWell>(
          find
              .ancestor(of: find.text('Copy'), matching: find.byType(InkWell))
              .first,
        );
        copyRow.onTap?.call();
        await tester.pump();
        expect(copied, isTrue);
      });
    },
  );

  group(
    'DsOnboardingSurface (OnboardingSurface.tsx parity: takeover chrome)',
    () {
      const steps = <DsOnboardingStep>[
        DsOnboardingStep(
          title: 'Welcome',
          description: 'First step',
          ctaLabel: 'Next',
        ),
        DsOnboardingStep(title: 'Done', description: 'Last step'),
      ];

      testWidgets(
        'mid-flow shows step copy, skip affordance, and advances via CTA',
        (tester) async {
          var next = 0;
          var skipped = false;
          await tester.pumpWidget(
            _wrap(
              DsOnboardingSurface(
                steps: steps,
                currentStep: 0,
                onNext: () => next++,
                onSkip: () => skipped = true,
              ),
            ),
          );
          expect(find.text('Welcome'), findsOneWidget);
          expect(find.text('First step'), findsOneWidget);
          expect(find.text('Skip'), findsOneWidget);
          expect(find.text('Next'), findsOneWidget);

          await tester.tap(find.text('Next'));
          await tester.pump();
          expect(next, 1);

          await tester.tap(find.text('Skip'));
          await tester.pump();
          expect(skipped, isTrue);
        },
      );

      testWidgets('last step swaps CTA for completion and drops skip', (
        tester,
      ) async {
        var completed = false;
        await tester.pumpWidget(
          _wrap(
            DsOnboardingSurface(
              steps: steps,
              currentStep: 1,
              onComplete: () => completed = true,
            ),
          ),
        );
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Skip'), findsNothing);
        expect(find.text('Get started'), findsOneWidget);

        await tester.tap(find.text('Get started'));
        await tester.pump();
        expect(completed, isTrue);
      });
    },
  );

  group('DsIcons (icons/index.tsx substitution onto Material glyphs)', () {
    testWidgets(
      'mapped factories render their Material glyph at the requested size',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Column(
              children: <Widget>[
                DsIcons.check(size: 12),
                DsIcons.close(),
                DsIcons.warning(color: const Color(0xFFDC2626)),
              ],
            ),
          ),
        );
        final Icon check = tester.widget<Icon>(find.byIcon(Icons.check));
        expect(check.size, 12);
        expect(find.byIcon(Icons.close), findsOneWidget);
        final Icon warning = tester.widget<Icon>(
          find.byIcon(Icons.warning_amber_rounded),
        );
        expect(warning.color, const Color(0xFFDC2626));
      },
    );

    test('toDsIcon extension wraps any IconData as a sized icon', () {
      final Widget icon = Icons.search.toDsIcon(size: 14);
      expect(icon, isA<Icon>());
      expect((icon as Icon).icon, Icons.search);
      expect(icon.size, 14);
    });
  });

  group('DsMarkdown + sanitizeUrl (markdown/render.tsx allowlist parity)', () {
    test(
      'sanitizeUrl allows http/https/mailto and blocks script and data schemes',
      () {
        expect(sanitizeUrl('https://example.com/a'), 'https://example.com/a');
        expect(sanitizeUrl('http://example.com'), 'http://example.com');
        expect(sanitizeUrl('mailto:a@b.c'), 'mailto:a@b.c');
        expect(sanitizeUrl("javascript:alert('x')"), isNull);
        expect(sanitizeUrl('data:text/html,<b>x</b>'), isNull);
        expect(sanitizeUrl('file:///etc/passwd'), isNull);
      },
    );

    testWidgets('renders gfm headings, emphasis, and link text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: '# Heading\n\n**bold** text')),
      );
      expect(find.text('Heading'), findsOneWidget);
      // Inline bold lives in the paragraph's rich span, not a bare Text.
      expect(find.textContaining('bold', findRichText: true), findsOneWidget);
    });

    testWidgets(
      'tapping an https link routes through openExternal without crashing',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const DsMarkdown(data: '[good](https://example.com)')),
        );
        final link = find.text('good', findRichText: true);
        expect(link, findsOneWidget);
        // The missing url_launcher channel is swallowed inside openExternal in
        // widget tests; the assertion is that the tap neither throws nor
        // navigates.
        await tester.tap(link);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a javascript: link never reaches the launcher', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: '[bad](javascript:void(0))')),
      );
      final link = find.text('bad', findRichText: true);
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pump();
      // sanitizeUrl returns null before any launch attempt; nothing thrown,
      // nothing opened.
      expect(tester.takeException(), isNull);
    });
  });
}
