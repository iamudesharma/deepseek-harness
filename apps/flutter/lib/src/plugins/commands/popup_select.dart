/// Headless popupSelect shell state — Dart port of
/// `packages/client/ui-commands/src/client/popup.ts`. One controller per
/// client session: loads options once, filters them locally against the
/// shell's own search text, and settles a selection through the context
/// captured at open time. The shell is a transient layer (never in the input
/// state machine): draft consumption and composer focus are injected
/// callbacks; the controller never touches the input machine.
///
/// Late settlements lose their write rights through binding identity:
/// dismiss/dispose/reopen swap the binding, so a settling options fetch or
/// onSelect that no longer matches writes nothing and consumes nothing.
library;

import 'package:flutter/foundation.dart';

import '../input_trigger/trigger_source.dart' show TokenSpan;
import 'command_service.dart' show SelectOption;

/// Cancellation handle handed to a spec's options loader (the Dart analog of
/// the fetch AbortSignal): a superseded binding aborts it, and a long-running
/// loader can bail early on [aborted].
class PopupSignal {
  bool _aborted = false;

  /// Supersedes the owning binding.
  void abort() => _aborted = true;

  /// Whether the owning binding was superseded.
  bool get aborted => _aborted;
}

/// The command token segment snapshotted at shell-open time, replayed to the
/// injected [PopupSelectDeps.consume] callback after a successful selection.
/// The input side guards it: a menu-path span consumes iff draftRev is
/// unchanged, an enter-path line iff the trimmed draft still equals the bare
/// token.
sealed class TokenSegment {
  const TokenSegment();

  /// Menu-path pick: the open-time trigger-token span for CAS.
  const factory TokenSegment.menu({required TokenSpan span}) = MenuSegment;

  /// Enter-path invocation: the bare `/name` token line.
  const factory TokenSegment.enter({required String token}) = EnterSegment;
}

/// Menu-path segment (see [TokenSegment]).
class MenuSegment extends TokenSegment {
  /// Creates the segment over its open-time span.
  const MenuSegment({required this.span});

  /// The open-time trigger-token span for CAS.
  final TokenSpan span;
}

/// Enter-path segment (see [TokenSegment]).
class EnterSegment extends TokenSegment {
  /// Creates the segment over the bare token line.
  const EnterSegment({required this.token});

  /// The bare `/name` token line.
  final String token;
}

/// Structural business spec the shell settles against — the popupSelect half
/// of CommandUiSpec, generic in the context value the opener captures (the
/// wiring passes its session projection; the controller only carries it from
/// open() to the callbacks).
abstract interface class PopupSpec<TCtx> {
  /// Load the option rows once per open (a retry after failure reuses the
  /// same signal).
  Future<List<SelectOption>> options(TCtx context, PopupSignal signal);

  /// Settle the picked option against the open-time context.
  Future<void> onSelect(SelectOption option, TCtx context);
}

/// Injected session-wiring callbacks of one controller (tests pass fakes).
abstract interface class PopupSelectDeps {
  /// Consume the open-time token segment after a successful onSelect (the
  /// wiring dispatches the consume-token event to the opening session).
  /// Returns whether the token was consumed; false (CAS miss) is benign and
  /// never retried.
  bool consume(TokenSegment segment);

  /// Return focus to the session composer (successful settle and Escape
  /// close paths).
  void focusComposer();
}

/// Options-load lifecycle; 'failed' keeps the shell open for retry().
enum PopupStatus { pending, ready, failed }

/// Popup shell state (the shell component renders from here; closed renders
/// nothing).
@immutable
class PopupState {
  /// Creates a state snapshot.
  const PopupState({
    required this.open,
    required this.command,
    required this.status,
    required this.options,
    required this.search,
    required this.active,
    required this.submitting,
    required this.confirming,
    required this.acknowledged,
    required this.error,
  });

  /// Whether the shell is visible.
  final bool open;

  /// Command name the shell is open for (null while closed).
  final String? command;

  /// Options-load lifecycle.
  final PopupStatus status;

  /// Options as loaded — never re-fetched per keystroke; views render
  /// [filterOptions] over them.
  final List<SelectOption> options;

  /// Local filter text over the loaded options.
  final String search;

  /// Highlight index into the filtered row list (0 when empty/pending).
  final int active;

  /// A select() settlement is in flight: further select/search/highlight
  /// no-op until it settles.
  final bool submitting;

  /// Option waiting for explicit risk acknowledgement; null during normal
  /// selection.
  final SelectOption? confirming;

