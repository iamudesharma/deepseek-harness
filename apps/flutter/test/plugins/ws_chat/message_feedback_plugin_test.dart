import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_controller.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_plugin.dart';
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
  int listCalls = 0;
  String? failListWith;

  /// Simulates a concurrent writer winning the CAS race on the next mutation.
  bool forceVersionConflict = false;

  @override
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  }) async {
    listCalls++;
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

/// Activates the real plugin over [remote] and returns a scope container
/// sharing the plugin's locale service: the screen then runs the production
/// wiring (explicit remote face → `'messageFeedback'` service → activated
/// binding → session seat) with English copy.
Future<ProviderContainer> _activateWithRemote(_FakeRemote remote) async {
  final container = ProviderContainer();
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('locale', container.read(localeServiceProvider));
  host.provide('remote.messageFeedback', remote);
  host.register(MessageFeedbackPlugin());
  addTearDown(host.deactivateAll);
  addTearDown(container.dispose);
  await host.activateAll();
  container.read(localeServiceProvider).setLocale('en');
  return container;
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
    addTearDown(host.deactivateAll);
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

  testWidgets('feedback screen seeds from one Host list read, then toggles durably', (
    tester,
  ) async {
    final remote = _FakeRemote();
    remote.stored.addAll([
      const MessageFeedbackItem(
        messageId: 'm-1',
        rating: FeedbackRatingValue.positive,
        version: 1,
      ),
      const MessageFeedbackItem(
        messageId: 'm-2',
        rating: FeedbackRatingValue.negative,
        version: 2,
      ),
    ]);
    final container = await _activateWithRemote(remote);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen(sessionId: 's-1')),
      ),
    );
    await tester.pumpAndSettle();

    // A single list read seeds every row; both recorded rows render active.
    expect(remote.listCalls, 1);
    expect(find.text('No feedback yet'), findsNothing);
    expect(find.text('m-1'), findsOneWidget);
    expect(find.text('m-2'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down), findsOneWidget);

    // Tapping an active rating retracts it through the Host (toggle → delete
    // commits removal); the row leaves with the recorded item and no second
    // list read fires.
    await tester.tap(find.byIcon(Icons.thumb_up));
    await tester.pumpAndSettle();
    expect(remote.stored.map((i) => i.messageId), ['m-2']);
    expect(remote.calls.single.op, 'delete');
    expect(remote.listCalls, 1);
    expect(find.text('m-1'), findsNothing);
    expect(find.text('m-2'), findsOneWidget);

    // …and tapping an inactive rating commits it (toggle → put with the
    // observed version).
    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();
    expect(
      remote.stored.singleWhere((i) => i.messageId == 'm-2').rating,
      FeedbackRatingValue.positive,
    );
    expect(remote.calls.last.op, 'put');
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
  });

  testWidgets('feedback note saves through rate and clears through clearNote', (
    tester,
  ) async {
    final remote = _FakeRemote();
    remote.stored.add(
      const MessageFeedbackItem(
        messageId: 'm-2',
        rating: FeedbackRatingValue.positive,
        version: 1,
      ),
    );
    final container = await _activateWithRemote(remote);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen(sessionId: 's-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'helpful context');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(remote.stored.single.note, 'helpful context');
    // The dialog closes on success; the trigger now shows the stored note.
    expect(find.text('helpful context'), findsOneWidget);

    // Emptying the editor removes the note while keeping the rating.
    await tester.tap(find.text('helpful context'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(remote.stored.single.note, isNull);
    expect(remote.stored.single.rating, FeedbackRatingValue.positive);
  });

  testWidgets('a version-conflict settle reports and keeps the authoritative row', (
    tester,
  ) async {
    final remote = _FakeRemote();
    remote.stored.add(
      const MessageFeedbackItem(
        messageId: 'm-3',
        rating: FeedbackRatingValue.negative,
        version: 7,
      ),
    );
    remote.forceVersionConflict = true;
    final container = await _activateWithRemote(remote);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen(sessionId: 's-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();

    // The conflict text comes from describeFeedbackFailure; the reply's
    // authoritative row (negative, v7) stays rendered.
    expect(find.text('feedback changed elsewhere'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down), findsOneWidget);
  });

  testWidgets('a failed list read shows the error with a working retry', (
    tester,
  ) async {
    final remote = _FakeRemote()..failListWith = 'unavailable';
    final container = await _activateWithRemote(remote);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen(sessionId: 's-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('unavailable'), findsOneWidget);

    remote.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(remote.listCalls, 2);
    expect(find.text('No feedback yet'), findsOneWidget);
  });

  testWidgets('without a session the screen keeps the empty state', (
    tester,
  ) async {
    final container = await _activateWithRemote(_FakeRemote());

    // No explicit sessionId and no current session in the fresh container.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No feedback yet'), findsOneWidget);
  });

  testWidgets('without a wired remote the screen stays renderable with a visible failure', (
    tester,
  ) async {
    // No connection and no explicit face: the plugin wires _AbsentRemote and
    // still registers its copy, so the failure settles visibly.
    final container = ProviderContainer();
    final host = PluginHost();
    host.provide('slots', host.slots);
    host.provide('locale', container.read(localeServiceProvider));
    host.register(MessageFeedbackPlugin());
    addTearDown(host.deactivateAll);
    addTearDown(container.dispose);
    await host.activateAll();
    container.read(localeServiceProvider).setLocale('en');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageFeedbackScreen(sessionId: 's-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('message feedback remote is not wired yet'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
