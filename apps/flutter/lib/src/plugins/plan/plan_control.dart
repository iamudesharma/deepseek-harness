/// Plan control — the `'plan'` service face: leaving plan mode executes
/// `/plan off` through the command channel, mirroring `PlanChipInjected.
/// exitPlanMode` (null on admitted execution, a user-visible failure line
/// otherwise; failure strings stay English — error-surface policy).
///
/// The command channel is constructor-injected because the Dart host does not
/// yet provide a `remote.commands` service; boot wiring lands with the
/// commands-remote port. The effective-target fold (`pending ? !active :
/// active`) lives with the UI provider — this control is execution only,
/// zero client-side plan state, like the React seat.
library;

import '../../core/session/session_models.dart';

/// One command-execution outcome (the `result.ok | result.error` pair).
class CommandOutcome {
  /// Creates an outcome.
  const CommandOutcome({
    required this.ok,
    this.hasValue = false,
    this.errorCode = '',
    this.errorMessage = '',
  });

  /// Whether the RPC itself succeeded.
  final bool ok;

  /// Whether an ok response carried a value (`undefined` means unknown
  /// command in the React mapping).
  final bool hasValue;

  /// Error code when [ok] is false.
  final String errorCode;

  /// Error message when [ok] is false.
  final String errorMessage;
}

/// Executes one slash line for a session — the `remote.commands.execute`
/// slice ui-plan consumes.
typedef CommandExecutor = Future<CommandOutcome> Function(
  SessionId sessionId,
  String line,
);

/// Plan-mode exit over the command channel.
class PlanControl {
  /// Creates the control over [execute].
  const PlanControl({required this.execute});

  /// The bound command channel.
  final CommandExecutor execute;

  /// Leave plan mode by executing `/plan off`.
  ///
  /// Returns null on admitted execution; a user-visible failure line
  /// otherwise (RPC error `message (code)`, or the unknown-command line when
  /// the channel answers without a value).
  Future<String?> exitPlanMode(SessionId sessionId) async {
    final outcome = await execute(sessionId, '/plan off');
    if (!outcome.ok) return '${outcome.errorMessage} (${outcome.errorCode})';
    if (!outcome.hasValue) return 'unknown command: /plan off';
    return null;
  }
}