  /// Caller-controlled checkbox state for the pending confirmation.
  final bool acknowledged;

  /// Surfaced settlement failure (options load or onSelect); null when none.
  final String? error;

  /// The closed/resting state.
  static const PopupState closed = PopupState(
    open: false,
    command: null,
    status: PopupStatus.pending,
    options: [],
    search: '',
    active: 0,
    submitting: false,
    confirming: null,
    acknowledged: false,
    error: null,
  );
}

/// Filter option rows against the shell's local search text (case-insensitive
/// substring over label and detail; blank search keeps every row). Port of
/// `filterOptions`.
List<SelectOption> filterOptions(List<SelectOption> options, String search) {
  final query = search.trim().toLowerCase();
  if (query.isEmpty) return options;
  return [
    for (final o in options)
      if (o.label.toLowerCase().contains(query) ||
          (o.detail?.toLowerCase().contains(query) ?? false))
        o,
  ];
}

/// One open shell's bindings (spec + open-time context + segment snapshot +
/// options-fetch abort).
class _OpenBinding<TCtx> {
  _OpenBinding({
    required this.command,
    required this.spec,
    required this.context,
    required this.segment,
  });

  final String command;
  final PopupSpec<TCtx> spec;
  final TCtx context;
  final TokenSegment segment;
  final PopupSignal signal = PopupSignal();
}

/// The shell's error-strip line for a settlement failure.
String _errorText(Object error) => error.toString();

/// Headless controller of one session's popupSelect shell. State publishes
/// through [state] (a ValueNotifier; the overlay widget listens).
class PopupSelectController<TCtx> {
  /// Creates the controller over [deps]' session wiring.
  PopupSelectController(this.deps);

  /// Session wiring.
  final PopupSelectDeps deps;

  /// Shell state store (the overlay component subscribes here).
  final ValueNotifier<PopupState> state = ValueNotifier<PopupState>(
    PopupState.closed,
  );

  _OpenBinding<TCtx>? _binding;

  /// Open the shell for one command: publish pending state and fetch options
  /// once through the business spec. A reopen supersedes the previous shell
  /// (its options fetch is aborted, its late settlements are dropped).
  void open(
    String command,
    PopupSpec<TCtx> spec,
    TCtx context,
    TokenSegment segment,
  ) {
    _binding?.signal.abort();
    final binding = _OpenBinding<TCtx>(
      command: command,
      spec: spec,
      context: context,
      segment: segment,
    );
    _binding = binding;
    state.value = PopupState.closed.copyWith(open: true, command: command);
    _load(binding);
  }

  /// Run the one options fetch of a binding; settlement rights die with the
  /// binding.
  void _load(_OpenBinding<TCtx> binding) {
    binding.spec
        .options(binding.context, binding.signal)
        .then(
          (options) => _apply(
            binding,
            (s) => s.copyWith(
              status: PopupStatus.ready,
              options: options,
              active: 0,
              error: null,
            ),
          ),
          onError: (Object error) {
            debugPrint(
              '[ui-commands] popupSelect options failed for /${binding.command}: $error',
            );
            _apply(
              binding,
              (s) => s.copyWith(
                status: PopupStatus.failed,
                options: [],
                active: 0,
                error: _errorText(error),
              ),
            );
          },
        );
  }

  /// Re-run a failed options fetch (search survives; no-op unless status is
  /// 'failed').
  void retry() {
    final binding = _binding;
    final s = state.value;
    if (binding == null || !s.open || s.status != PopupStatus.failed) return;
    state.value = s.copyWith(status: PopupStatus.pending, error: null);
    _load(binding);
  }

  /// Replace the local search text (pure local filter — the provider is never
  /// re-queried) and rebase the highlight onto the new filtered list.
  void setSearch(String search) {
    final s = state.value;
    if (!s.open || s.submitting || s.confirming != null || search == s.search) {
      return;
    }
    state.value = s.copyWith(search: search, active: 0);
  }

