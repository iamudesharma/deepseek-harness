/// Console terminal session state: the host session pool behind one
/// Riverpod notifier, with one xterm emulator buffer per session.
///
/// The host verbs are line-mode (`terminal/send` settles with a viewport;
/// there is no keystroke stream and no follow stream), so the bridge is
/// explicit: keystrokes accumulate into a pending line with local echo,
/// Enter submits the line and paints the settled viewport, Ctrl+C signals.
/// Arrow keys and other cursor movements are swallowed — the pending line
/// tracks plain append/backspace only, which is exactly what the host can
/// consume. This limit is documented, not silent: the emulator still renders
/// every output byte with full fidelity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection_controller.dart';
import '../../theme/app_theme.dart';

/// Max emulator scrollback lines per console session.
const int kTerminalMaxLines = 2000;

/// How many scrollback lines a manual refresh reads.
const int kTerminalRefreshLines = 200;

/// One console session: host identity plus its emulator buffer.
///
/// The [terminal] buffer is the display of record — output viewports and the
/// MOTD are written into it, and the pending input line is echoed there —
/// so a rebuild never loses painted output.
class ConsoleSession {
  /// Creates a console session.
  ConsoleSession({
    required this.sessionId,
    required this.terminal,
    required this.viewController,
    this.name,
    this.type = 'shell',
    this.exited = false,
    this.exitCode,
    this.busy = false,
    this.error,
  });

  /// Registry-minted host identity.
  final String sessionId;

  /// Owner-local display name, when the session was opened with one.
  final String? name;

  /// Backend type that created the session.
  final String type;

  /// The emulator buffer backing the panel view.
  final Terminal terminal;

  /// Selection controller for the panel view.
  final TerminalController viewController;

  /// True after the top-level shell exited.
  final bool exited;

  /// Settled exit code, when the host reported one.
  final int? exitCode;

  /// True while one foreground send is in flight.
  final bool busy;

  /// Last failure to surface inline; cleared by the next success.
  final String? error;

  /// Pending input line, echoed locally, submitted on Enter.
  final StringBuffer pending = StringBuffer();

  /// Display label: the owner-local name or the short session id.
  String label(String untitled) =>
      (name == null || name!.isEmpty) ? '$untitled $sessionId' : name!;

