import 'dart:typed_data';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake that succeeds without touching the network — exercises the live
/// `ConnectionClient.sendMessage` path while keeping the test deterministic.
class _FakeSuccessClient extends ConnectionClient {
  _FakeSuccessClient() : super(baseUrl: 'http://fake');
  @override
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _FakeFailureClient extends ConnectionClient {
  _FakeFailureClient() : super(baseUrl: 'http://fake');
  @override
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    throw Exception('host unreachable');
  }
}

ProviderContainer _containerWithFake({ConnectionClient? client}) {
  final fake = client ?? _FakeSuccessClient();
  return ProviderContainer(
    overrides: [connectionClientProvider.overrideWithValue(fake)],
  );
}

void main() {
  group('ComposerState helpers', () {
    test('initial state is empty and cannot submit', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(composerControllerProvider('s1'));
      expect(state.text, isEmpty);
      expect(state.attachments, isEmpty);
      expect(state.canSubmit, isFalse);
      expect(state.isSending, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith preserves values', () {
      const a = ComposerState(text: 'hi', attachments: [], isSending: false);
      final b = a.copyWith(text: 'hello');
      expect(b.text, 'hello');
      expect(a.text, 'hi');
      final cleared = b.copyWith(clearError: true, error: 'should be ignored');
      expect(cleared.error, isNull);
    });
  });

  group('ComposerController draft', () {
    test('setText updates draft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      expect(container.read(composerControllerProvider('s1')).text, 'hello');
    });

    test('setText no-op when same value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      final before = container.read(composerControllerProvider('s1'));
      notifier.setText('hello');
      expect(container.read(composerControllerProvider('s1')), same(before));
    });

    test('setText clears error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setError('oops');
      expect(container.read(composerControllerProvider('s1')).error, 'oops');
      notifier.setText('new draft');
      expect(container.read(composerControllerProvider('s1')).error, isNull);
    });

    test('setModel updates model', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setModel('deepseek-chat');
      expect(
        container.read(composerControllerProvider('s1')).selectedModel,
        'deepseek-chat',
      );
      notifier.setModel(null);
      expect(
        container.read(composerControllerProvider('s1')).selectedModel,
        isNull,
      );
    });

    test('setModel no-op when same', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setModel('deepseek-chat');
      final before = container.read(composerControllerProvider('s1'));
      notifier.setModel('deepseek-chat');
      expect(container.read(composerControllerProvider('s1')), same(before));
    });

    test('setModel clears error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setError('err');
      notifier.setModel('deepseek-chat');
      expect(container.read(composerControllerProvider('s1')).error, isNull);
    });
  });

  group('ComposerController attachments', () {
    test('addAttachments dedupes by name+path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      const a = ComposerAttachment(name: 'file.txt', path: '/tmp/file.txt');
      const b = ComposerAttachment(name: 'file.txt', path: '/tmp/file.txt');
      notifier.addAttachments([a]);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        1,
      );
      notifier.addAttachments([b]);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        1,
      );
    });

    test('addAttachments with empty does nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      final before = container.read(composerControllerProvider('s1'));
      notifier.addAttachments([]);
      expect(container.read(composerControllerProvider('s1')), same(before));
    });

    test('addAttachments appends multiple distinct', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.addAttachments(const [
        ComposerAttachment(name: 'a.txt'),
        ComposerAttachment(name: 'b.txt'),
      ]);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        2,
      );
    });

    test('removeAttachmentAt removes by index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.addAttachments(const [
        ComposerAttachment(name: 'a.txt'),
        ComposerAttachment(name: 'b.txt'),
      ]);
      notifier.removeAttachmentAt(0);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        1,
      );
      expect(
        container.read(composerControllerProvider('s1')).attachments.first.name,
        'b.txt',
      );
    });

    test('removeAttachmentAt out of bounds no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.addAttachments(const [ComposerAttachment(name: 'a.txt')]);
      notifier.removeAttachmentAt(5);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        1,
      );
      notifier.removeAttachmentAt(-1);
      expect(
        container.read(composerControllerProvider('s1')).attachments.length,
        1,
      );
    });

    test('clearAttachments empties', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.addAttachments(const [ComposerAttachment(name: 'a.txt')]);
      notifier.clearAttachments();
      expect(
        container.read(composerControllerProvider('s1')).attachments,
        isEmpty,
      );
    });

    test('clearAttachments no-op when empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      final before = container.read(composerControllerProvider('s1'));
      notifier.clearAttachments();
      expect(container.read(composerControllerProvider('s1')), same(before));
    });
  });

  group('ComposerController canSubmit', () {
    test('false when empty text and no attachments', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(composerControllerProvider('s1')).canSubmit,
        isFalse,
      );
    });

    test('true when text non-empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(composerControllerProvider('s1').notifier)
          .setText('hello');
      expect(
        container.read(composerControllerProvider('s1')).canSubmit,
        isTrue,
      );
    });

    test('false when only whitespace', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(composerControllerProvider('s1').notifier).setText('   ');
      expect(
        container.read(composerControllerProvider('s1')).canSubmit,
        isFalse,
      );
    });

    test('true when attachment present even with empty text', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.addAttachments(const [ComposerAttachment(name: 'file.txt')]);
      expect(
        container.read(composerControllerProvider('s1')).canSubmit,
        isTrue,
      );
    });

    test('false when isSending even with text', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      // kick off submit but don't await
      final future = notifier.submit();
      expect(
        container.read(composerControllerProvider('s1')).canSubmit,
        isFalse,
      );
      expect(
        container.read(composerControllerProvider('s1')).isSending,
        isTrue,
      );
      await future;
    });
  });

  group('ComposerController submit', () {
    test('no-op when cannot submit', () async {
      final container = _containerWithFake();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      await notifier.submit();
      expect(
        container.read(composerControllerProvider('s1')).isSending,
        isFalse,
      );
      expect(container.read(composerControllerProvider('s1')).text, isEmpty);
    });

    test(
      'clears draft and attachments after host success, keeps model',
      () async {
        final container = _containerWithFake();
        addTearDown(container.dispose);
        final notifier = container.read(
          composerControllerProvider('s1').notifier,
        );
        notifier.setText('hello');
        notifier.setModel('deepseek-chat');
        notifier.addAttachments([
          ComposerAttachment(
            name: 'a.png',
            mimeType: 'image/png',
            size: 3,
            bytes: Uint8List.fromList([1, 2, 3]),
            previewUrl: '/tmp/a.png',
          ),
        ]);
        await notifier.submit();
        final after = container.read(composerControllerProvider('s1'));
        expect(after.text, isEmpty);
        expect(after.attachments, isEmpty);
        expect(after.selectedModel, 'deepseek-chat');
        expect(after.isSending, isFalse);
        expect(after.error, isNull);
      },
    );

    test('toggles isSending during host call', () async {
      final container = _containerWithFake();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      final future = notifier.submit();
      expect(
        container.read(composerControllerProvider('s1')).isSending,
        isTrue,
      );
      await future;
      expect(
        container.read(composerControllerProvider('s1')).isSending,
        isFalse,
      );
    });

    test('clears error on submit and keeps draft cleared on success', () async {
      final container = _containerWithFake();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      notifier.setError('previous error');
      await notifier.submit();
      expect(container.read(composerControllerProvider('s1')).error, isNull);
      expect(container.read(composerControllerProvider('s1')).text, isEmpty);
    });

    test('sets error and preserves draft on host failure', () async {
      final container = _containerWithFake(client: _FakeFailureClient());
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setText('hello');
      await notifier.submit();
      final after = container.read(composerControllerProvider('s1'));
      expect(after.isSending, isFalse);
      expect(after.error, contains('host unreachable'));
      expect(after.text, 'hello');
    });

    test('setError and clearError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      notifier.setError('boom');
      expect(container.read(composerControllerProvider('s1')).error, 'boom');
      expect(
        container.read(composerControllerProvider('s1')).isSending,
        isFalse,
      );
      notifier.clearError();
      expect(container.read(composerControllerProvider('s1')).error, isNull);
    });

    test('clearError no-op when no error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      final before = container.read(composerControllerProvider('s1'));
      notifier.clearError();
      expect(container.read(composerControllerProvider('s1')), same(before));
    });

    test('session scoping: different ids have independent drafts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(composerControllerProvider('s1').notifier)
          .setText('for s1');
      container
          .read(composerControllerProvider('s2').notifier)
          .setText('for s2');
      expect(container.read(composerControllerProvider('s1')).text, 'for s1');
      expect(container.read(composerControllerProvider('s2')).text, 'for s2');
    });
  });

  group('ComposerAttachment serializeDraftImages', () {
    test('encodes png bytes to base64 image part', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final att = ComposerAttachment(
        id: DraftAttachmentId('a1'),
        name: 'shot.png',
        mimeType: 'image/png',
        size: bytes.length,
        bytes: bytes,
      );
      final parts = await ComposerController.serializeDraftImages([att]);
      expect(parts.length, 1);
      expect(parts.first['type'], 'image');
      expect(parts.first['mediaType'], 'image/png');
      expect(parts.first['name'], 'shot.png');
      // 1,2,3,4 -> base64 AQIDBA==
      expect(parts.first['data'], 'AQIDBA==');
    });

    test('rejects unsupported media type', () async {
      const att = ComposerAttachment(
        id: DraftAttachmentId('a1'),
        name: 'doc.pdf',
        mimeType: 'application/pdf',
        size: 10,
        bytes: null,
      );
      await expectLater(
        ComposerController.serializeDraftImages([att]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unsupported image media type'),
          ),
        ),
      );
    });

    test('rejects when bytes missing and file cannot be read', () async {
      const att = ComposerAttachment(
        id: DraftAttachmentId('a1'),
        name: 'shot.png',
        mimeType: 'image/png',
        size: 10,
        path: '/nonexistent/shot.png',
        bytes: null,
      );
      await expectLater(
        ComposerController.serializeDraftImages([att]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('missing image data'),
          ),
        ),
      );
    });
  });

  group('ComposerController submit with images', () {
    test('sends image parts plus text via ConnectionClient', () async {
      List<Map<String, dynamic>>? sentImages;
      String? sentText;
      final fake = _FakeCaptureClient(
        onSend: (images, text) {
          sentImages = images;
          sentText = text;
        },
      );
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      final bytes = Uint8List.fromList([10, 20, 30]);
      notifier.addAttachments([
        ComposerAttachment(
          id: DraftAttachmentId('a1'),
          name: 'a.png',
          mimeType: 'image/png',
          size: bytes.length,
          bytes: bytes,
        ),
      ]);
      notifier.setText('hello');
      await notifier.submit();
      expect(sentText, 'hello');
      expect(sentImages, isNotNull);
      expect(sentImages!.length, 1);
      expect(sentImages!.first['mediaType'], 'image/png');
      expect(sentImages!.first['data'], isNotEmpty);
      // Draft cleared on success
      expect(
        container.read(composerControllerProvider('s1')).attachments,
        isEmpty,
      );
      expect(container.read(composerControllerProvider('s1')).text, isEmpty);
    });

    test(
      'submit with image serialization failure keeps draft and sets error',
      () async {
        final fake = _FakeSuccessClient();
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          composerControllerProvider('s1').notifier,
        );
        // unsupported type -> serialize failure before host call
        notifier.addAttachments(const [
          ComposerAttachment(
            id: DraftAttachmentId('a1'),
            name: 'bad.pdf',
            mimeType: 'application/pdf',
            size: 10,
          ),
        ]);
        notifier.setText('hello');
        await notifier.submit();
        final after = container.read(composerControllerProvider('s1'));
        expect(after.error, contains('unsupported image media type'));
        expect(after.attachments, isNotEmpty);
        expect(after.text, 'hello');
        expect(after.isSending, isFalse);
      },
    );

    test('submit with images and empty text sends only images', () async {
      List<Map<String, dynamic>>? sentImages;
      String? sentText;
      final fake = _FakeCaptureClient(
        onSend: (images, text) {
          sentImages = images;
          sentText = text;
        },
      );
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        composerControllerProvider('s1').notifier,
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      notifier.addAttachments([
        ComposerAttachment(
          id: DraftAttachmentId('a1'),
          name: 'a.png',
          mimeType: 'image/png',
          size: 3,
          bytes: bytes,
        ),
      ]);
      // no text
      await notifier.submit();
      expect(sentText, '');
      expect(sentImages!.length, 1);
    });
  });
}

class _FakeCaptureClient extends ConnectionClient {
  _FakeCaptureClient({required this.onSend}) : super(baseUrl: 'http://fake');
  final void Function(List<Map<String, dynamic>> images, String text) onSend;
  @override
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    onSend(images, content);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