  /// Move the highlight across the filtered rows (wraps around; no-op unless
  /// options are ready and no selection is in flight). +1 down, -1 up.
  void move(int dir) {
    final s = state.value;
    if (!s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    final rows = filterOptions(s.options, s.search);
    if (rows.isEmpty) return;
    state.value = s.copyWith(
      active: (s.active + dir + rows.length) % rows.length,
    );
  }

  /// Set the highlight directly (pointer hover; no-op unless ready, idle, and
  /// in filtered range).
  void highlight(int index) {
    final s = state.value;
    if (!s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    if (index < 0 ||
        index >= filterOptions(s.options, s.search).length ||
        index == s.active) {
      return;
    }
    state.value = s.copyWith(active: index);
  }

  /// Select one filtered row: single-flight — the first call enters
  /// `submitting` and later calls no-op until it settles. An option carrying
  /// a confirmation first enters the risk gate. Success consumes the
  /// open-time token segment (a false CAS answer is benign), closes, and
  /// returns focus to the composer. Failure keeps the shell open with search,
  /// highlight, and token intact, surfaces the error, and re-arms select as
  /// the retry.
  Future<void> select(int index) async {
    final binding = _binding;
    final s = state.value;
    if (binding == null ||
        !s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    final rows = filterOptions(s.options, s.search);
    if (index < 0 || index >= rows.length) return;
    final option = rows[index];
    if (option.confirmation != null) {
      state.value = s.copyWith(
        confirming: option,
        acknowledged: false,
        error: null,
      );
      return;
    }
    await _settle(binding, option);
  }

  /// Update the explicit checkbox for the currently pending risk gate.
  void acknowledge(bool acknowledged) {
    final s = state.value;
    if (!s.open ||
        s.submitting ||
        s.confirming == null ||
        s.acknowledged == acknowledged) {
      return;
    }
    state.value = s.copyWith(acknowledged: acknowledged);
  }

  /// Cancel only the risk gate and return to the still-open option picker.
  void cancelConfirmation() {
    final s = state.value;
    if (!s.open || s.submitting || s.confirming == null) return;
    state.value = s.copyWith(confirming: null, acknowledged: false);
  }

  /// Settle the gated option only after the checkbox is acknowledged.
  Future<void> confirm() async {
    final binding = _binding;
    final s = state.value;
    if (binding == null ||
        !s.open ||
        s.submitting ||
        s.confirming == null ||
        !s.acknowledged) {
      return;
    }
    await _settle(binding, s.confirming!);
  }

  /// Run the business settlement for an already admitted option.
  Future<void> _settle(_OpenBinding<TCtx> binding, SelectOption option) async {
    final s = state.value;
    if (_binding != binding || !s.open || s.submitting) return;
    state.value = s.copyWith(
      submitting: true,
      confirming: null,
      acknowledged: false,
      error: null,
    );
    try {
      await binding.spec.onSelect(option, binding.context);
    } catch (error) {
      debugPrint(
        '[ui-commands] popupSelect onSelect failed for /${binding.command}: $error',
      );
      if (_binding != binding)
        return; // dismissed/reopened/disposed while onSelect flew
      state.value = state.value.copyWith(
        submitting: false,
        error: _errorText(error),
      );
      return;
    }
    if (_binding != binding)
      return; // late success: no state write, no consumption
    deps.consume(binding.segment);
    _binding = null;
    state.value = PopupState.closed;
    deps.focusComposer();
  }

  /// Close the shell; aborts a flying options fetch and revokes settlement
  /// rights. An outside pointer interaction dismisses plainly (the click's
  /// own target takes focus); Escape passes focusComposer to restore focus
  /// explicitly.
  void dismiss({bool focusComposer = false}) {
    if (_binding == null) return;
    _binding!.signal.abort();
    _binding = null;
    state.value = PopupState.closed;
    if (focusComposer) deps.focusComposer();
  }

  /// Scope-teardown disposer: abort in-flight work and clear state (no focus
  /// side effect).
  void dispose() {
    _binding?.signal.abort();
    _binding = null;
    state.value = PopupState.closed;
    state.dispose();
  }

  /// Apply a mutation only while [binding] still owns the shell.
  void _apply(
    _OpenBinding<TCtx> binding,
    PopupState Function(PopupState s) mutate,
  ) {
    if (_binding != binding) return;
    state.value = mutate(state.value);
  }
}

extension _PopupStateCopy on PopupState {
  PopupState copyWith({
    bool? open,
    String? command,
    PopupStatus? status,
    List<SelectOption>? options,
    String? search,
    int? active,
    bool? submitting,
    Object? confirming = _sentinel,
    bool? acknowledged,
    String? error,
  }) {
    return PopupState(
      open: open ?? this.open,
      command: command ?? this.command,
      status: status ?? this.status,
      options: options ?? this.options,
      search: search ?? this.search,
      active: active ?? this.active,
      submitting: submitting ?? this.submitting,
      confirming: identical(confirming, _sentinel)
          ? this.confirming
          : confirming as SelectOption?,
      acknowledged: acknowledged ?? this.acknowledged,
      error: error ?? this.error,
    );
  }
}

const Object _sentinel = Object();