  /// Copy with the given fields replaced.
  ConsoleSession copyWith({
    bool? exited,
    int? exitCode,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return ConsoleSession(
      sessionId: sessionId,
      terminal: terminal,
      viewController: viewController,
      name: name,
      type: type,
      exited: exited ?? this.exited,
      exitCode: exitCode ?? this.exitCode,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Console session pool state: sessions in publication order plus selection.
class TerminalPoolState {
  /// Creates the pool state.
  const TerminalPoolState({this.sessions = const [], this.selectedId});

  /// Live sessions, in host publication order.
  final List<ConsoleSession> sessions;

  /// Selected session id; null selects the first session.
  final String? selectedId;

  /// The selected session, defaulting to the first live one.
  ConsoleSession? get selected {
    if (sessions.isEmpty) return null;
    if (selectedId == null) return sessions.first;
    for (final session in sessions) {
      if (session.sessionId == selectedId) return session;
    }
    return sessions.first;
  }

  /// Copy with the given fields replaced.
  TerminalPoolState copyWith({
    List<ConsoleSession>? sessions,
    String? selectedId,
  }) {
    return TerminalPoolState(
      sessions: sessions ?? this.sessions,
      selectedId: selectedId ?? this.selectedId,
    );
  }
}

/// Maps theme aliases onto the emulator palette: the panel background stays
/// the code-block surface, and the 16 ANSI colors stay the literal palette
/// so authored output contrast survives (the same rule the shared ANSI
/// renderer applies to runs that paint their own background).
TerminalTheme terminalThemeFor(DswAliases aliases) {
  return TerminalTheme(
    cursor: aliases.labelPrimary,
    selection: aliases.labelPrimary.withValues(alpha: 0.3),
    foreground: aliases.labelPrimary,
    background: aliases.markdownCodeBlock,
    black: const Color(0xFF000000),
    white: const Color(0xFFBBBBBB),
    red: const Color(0xFFBB0000),
    green: const Color(0xFF00BB00),
    yellow: const Color(0xFFBBBB00),
    blue: const Color(0xFF0000BB),
    magenta: const Color(0xFFBB00BB),
    cyan: const Color(0xFF00BBBB),
    brightBlack: const Color(0xFF555555),
    brightRed: const Color(0xFFFF5555),
    brightGreen: const Color(0xFF00FF00),
    brightYellow: const Color(0xFFFFFF55),
    brightBlue: const Color(0xFF5555FF),
    brightMagenta: const Color(0xFFFF55FF),
    brightCyan: const Color(0xFF55FFFF),
    brightWhite: const Color(0xFFFFFFFF),
    searchHitBackground: const Color(0xFFFFFF55),
    searchHitBackgroundCurrent: const Color(0xFFFFFF55),
    searchHitForeground: const Color(0xFF000000),
  );
}

/// Owns the console session pool: opens, drives, refreshes, and closes host
/// sessions, and bridges xterm keystrokes onto the line-mode verbs.
class TerminalSessionsNotifier extends StateNotifier<TerminalPoolState> {
  /// Creates the notifier.
  TerminalSessionsNotifier(this.ref) : super(const TerminalPoolState());

  /// Provider access for the connection client.
  final Ref ref;

  /// Select one session.
  void select(String sessionId) {
    state = state.copyWith(selectedId: sessionId);
  }

  /// Replace the pool from a `terminal/list` snapshot, preserving emulator
  /// buffers for sessions the host still reports.
  Future<void> refresh() async {
    final client = ref.read(connectionClientProvider);
    final value = await client.terminalList();
    final seen = <String>{};
    final next = <ConsoleSession>[];
    for (final raw in (value['sessions'] as List? ?? [])) {
      final map = (raw as Map).cast<String, dynamic>();
      final id = map['sessionId'] as String;
      seen.add(id);
      final existing = _byId(id);
      if (existing != null) {
        next.add(existing);
        continue;
      }
      next.add(_create(map));
    }
    for (final stale in state.sessions) {
      if (!seen.contains(stale.sessionId)) {
        _writeLine(stale, '\r\n[closed on host]');
      }
    }
    state = TerminalPoolState(
      sessions: next,
      selectedId: state.selectedId,
    );
  }

  /// Open one console session and select it.
  Future<void> open({String? name, String? cwd}) async {
    final client = ref.read(connectionClientProvider);
    final value = await client.terminalOpen(name: name, cwd: cwd);
    final map = value.cast<String, dynamic>();
    final session = _create(map);
    final motd = map['motd'] as String?;
    if (motd != null && motd.isNotEmpty) {
      session.terminal.write(motd);
      if (!motd.endsWith('\n')) session.terminal.write('\r\n');
    }
    state = TerminalPoolState(
      sessions: [...state.sessions, session],
      selectedId: session.sessionId,
    );
  }

  /// Close one session on the host and drop its buffer.
  Future<void> close(String sessionId) async {
    final client = ref.read(connectionClientProvider);
    await client.terminalClose(sessionId: sessionId);
    final next = state.sessions
        .where((session) => session.sessionId != sessionId)
        .toList(growable: false);
    state = TerminalPoolState(sessions: next, selectedId: state.selectedId);
  }

  /// Read the scrollback tail into the session's buffer.
  Future<void> readTail(ConsoleSession session) async {
    final client = ref.read(connectionClientProvider);
    final value = await client.terminalRead(
      sessionId: session.sessionId,
      count: kTerminalRefreshLines,
    );
    final text = value['text'] as String? ?? '';
    if (text.isNotEmpty) {
      session.terminal.write(text);
      if (!text.endsWith('\n')) session.terminal.write('\r\n');
    }
    _replace(session.copyWith(clearError: true));
  }

  /// Bridge xterm keystrokes onto the line-mode verbs.
  ///
  /// Printable text appends to the pending line with local echo; backspace
  /// erases one pending char; Enter submits; Ctrl+C signals; escape
  /// sequences (arrows, function keys) are swallowed because the host has
  /// no cursor-addressing verb to carry them.
  void handleOutput(ConsoleSession session, String data) {
    if (session.exited || session.busy) return;
    for (var i = 0; i < data.length; i++) {
      final code = data.codeUnitAt(i);
      if (code == 0x03) {
        _interrupt(session);
        return;
      }
      if (code == 0x0d || code == 0x0a) {
        _submit(session);
        return;
      }
      if (code == 0x7f || code == 0x08) {
        if (session.pending.isNotEmpty) {
          final text = session.pending.toString();
          session.pending.clear();
          session.pending.write(text.substring(0, text.length - 1));
          session.terminal.write('\b \b');
        }
        continue;
      }
      if (code == 0x1b) {
        // Swallow one escape sequence. A `[` introducer starts a CSI
        // sequence: consume it, then parameter bytes (0x30-0x3F) and
        // intermediates (0x20-0x2F), then the single final byte (0x40-0x7E).
        // Any other single byte after ESC is a lone escape; consume it too.
        i++;
        if (i < data.length && data.codeUnitAt(i) == 0x5b) {
          i++;
          while (i < data.length) {
            final c = data.codeUnitAt(i);
            if (c < 0x20 || c > 0x3f) break;
            i++;
          }
        }
        continue;
      }
      if (code < 0x20) continue;
      session.pending.writeCharCode(code);
      session.terminal.write(String.fromCharCode(code));
    }
  }

  /// Deliver SIGINT to the session's foreground process group.
  Future<void> _interrupt(ConsoleSession session) async {
    if (session.exited || session.busy) return;
    session.pending.clear();
    session.terminal.write('^C\r\n');
    _replace(session.copyWith(busy: true, clearError: true));
    try {
      final client = ref.read(connectionClientProvider);
      await client.terminalSignal(sessionId: session.sessionId, signal: 'SIGINT');
    } catch (error) {
      _replace(session.copyWith(busy: false, error: '$error'));
      return;
    }
    _replace(session.copyWith(busy: false, clearError: true));
  }

  /// Submit the pending line as one foreground send and paint the viewport.
  Future<void> _submit(ConsoleSession session) async {
    final text = session.pending.toString();
    session.pending.clear();
    session.terminal.write('\r\n');
    _replace(session.copyWith(busy: true, clearError: true));
    try {
      final client = ref.read(connectionClientProvider);
      final value = await client.terminalSend(
        sessionId: session.sessionId,
        text: text,
        submit: true,
      );
      final viewport = value['viewport'] as String? ?? '';
      if (viewport.isNotEmpty) {
        session.terminal.write(viewport);
        if (!viewport.endsWith('\n')) session.terminal.write('\r\n');
      }
      final status = (value['sessionStatus'] as Map?)?.cast<String, dynamic>();
      if (status != null && status['kind'] == 'exited') {
        final code = status['exitCode'] as int?;
        _replace(
          session.copyWith(busy: false, exited: true, exitCode: code, clearError: true),
        );
        return;
      }
    } catch (error) {
      _replace(session.copyWith(busy: false, error: '$error'));
      return;
    }
    _replace(session.copyWith(busy: false, clearError: true));
  }

  ConsoleSession? _byId(String sessionId) {
    for (final session in state.sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  ConsoleSession _create(Map<String, dynamic> map) {
    final terminal = Terminal(maxLines: kTerminalMaxLines);
    final session = ConsoleSession(
      sessionId: map['sessionId'] as String,
      terminal: terminal,
      viewController: TerminalController(),
      name: map['name'] as String?,
      type: map['type'] as String? ?? 'shell',
    );
    // Keystrokes arrive here; the view only renders. Wired per session so
    // the bridge always carries the session the keystrokes belong to.
    terminal.onOutput = (data) => handleOutput(session, data);
    return session;
  }

  void _writeLine(ConsoleSession session, String text) {
    session.terminal.write(text);
  }

  void _replace(ConsoleSession session) {
    state = TerminalPoolState(
      sessions: [
        for (final existing in state.sessions)
          existing.sessionId == session.sessionId ? session : existing,
      ],
      selectedId: state.selectedId,
    );
  }
}

/// The console session pool.
final terminalSessionsProvider =
    StateNotifierProvider<TerminalSessionsNotifier, TerminalPoolState>(
      (ref) => TerminalSessionsNotifier(ref),
    );
