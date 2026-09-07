import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Folded plan-mode projection state (`pending ? !active : active` decides
/// the chip target). Zero client-side optimism beyond the two transition
/// flags the UI needs while an RPC is in flight.
class PlanState {
  /// Creates the state.
  const PlanState({required this.active, this.pending = false, this.error});

  /// Whether plan mode is on (host-computed value).
  final bool active;

  /// Whether a switch is currently executing.
  final bool pending;

  /// Last failure line surfaced by an exit attempt.
  final String? error;

  PlanState copyWith({bool? active, bool? pending, String? error}) => PlanState(
    active: active ?? this.active,
    pending: pending ?? this.pending,
    error: error,
  );
}

/// Global plan-state provider; inactive until the host `plan` projection
/// arrives — the last `plan/mode` or command lifecycle drives it. Pre-first
/// plan event mirrors React's "inactive before the first" (types.ts).
final planProvider = StateNotifierProvider<PlanNotifier, PlanState>(
  (ref) => PlanNotifier(),
);

/// UI-state transitions for the plan surfaces. Exit execution does not live
/// here: it goes through the plugin-bound [PlanControl] (`planControlProvider`
/// in `ui/plan_chip_dock.dart`), mirroring the React `/plan off` channel.
class PlanNotifier extends StateNotifier<PlanState> {
  /// Creates the notifier.
  PlanNotifier() : super(const PlanState(active: false));

  /// Marks a switch in flight.
  void setPending() => state = state.copyWith(pending: true, error: null);

  /// Lands a settled switch result.
  void settle({required bool active, String? error}) =>
      state = PlanState(active: active, error: error);

  /// Models the host projection arriving at plan mode (entry rides the
  /// command source host-side; nothing executes here).
  void enter() => state = PlanState(active: true);
}
