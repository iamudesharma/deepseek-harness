import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_controller.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_plugin.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_provider.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/ui/message_feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One recorded remote call, field-asserted instead of string-matched.
class _Call {
  _Call.put(this.messageId, this.rating, this.note, this.ifVersion)
    : op = 'put';
  _Call.delete(this.messageId, this.ifVersion)
    : op = 'delete',
      rating = null,
      note = null;

  final String op;
  final String messageId;
  final FeedbackRatingValue? rating;
  final Object? note;
  final Object? ifVersion;
}

class _FakeRemote implements MessageFeedbackRemote {
  final List<MessageFeedbackItem> stored = [];
  final List<_Call> calls = [];
  String? failListWith;

  /// Simulates a concurrent writer winning the CAS race on the next mutation.
  bool forceVersionConflict = false;

  @override
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  }) async {
    if (failListWith != null) return ReplyError(failListWith!);
    return ReplyOk(List.of(stored));
  }

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> put({
    required String sessionId,
    required String messageId,
    required FeedbackRatingValue rating,
    String? note,
    required int? ifVersion,
  }) async {
    calls.add(_Call.put(messageId, rating, note, ifVersion));
    final observed = _byId(messageId);
    if (forceVersionConflict ||
        (observed != null && observed.version != ifVersion)) {
      // Host CAS failure carries the authoritative row back.
      return ReplyError('version-conflict', current: observed);
    }
    final item = MessageFeedbackItem(
      messageId: messageId,
      rating: rating,
      note: note,
      version: (observed?.version ?? 0) + 1,
    );
    stored.removeWhere((i) => i.messageId == messageId);
    stored.add(item);
    return ReplyOk(item);
  }

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> delete({
    required String sessionId,
    required String messageId,
    required int ifVersion,
  }) async {
    calls.add(_Call.delete(messageId, ifVersion));
    final observed = _byId(messageId);
    if (observed == null) return const ReplyOk<MessageFeedbackItem?>(null);
    if (observed.version != ifVersion) {
      return ReplyError('version-conflict', current: observed);
    }
    stored.removeWhere((i) => i.messageId == messageId);
    return const ReplyOk<MessageFeedbackItem?>(null);
  }

  MessageFeedbackItem? _byId(String messageId) {
    for (final item in stored) {
      if (item.messageId == messageId) return item;
    }
    return null;
  }
}

