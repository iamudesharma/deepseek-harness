/// Terminal card model — Dart port of the React terminal derivation
/// (`terminal-card-model.ts` + `bash-sample.tsx` summary rules).
///
/// A foreground `bash`/`pwsh` call renders a terminal card; `run_in_background`
/// stays a generic row. Successful results carry trailing `[exit code: N]` /
/// `[killed by signal: X]` markers that become the status pill and are stripped
/// from the body.
library;

import 'dart:convert';

/// Settled terminal outcome parsed from result text.
class TerminalOutcome {
  const TerminalOutcome({required this.body, this.exitCode, this.signal});

  /// Output with the trailing status marker removed.
  final String body;
  final int? exitCode;
  final String? signal;
}

final RegExp _exitMarker = RegExp(r'\[exit code: (-?\d+)\]\s*$');
final RegExp _signalMarker = RegExp(r'\[killed by signal: ([A-Z0-9_+-]+)\]\s*$');

/// Splits the trailing status marker off a settled shell result.
TerminalOutcome parseTerminalOutcome(String result) {
  final exit = _exitMarker.firstMatch(result);
  if (exit != null) {
    return TerminalOutcome(
      body: result.substring(0, exit.start).trimRight(),
      exitCode: int.tryParse(exit.group(1)!),
    );
  }
  final sig = _signalMarker.firstMatch(result);
  if (sig != null) {
    return TerminalOutcome(
      body: result.substring(0, sig.start).trimRight(),
      signal: sig.group(1),
    );
  }
  return TerminalOutcome(body: result);
}

Object? _parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val as Object?));
  return null;
}

/// Whether this call is a background launch (generic row, not a terminal card).
bool isBackgroundCall(String argsRaw) {
  final map = _asMap(_parseArgs(argsRaw));
  return map?['run_in_background'] == true;
}

/// Foreground command from args (`command`, tolerating `cmd`).
String? commandOf(String argsRaw) {
  final map = _asMap(_parseArgs(argsRaw));
  final cmd = map?['command'] ?? map?['cmd'];
  return cmd is String && cmd.isNotEmpty ? cmd : null;
}

/// Row summary: explicit `description` first, then the command's first line.
String terminalSummary(String argsRaw) {
  final map = _asMap(_parseArgs(argsRaw));
  final desc = map?['description'];
  if (desc is String && desc.isNotEmpty) return desc.split('\n').first;
  final cmd = map?['command'] ?? map?['cmd'];
  if (cmd is String && cmd.isNotEmpty) return cmd.split('\n').first;
  if (argsRaw.isNotEmpty) return argsRaw.split('\n').first;
  return '';
}

/// Resolves a relative workdir against the session workspace root.
String resolveWorkdir(String? workdir, String? cwd) {
  if (workdir == null || workdir.isEmpty) return cwd ?? '';
  if (workdir.startsWith('/') ||
      workdir.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(workdir)) {
    return workdir;
  }
  if (cwd == null || cwd.isEmpty) return workdir;
  final root = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  return '$root/$workdir';
}
