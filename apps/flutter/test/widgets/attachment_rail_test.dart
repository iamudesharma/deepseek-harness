import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/attachment_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentRail', () {
    List<ComposerAttachment> items(int count) => List.generate(
          count,
          (i) => ComposerAttachment.create(
            name: 'image_$i.png',
            path: '/tmp/image_$i.png',
            mimeType: 'image/png',
            size: 10,
          ),
        );

    Widget wrap(Widget child) => MaterialApp(
          theme: ThemeData(extensions: const [DswThemeExtension(aliases: DswTokens.lightAliases)]),
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
        );

    testWidgets('renders one card per attachment', (tester) async {
      final data = items(2);
      await tester.pumpWidget(wrap(AttachmentRail(items: data, onOpen: (_) {}, onRemove: (_) {})));
      // Each rail item hosts an InkWell for the thumbnail (open).
      expect(find.byType(InkWell), findsAtLeastNWidgets(2));
    });

    testWidgets('single-click open invokes onOpen with the attachment', (tester) async {
      final data = items(1);
      ComposerAttachment? opened;
      await tester.pumpWidget(wrap(AttachmentRail(
        items: data,
        onOpen: (a) => opened = a,
        onRemove: (_) {},
      )));
      // First InkWell is the thumbnail; tap it.
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(opened?.name, data.first.name);
    });

    testWidgets('remove button invokes onRemove with the attachment', (tester) async {
      final data = items(1);
      ComposerAttachment? removed;
      await tester.pumpWidget(wrap(AttachmentRail(
        items: data,
        onOpen: (_) {},
        onRemove: (a) => removed = a,
      )));
      await tester.pump();
      // Find the close icon and tap it.
      final close = find.byIcon(Icons.close);
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(removed?.name, data.first.name);
    });

    testWidgets('when onRemove is null, no close button is rendered', (tester) async {
      final data = items(1);
      await tester.pumpWidget(wrap(AttachmentRail(items: data, onOpen: (_) {}, onRemove: null)));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('lightbox shows placeholder when no preview url', (tester) async {
      const att = ComposerAttachment(name: 'doc.png');
      await tester.pumpWidget(wrap(Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AttachmentLightbox(
              attachment: att,
              aliases: DswTokens.lightAliases,
            ),
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('doc.png'), findsWidgets);
    });

    testWidgets('native file thumbnail renders without dart:io crash (conditional seam)', (tester) async {
      // Path-based previewUrl on macOS should go through buildNativeThumbnail seam.
      // On vm (dart:io available) Image.file exists; on web the stub returns a fallback icon.
      // Either path must not throw and must render the rail card.
      final data = [
        ComposerAttachment.create(name: 'native.png', path: '/tmp/native.png', mimeType: 'image/png', size: 10),
      ];
      await tester.pumpWidget(wrap(AttachmentRail(items: data, onOpen: (_) {}, onRemove: (_) {})));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentRail), findsOneWidget);
      // Rail still hosts an InkWell for the thumbnail even when the file is missing.
      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
    });

    testWidgets('http previewUrl renders Image.network', (tester) async {
      final data = [
        const ComposerAttachment(name: 'remote.png', previewUrl: 'http://example.com/a.png', mimeType: 'image/png'),
      ];
      await tester.pumpWidget(wrap(AttachmentRail(items: data, onOpen: (_) {}, onRemove: (_) {})));
      // Image.network is inside the rail item; at least one Image widget exists.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('lightbox with http preview shows network image', (tester) async {
      const att = ComposerAttachment(name: 'remote.png', previewUrl: 'http://example.com/a.png');
      await tester.pumpWidget(wrap(Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AttachmentLightbox(attachment: att, aliases: DswTokens.lightAliases),
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('lightbox with file path uses native seam fallback placeholder', (tester) async {
      final att = ComposerAttachment.create(name: 'native.png', path: '/tmp/native.png', mimeType: 'image/png', size: 10);
      await tester.pumpWidget(wrap(Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AttachmentLightbox(attachment: att, aliases: DswTokens.lightAliases),
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Native lightbox via Image.file with missing file falls back to placeholder containing the name.
      expect(find.text('native.png'), findsWidgets);
    });
  });
}

// Private rail item type re-export would normally be unreachable; we import via the library's exported widget tree.
// Instead locate InkWell count by generic predicate. Exposing _RailItem is not needed; we search by icon.
