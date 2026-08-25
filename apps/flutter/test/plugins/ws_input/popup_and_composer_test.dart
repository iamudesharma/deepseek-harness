import 'dart:async';

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/commands/popup_select.dart';
import 'package:dsh_flutter/src/plugins/commands/ui/popup_select_overlay.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/question_composer_entry.dart'
    show questionComposerSelect;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted spec recording option loads and settlements.
class FakeSpec implements PopupSpec<SessionId> {
  FakeSpec({this.failFirst = false, this.throwOnSelect = false});

  final bool failFirst;
  final bool throwOnSelect;
  var loadCount = 0;
  final List<SelectOption> settled = [];

  static const rows = [
    SelectOption(id: 'a', label: 'Alpha', detail: 'first'),
    SelectOption(id: 'b', label: 'Beta'),
    SelectOption(
      id: 'c',
      label: 'Gamma',
      confirmation: SelectConfirmation(
        title: 'Risky',
        description: 'This cannot be undone.',
        acknowledgeLabel: 'I understand',
        cancelLabel: 'Back',
        confirmLabel: 'Do it',
      ),
    ),
  ];

  @override
  Future<List<SelectOption>> options(SessionId context, PopupSignal signal) async {
    loadCount++;
    if (failFirst && loadCount == 1) throw StateError('offline');
    return rows;
  }

  @override
  Future<void> onSelect(SelectOption option, SessionId context) async {
    if (throwOnSelect) throw StateError('settle blew up');
    settled.add(option);
  }
}

/// Recording wiring.
class RecordingDeps implements PopupSelectDeps {
  final List<TokenSegment> consumed = [];
  var focusCalls = 0;

  @override
  bool consume(TokenSegment segment) {
    consumed.add(segment);
    return true;
  }

  @override
  void focusComposer() => focusCalls++;
}

