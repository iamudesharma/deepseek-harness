import 'dart:typed_data';

import 'package:dsh_flutter/src/plugins/attachment/attachment_limits.dart'
    show imageLimitsProvider, imageSizeText;
import 'package:dsh_flutter/src/plugins/attachment/ui/document_drop_scope.dart';
import 'package:dsh_flutter/src/plugins/attachment/ui/drop_overlay.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/platform/drag_drop.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/composer.dart'
    show intakeComposerImages;
import 'package:desktop_drop/desktop_drop.dart' show DropTarget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DroppedFile file(
  String name, {
  String mime = 'image/png',
  int size = 10,
  String? path,
  Uint8List? bytes,
}) => DroppedFile(
  name: name,
  mimeType: mime,
  size: size,
  path: path,
  bytes: bytes,
);

ImageLimits limits({int count = 2, int perFile = 100, int total = 150}) =>
    ImageLimits(
      mediaTypes: const ['image/png', 'image/jpeg'],
      maxImagesPerMessage: count,
      maxImageBytes: perFile,
      maxMessageImageBytes: total,
    );

void main() {
  group('DragDropController', () {
    test('depth counter shows overlay only while a drag is active', () {
      final c = DragDropController(onAddImages: (_) => null);
      expect(c.dragActive, isFalse);
      c.dragEntered();
      expect(c.dragActive, isTrue);
      c.dragEntered();
      c.dragLeft(); // nested region leave — still active
      expect(c.dragActive, isTrue);
      c.dragLeft();
      expect(c.dragActive, isFalse);
      // Clamp: extra leaves never go negative.
      c.dragLeft();
      expect(c.dragActive, isFalse);
      c.dispose();
    });

    test('reset clears any depth', () {
      final c = DragDropController(onAddImages: (_) => null);
      c.dragEntered();
      c.dragEntered();
      c.reset();
      expect(c.dragActive, isFalse);
      c.dispose();
    });

    test('blocked gate refuses drops without forwarding files', () {
      var forwarded = 0;
      String? reject;
      final c = DragDropController(
        onAddImages: (files) {
          forwarded += files.length;
          return null;
        },
        onRejected: (m) => reject = m,
      );
      c.configure(canAcceptDrop: false);
      c.dropped([file('a.png')]);
      expect(forwarded, 0);
      expect(reject, isNull); // blocked drop is silent, like React
      c.dispose();
    });

    test('accepted gate forwards the batch and resets depth', () {
      var forwarded = <String>[];
      final c = DragDropController(
        onAddImages: (files) {
          forwarded = files.map((f) => f.name).toList();
          return null;
        },
      );
      c.configure(canAcceptDrop: true);
      c.dragEntered();
      c.dropped([file('a.png'), file('b.png')]);
      expect(forwarded, ['a.png', 'b.png']);
      expect(c.dragActive, isFalse);
      c.dispose();
    });

    test('pre-check order: format precedes count and size', () {
      // A batch with a non-image defers to the authoritative intake even
      // when it also exceeds every limit.
      String? rejection;
      var forwarded = false;
      final c = DragDropController(
        onAddImages: (files) {
          forwarded = true;
          return 'authoritative rejection';
        },
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits());
      c.stagedCount = 1; // one more would exceed count=2
      c.dropped([
        file('huge.txt', mime: 'text/plain', size: 999),
        file('b.png', size: 999),
      ]);
      expect(forwarded, isTrue); // deferred to authoritative intake
      expect(rejection, 'authoritative rejection');
      c.dispose();
    });

    test('count limit counts existing drafts plus the batch', () {
      String? rejection;
      var forwarded = false;
      final c = DragDropController(
        onAddImages: (_) {
          forwarded = true;
          return null;
        },
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits(count: 2));
      c.stagedCount = 1;
      c.dropped([file('a.png'), file('b.png')]);
      expect(forwarded, isFalse);
      expect(rejection, contains('up to 2 images'));
      c.dispose();
    });

    test('per-file size limit rejects an oversized single file', () {
      String? rejection;
      final c = DragDropController(
        onAddImages: (_) => null,
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits(perFile: 100));
      c.dropped([file('ok.png'), file('big.png', size: 101)]);
      expect(rejection, contains('smaller than 100B'));
      c.dispose();
    });

    test('total batch size limit rejects an oversized combined batch', () {
      String? rejection;
      final c = DragDropController(
        onAddImages: (_) => null,
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits(total: 150));
      c.dropped([file('a.png', size: 80), file('b.png', size: 80)]);
      expect(rejection, contains('total less than'));
      c.dispose();
    });

    test('total limit includes staged bytes (mirrors InputBar total)', () {
      String? rejection;
      final c = DragDropController(
        onAddImages: (_) => null,
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits(total: 150));
      c.stagedCount = 1;
      c.stagedTotalBytes = 80; // one staged image already
      c.dropped([file('b.png', size: 80)]);
      expect(rejection, contains('total less than'));
      c.dispose();
    });

    test('total limit passes when staged+incoming stays within budget', () {
      String? rejection;
      var forwarded = false;
      final c = DragDropController(
        onAddImages: (_) {
          forwarded = true;
          return null;
        },
        onRejected: (m) => rejection = m,
      );
      c.configure(canAcceptDrop: true, limits: limits(total: 300));
      c.stagedTotalBytes = 80;
      c.dropped([file('b.png', size: 80)]);
      expect(rejection, isNull);
      expect(forwarded, isTrue);
      c.dispose();
    });

    test('null limits defer entirely to the authoritative intake', () {
      var forwarded = false;
      final c = DragDropController(
        onAddImages: (files) {
          forwarded = files.every((f) => f.mimeType == 'application/zip');
          return null;
        },
      );
      c.configure(canAcceptDrop: true);
      c.dropped([file('x.zip', mime: 'application/zip', size: 10 << 20)]);
      expect(forwarded, isTrue);
      c.dispose();
    });
  });

  group('intakeComposerImages', () {
    test('stages dropped files as draft attachments with generated ids', () {
      final staged = <ComposerAttachment>[];
      final rejected = intakeComposerImages(
        staged: const [],
        limits: limits(),
        add: staged.addAll,
        files: [file('shot.png', path: '/tmp/shot.png', size: 12)],
      );
      expect(rejected, isNull);
      expect(staged.single.name, 'shot.png');
      expect(staged.single.path, '/tmp/shot.png');
      expect(staged.single.size, 12);
      expect(staged.single.id, isNotEmpty);
      expect(staged.single.previewUrl, '/tmp/shot.png');
      // ids are stable and unique per file
      final second = <ComposerAttachment>[];
      intakeComposerImages(
        staged: const [],
        limits: limits(),
        add: second.addAll,
        files: [file('shot2.png', path: '/tmp/shot2.png', size: 12)],
      );
      expect(second.single.id, isNot(staged.single.id));
    });

    test('rejects a non-image batch before touching limits', () {
      final staged = <ComposerAttachment>[];
      final rejected = intakeComposerImages(
        staged: const [],
        limits: limits(),
        add: staged.addAll,
        files: [file('notes.txt', mime: 'text/plain')],
      );
      expect(rejected, 'Only image files can be attached');
      expect(staged, isEmpty);
    });

    test(
      'total limit includes staged attachments when batch would overflow',
      () {
        final staged = [const ComposerAttachment(name: 'a.png', size: 80)];
        final fresh = <ComposerAttachment>[];
        final rejected = intakeComposerImages(
          staged: staged,
          limits: limits(total: 150),
          add: fresh.addAll,
          files: [file('b.png', size: 80)],
        );
        expect(rejected, contains('total less than'));
        expect(fresh, isEmpty);
      },
    );

    test('staged+incoming within total budget stages the batch', () {
      final staged = [const ComposerAttachment(name: 'a.png', size: 80)];
      final fresh = <ComposerAttachment>[];
      final rejected = intakeComposerImages(
        staged: staged,
        limits: limits(total: 300),
        add: fresh.addAll,
        files: [file('b.png', size: 80)],
      );
      expect(rejected, isNull);
      expect(fresh.single.name, 'b.png');
    });
  });

  group('ComposerAttachment unified model', () {
    test('create generates unique ids for distinct drops', () {
      final a = ComposerAttachment.create(
        name: 'a.png',
        path: '/tmp/a.png',
        size: 10,
        mimeType: 'image/png',
      );
      final b = ComposerAttachment.create(
        name: 'a.png',
        path: '/tmp/a.png',
        size: 10,
        mimeType: 'image/png',
      );
      expect(a.id, isNotEmpty);
      expect(b.id, isNotEmpty);
      expect(a.id, isNot(b.id));
      expect(a, isNot(b));
    });

    test('legacy const fixtures dedupe by name+path when ids empty', () {
      const a = ComposerAttachment(name: 'file.txt', path: '/tmp/file.txt');
      const b = ComposerAttachment(name: 'file.txt', path: '/tmp/file.txt');
      expect(a, equals(b));
    });

    test('real attachments dedupe by id even when name/path coincide', () {
      final a = ComposerAttachment.create(
        name: 'file.txt',
        path: '/tmp/file.txt',
      );
      final b = ComposerAttachment(
        id: a.id,
        name: 'file.txt',
        path: '/tmp/file.txt',
      );
      expect(a, equals(b));
    });
  });

  group('DropOverlay', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool disabled,
      String? limitsText,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DropOverlay(disabled: disabled, limitsText: limitsText),
          ),
        ),
      );
    }

    testWidgets('enabled state invites the drop and shows limits', (
      tester,
    ) async {
      await pump(tester, disabled: false, limitsText: 'Up to 5 images');
      expect(find.text('Drop images to attach'), findsOneWidget);
      expect(find.text('Up to 5 images'), findsOneWidget);
    });

    testWidgets('disabled state names the block and hides limits', (
      tester,
    ) async {
      await pump(tester, disabled: true, limitsText: 'Up to 5 images');
      expect(
        find.text('Image uploads are unavailable right now'),
        findsOneWidget,
      );
      expect(find.text('Up to 5 images'), findsNothing);
    });

    testWidgets('overlay ignores pointers so drags pass through', (
      tester,
    ) async {
      await pump(tester, disabled: false);
      final finder = find.descendant(
        of: find.byType(DropOverlay),
        matching: find.byType(IgnorePointer),
      );
      expect(finder, findsOneWidget);
      expect(tester.widget<IgnorePointer>(finder).ignoring, isTrue);
    });
  });

  group('ImageLimits deduplication', () {
    test('platform imageSizeText and attachment_limits re-export match', () {
      expect(imageSizeText(500), '500B');
      expect(imageSizeText(2048), '2KB');
      expect(imageSizeText(2 * 1024 * 1024), '2MB');
    });

    test('DroppedFile bytes round-trip through intakeComposerImages', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final staged = <ComposerAttachment>[];
      final rejected = intakeComposerImages(
        staged: const [],
        limits: limits(),
        add: staged.addAll,
        files: [file('shot.png', path: '/tmp/shot.png', size: 4, bytes: bytes)],
      );
      expect(rejected, isNull);
      expect(staged.single.bytes, bytes);
      expect(staged.single.previewUrl, '/tmp/shot.png');
    });
  });

  group('DocumentDropScope enabled / modal guard', () {
    testWidgets('shows DropTarget when enabled and no modal', (tester) async {
      final controller = DragDropController(onAddImages: (_) => null);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentDropScope(
              controller: controller,
              onAddImages: (_) => null,
              child: const Text('content'),
            ),
          ),
        ),
      );
      expect(find.byType(DropTarget), findsOneWidget);
    });

    testWidgets('hides DropTarget when enabled=false', (tester) async {
      final controller = DragDropController(onAddImages: (_) => null);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentDropScope(
              controller: controller,
              enabled: false,
              onAddImages: (_) => null,
              child: const Text('content'),
            ),
          ),
        ),
      );
      expect(find.byType(DropTarget), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('hides DropTarget when modal route is on top', (tester) async {
      final controller = DragDropController(onAddImages: (_) => null);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentDropScope(
              controller: controller,
              onAddImages: (_) => null,
              child: const Text('content'),
            ),
          ),
        ),
      );
      expect(find.byType(DropTarget), findsOneWidget);
      // Push a dialog route — underlying DocumentDropScope's ModalRoute becomes non-current.
      showDialog<void>(
        context: tester.element(find.text('content')),
        builder: (_) => const Dialog(child: Text('modal')),
      );
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);
      // The DropTarget under the modal should be gone (effectiveEnabled false).
      expect(find.byType(DropTarget), findsNothing);
    });
  });
}