void main() {
  test('activation provides the per-session controller service', () async {
    final host = PluginHost();
    host.provide('slots', host.slots);
    host.register(MessageFeedbackPlugin());
    addTearDown(host.deactivateAll);

    await host.activateAll();

    final controllers = host.service<MessageFeedbackControllers>(
      'messageFeedback',
    );
    expect(controllers, isNotNull);
    final controller = controllers!.forSession('s-1');
    expect(controller.view.status, MessageFeedbackStatus.cold);
    expect(identical(controllers.forSession('s-1'), controller), isTrue);
  });

  test('toggle seeds from the list read, then replaces against the observed version', () async {
    final remote = _FakeRemote();
    remote.stored.add(
      const MessageFeedbackItem(
        messageId: 'm1',
        rating: FeedbackRatingValue.positive,
        version: 3,
      ),
    );
    final controller = MessageFeedbackController(remote, 's-1');

    final result = await controller.toggle('m1', FeedbackRatingValue.negative);

    expect(result.ok, isTrue);
    expect(remote.calls, hasLength(1));
    final put = remote.calls.single;
    expect(put.op, 'put');
    expect(put.rating, FeedbackRatingValue.negative);
    expect(put.ifVersion, 3);
    expect(controller.view.status, MessageFeedbackStatus.ready);
    expect(controller.view.items['m1']!.rating, FeedbackRatingValue.negative);
    expect(controller.view.items['m1']!.version, 4);
  });

  test('toggle retracts when the committed rating already matches', () async {
    final remote = _FakeRemote();
    remote.stored.add(
      const MessageFeedbackItem(
        messageId: 'm2',
        rating: FeedbackRatingValue.positive,
        version: 1,
      ),
    );
    final controller = MessageFeedbackController(remote, 's-1');

    await controller.toggle('m2', FeedbackRatingValue.positive);

    expect(remote.calls.single.op, 'delete');
    expect(remote.calls.single.ifVersion, 1);
    expect(controller.view.items.containsKey('m2'), isFalse);
  });

  test(
    'a version-conflict reply commits the authoritative row and reports',
    () async {
      final remote = _FakeRemote();
      remote.stored.add(
        const MessageFeedbackItem(
          messageId: 'm3',
          rating: FeedbackRatingValue.negative,
          version: 7,
        ),
      );
      // Another client committed between our list read and this mutation.
      remote.forceVersionConflict = true;
      final controller = MessageFeedbackController(remote, 's-1');

      final result = await controller.rate(
        'm3',
        FeedbackRatingValue.positive,
        note: 'x',
      );

      expect(result.ok, isFalse);
      expect(result.code, 'version-conflict');
      expect(result.message, 'feedback changed elsewhere');
      // The reply's authoritative row replaced the optimistic one.
      expect(controller.view.items['m3']!.version, 7);
      expect(controller.view.items['m3']!.rating, FeedbackRatingValue.negative);
    },
  );

  test(
    'rate keeps the stored note; clearNote removes it keeping the rating',
    () async {
      final remote = _FakeRemote();
      remote.stored.add(
        const MessageFeedbackItem(
          messageId: 'm4',
          rating: FeedbackRatingValue.positive,
          note: 'original',
          version: 2,
        ),
      );
      final controller = MessageFeedbackController(remote, 's-1');

      await controller.rate('m4', FeedbackRatingValue.negative);

      expect(remote.calls.last.note, 'original');

      await controller.clearNote('m4');
      expect(controller.view.items['m4']!.rating, FeedbackRatingValue.negative);
      expect(controller.view.items['m4']!.note, isNull);
    },
  );

  test(
    'queued toggles serialize: the second reads the first commit and retracts',
    () async {
      final remote = _FakeRemote();
      final controller = MessageFeedbackController(remote, 's-1');

      final first = controller.toggle('m5', FeedbackRatingValue.positive);
      final second = controller.toggle('m5', FeedbackRatingValue.positive);
      await Future.wait([first, second]);

      // The second mutation ran after the first settled: it observed the
      // committed positive rating and retracted instead of re-putting.
      expect(remote.calls[0].op, 'put');
      expect(remote.calls[0].ifVersion, isNull);
      expect(remote.calls[1].op, 'delete');
      expect(remote.calls[1].ifVersion, 1);
      expect(controller.view.items.containsKey('m5'), isFalse);
    },
  );

  test('disposeAll retires every live controller', () async {
    final host = PluginHost();
    host.provide('slots', host.slots);
    host.register(MessageFeedbackPlugin());
    await host.activateAll();
    final controllers = host.service<MessageFeedbackControllers>(
      'messageFeedback',
    )!;
    final controller = controllers.forSession('s-9');

    controllers.disposeAll();

    final result = await controller.toggle('m6', FeedbackRatingValue.positive);
    expect(result.ok, isFalse);
    expect(result.code, 'disposed');
  });

  testWidgets('feedback rows rate and toggle through the provider surface', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen()),
      ),
    );
    await tester.pump();

    // No fixtures: the store starts empty and shows the empty state.
    expect(container.read(messageFeedbackProvider), isEmpty);
    expect(find.text('No feedback yet'), findsOneWidget);

    // Seed one recorded row through the notifier, like a settled transcript
    // would once the assistant-actions hole carries these controls.
    container
        .read(messageFeedbackProvider.notifier)
        .rate('m-1', FeedbackRating.positive);
    await tester.pump();

    expect(find.text('No feedback yet'), findsNothing);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);

    // Tapping the active rating retracts it (toggle semantics)…
    await tester.tap(find.byIcon(Icons.thumb_up));
    await tester.pump();
    expect(
      container.read(messageFeedbackProvider)['m-1']!.rating,
      FeedbackRating.none,
    );

    // …and tapping an inactive rating commits it.
    await tester.tap(find.byIcon(Icons.thumb_down_outlined));
    await tester.pump();
    expect(
      container.read(messageFeedbackProvider)['m-1']!.rating,
      FeedbackRating.negative,
    );
  });
}