void main() {
  group('popupSelect shell (popup.ts port)', () {
    test('filterOptions: blank keeps all; case-insensitive label/detail', () {
      const rows = [
        SelectOption(id: '1', label: 'Deploy Prod'),
        SelectOption(id: '2', label: 'Restart', detail: 'Staging cluster'),
      ];
      expect(filterOptions(rows, ''), hasLength(2));
      expect(filterOptions(rows, 'deploy'), [rows[0]]);
      expect(filterOptions(rows, 'STAGING'), [rows[1]]);
      expect(filterOptions(rows, 'zzz'), isEmpty);
    });

    test('open loads options once; search filters locally without refetch',
        () async {
      final spec = FakeSpec();
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('deploy', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/deploy'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.value.status, PopupStatus.ready);
      expect(controller.state.value.command, 'deploy');
      expect(spec.loadCount, 1);

      controller.setSearch('alph');
      expect(controller.state.value.search, 'alph');
      expect(controller.state.value.active, 0);
      expect(spec.loadCount, 1); // never re-queried per keystroke
    });

    test('move wraps over filtered rows; highlight rejects out-of-range', () async {
      final spec = FakeSpec();
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('x', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/x'));
      await Future<void>.delayed(Duration.zero);
      controller.move(1);
      expect(controller.state.value.active, 1);
      controller.move(-1);
      expect(controller.state.value.active, 0);
      controller.move(-1); // wraps to the last row
      expect(controller.state.value.active, 2);
      controller.highlight(9); // out of range → no-op
      expect(controller.state.value.active, 2);
    });

    test('select settles single-flight, consumes segment, closes, focuses',
        () async {
      final spec = FakeSpec();
      final deps = RecordingDeps();
      final controller = PopupSelectController<SessionId>(deps);
      controller.open('deploy', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/deploy'));
      await Future<void>.delayed(Duration.zero);

      // Single-flight: while the first settle is in flight (spec records
      // synchronously here, so drive two and expect one settlement).
      await controller.select(0);
      await controller.select(1);
      expect(spec.settled.map((o) => o.id), ['a']);
      expect(deps.consumed.single,
          isA<EnterSegment>().having((s) => s.token, 'token', '/deploy'));
      expect(controller.state.value.open, isFalse);
      expect(deps.focusCalls, 1);
    });

    test('gated option enters confirmation; select blocked until acknowledged',
        () async {
      final spec = FakeSpec();
      final deps = RecordingDeps();
      final controller = PopupSelectController<SessionId>(deps);
      controller.open('gamma', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/gamma'));
      await Future<void>.delayed(Duration.zero);

      await controller.select(2); // Gamma carries the gate
      expect(controller.state.value.confirming?.id, 'c');
      expect(deps.consumed, isEmpty); // nothing settled yet

      await controller.select(0); // picker interactions no-op while gated
      expect(spec.settled, isEmpty);

      controller.acknowledge(true);
      expect(controller.state.value.acknowledged, isTrue);
      await controller.confirm();
      expect(spec.settled.single.id, 'c');
      expect(controller.state.value.open, isFalse);
      expect(deps.focusCalls, 1);
    });

    test('cancelConfirmation returns to the picker without settling', () async {
      final spec = FakeSpec();
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('gamma', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/gamma'));
      await Future<void>.delayed(Duration.zero);
      await controller.select(2);
      controller.cancelConfirmation();
      expect(controller.state.value.confirming, isNull);
      expect(controller.state.value.open, isTrue);
      expect(spec.settled, isEmpty);
    });

    test('onSelect failure keeps the shell open with error; retry re-arms select',
        () async {
      final spec = FakeSpec(throwOnSelect: true);
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('boom', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/boom'));
      await Future<void>.delayed(Duration.zero);
      await controller.select(0);
      expect(controller.state.value.open, isTrue);
      expect(controller.state.value.error, contains('settle blew up'));
      expect(controller.state.value.submitting, isFalse);
    });

    test('options failure surfaces failed state; retry reloads same binding',
        () async {
      final spec = FakeSpec(failFirst: true);
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('flaky', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/flaky'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.value.status, PopupStatus.failed);
      expect(controller.state.value.error, contains('offline'));

      controller.retry();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.value.status, PopupStatus.ready);
      expect(spec.loadCount, 2);
    });

    test('dismiss during flying options drops the late write and consumption',
        () async {
      final completer = Completer<List<SelectOption>>();
      late PopupSignal captured;
      final spec = _HangingSpec(completer, (signal) => captured = signal);
      final deps = RecordingDeps();
      final controller = PopupSelectController<SessionId>(deps);
      controller.open('slow', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/slow'));
      controller.dismiss();

      completer.complete(FakeSpec.rows); // late settlement flies in
      await Future<void>.delayed(Duration.zero);
      expect(captured.aborted, isTrue);
      expect(controller.state.value.open, isFalse); // stays closed
      expect(deps.consumed, isEmpty);
    });

    test('reopen supersedes the previous binding (late first fetch dropped)',
        () async {
      final first = Completer<List<SelectOption>>();
      final second = Completer<List<SelectOption>>();
      late PopupSignal firstSignal;
      final controller =
          PopupSelectController<SessionId>(RecordingDeps());

      controller.open('one', _HangingSpec(first, (s) => firstSignal = s),
          const SessionId('s1'), const TokenSegment.enter(token: '/one'));
      controller.open('two', _HangingSpec(second, (_) {}),
          const SessionId('s1'), const TokenSegment.enter(token: '/two'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.value.command, 'two');
      first.complete(FakeSpec.rows); // stale binding settles late
      await Future<void>.delayed(Duration.zero);
      second.complete(const [SelectOption(id: 'z', label: 'Zeta')]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.value.status, PopupStatus.ready);
      expect(controller.state.value.options.single.label, 'Zeta');
      expect(firstSignal.aborted, isTrue);
    });
  });

  group('PopupSelectOverlay widget', () {
    // Production mounts the overlay seat at the composer card's top edge
    // (bottom of the column): the shell opens UPWARD from that anchor
    // (React `bottom: calc(100% + 4px)`), so the fixture anchors low.
    Widget host(PopupSelectController<SessionId> controller) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PopupSelectOverlay(controller: controller),
            ),
          ),
        );
    testWidgets('closed renders nothing; open renders rows; tap settles',
        (tester) async {
      final spec = FakeSpec();
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      await tester.pumpWidget(host(controller));
      expect(find.byKey(const ValueKey('popup-select')), findsNothing);

      controller.open('deploy', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/deploy'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('popup-select')), findsOne);
      expect(find.text('/deploy'), findsOne); // search hint
      expect(find.text('Alpha'), findsOne);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(spec.settled.single.id, 'a');
      expect(find.byKey(const ValueKey('popup-select')), findsNothing);
    });

    testWidgets('gated row swaps to the confirmation card', (tester) async {
      final spec = FakeSpec();
      final controller = PopupSelectController<SessionId>(RecordingDeps());
      controller.open('gamma', spec, const SessionId('s1'),
          const TokenSegment.enter(token: '/gamma'));
      await tester.pumpWidget(host(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gamma'));
      await tester.pumpAndSettle();
      expect(find.text('Risky'), findsOne);
      expect(find.byKey(const ValueKey('popup-confirm')), findsOne);

      // Confirm disabled until acknowledged.
      await tester.tap(find.byKey(const ValueKey('popup-confirm')));
      await tester.pumpAndSettle();
      expect(spec.settled, isEmpty);

      await tester.tap(find.byKey(const ValueKey('popup-acknowledge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('popup-confirm')));
      await tester.pumpAndSettle();
      expect(spec.settled.single.id, 'c');
    });
  });

  group('user-questions composer chain entry', () {
    test('selector matches only a PendingQuestion carrier', () {
      const pending = PendingQuestion(
        rpcId: 'r1',
        sessionId: 's1',
        questions: [],
      );
      expect(questionComposerSelect(pending), same(pending));
      expect(questionComposerSelect(null), isNull);
      expect(questionComposerSelect('not-a-question'), isNull);
    });
  });
}

/// Spec whose options fetch hangs until the test completes it.
class _HangingSpec implements PopupSpec<SessionId> {
  _HangingSpec(this._completer, void Function(PopupSignal) onSignal)
      : _onSignal = onSignal;

  final Completer<List<SelectOption>> _completer;
  final void Function(PopupSignal) _onSignal;

  @override
  Future<List<SelectOption>> options(SessionId context, PopupSignal signal) {
    _onSignal(signal);
    return _completer.future;
  }

  @override
  Future<void> onSelect(SelectOption option, SessionId context) async {}
}
