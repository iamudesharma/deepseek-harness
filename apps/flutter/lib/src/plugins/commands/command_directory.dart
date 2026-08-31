/// Session-keyed command directory — Dart port of
/// `packages/client/ui-commands/src/client/directory.ts`. One entry per served
/// catalog; single-flight pulls, soft/hard invalidation, and the epoch guard
/// are ported unchanged (the session-key axis is the only dimension).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/session/session_models.dart';

/// One host command row (`CommandDescriptor`): lowercase name, summary, and
/// the optional input hint.
class CommandDescriptor {
  /// Creates a descriptor.
  const CommandDescriptor({
    required this.name,
    required this.description,
    this.hint,
    this.images = false,
  });

  /// Decodes one wire row; rows missing name/description are skipped by the
  /// caller via [tryFromJson].
  static CommandDescriptor? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final description = raw['description'];
    if (name is! String || name.isEmpty) return null;
    if (description is! String) return null;
    final input = raw['input'];
    String? hint;
    var images = false;
    if (input is Map) {
      final h = input['hint'];
      if (h is String) hint = h;
      final img = input['images'];
      if (img is bool) images = img;
    }
    return CommandDescriptor(
      name: name,
      description: description,
      hint: hint,
      images: images,
    );
  }

  /// Command name without the leading slash.
  final String name;

  /// Human-readable summary used in discovery UI.
  final String description;

  /// Placeholder shown before the user supplies free-form input.
  final String? hint;

  /// Whether composer image attachments may accompany an invocation.
  final bool images;
}

/// Injected pull (the service binds `command.list` off the connection).
typedef FetchCommands = Future<List<CommandDescriptor>> Function(
  SessionId sessionId,
);

/// cold = never pulled; pending = pull in flight with nothing servable;
/// ready = snapshot serving (a soft-invalidate repull keeps this status);
/// failed = last winning pull rejected, snapshot dropped.
enum DirectoryStatus { cold, pending, ready, failed }

class _Entry {
  DirectoryStatus state = DirectoryStatus.cold;
  List<CommandDescriptor> commands = [];
  int epoch = 0;
  Object? lastError;
  final List<void Function()> waiters = [];
}

/// The session-keyed directory cache. Plain class — the owning service wires
/// events and RPC.
class CommandDirectory {
  /// Creates the cache over [fetchCommands].
  CommandDirectory({required FetchCommands fetchCommands})
    : _fetchCommands = fetchCommands;

  final FetchCommands _fetchCommands;
  final Map<SessionId, _Entry> _entries = {};

  /// Current cache status for one session (cold when never touched).
  DirectoryStatus status(SessionId sessionId) =>
      _entries[sessionId]?.state ?? DirectoryStatus.cold;

  /// Synchronous exact-name lookup over one session's hot snapshot; null when
  /// absent or the entry is not ready.
  CommandDescriptor? resolve(SessionId sessionId, String name) {
    final entry = _entries[sessionId];
    if (entry == null || entry.state != DirectoryStatus.ready) return null;
    for (final c in entry.commands) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Soft invalidation: background repull on every touched key; ready
  /// snapshots keep serving.
  void invalidateAll() {
    for (final key in List.of(_entries.keys)) {
      unawaited(refresh(key));
    }
  }

  /// Hard reset on reconnect: every entry drops its snapshot (the agent world
  /// may have changed shape across the generation) and prewarms.
  void resetConnected() {
    for (final MapEntry(key: key, value: entry) in _entries.entries) {
      entry.state = DirectoryStatus.cold;
      entry.commands = [];
      unawaited(refresh(key));
    }
  }

  /// Fire-and-forget prewarm of one session (the source's scope-birth warm).
  void warm(SessionId sessionId) {
    final entry = _entry(sessionId);
    if (entry.state == DirectoryStatus.cold ||
        entry.state == DirectoryStatus.failed) {
      unawaited(refresh(sessionId));
    }
  }

  /// Start one pull for one session. Publishes ready/failed only while it is
  /// still the key's latest pull (epoch guard); a ready snapshot is not
  /// demoted while the pull flies.
  Future<void> refresh(SessionId sessionId) async {
    final entry = _entry(sessionId);
    final epoch = ++entry.epoch;
    if (entry.state != DirectoryStatus.ready) {
      entry.state = DirectoryStatus.pending;
    }
    try {
      final commands = await _fetchCommands(sessionId);
      if (epoch != entry.epoch) return;
      entry.commands = commands;
      entry.state = DirectoryStatus.ready;
      entry.lastError = null;
    } catch (error) {
      if (epoch != entry.epoch) return;
      entry.commands = [];
      entry.state = DirectoryStatus.failed;
      entry.lastError = error;
    } finally {
      if (epoch == entry.epoch) _notifyWaiters(entry);
    }
  }

  /// Strong-wait until one session's catalog is servable (enter-adjudication
  /// "directory must be reached"): ready returns at once; cold/failed launch a
  /// fresh pull; pending joins the flying one. Throws when the awaited pull
  /// fails or [deadline] elapses first.
  Future<List<CommandDescriptor>> ensureReady(
    SessionId sessionId, {
    DateTime? deadline,
  }) async {
    final entry = _entry(sessionId);
    while (true) {
      if (entry.state == DirectoryStatus.ready) return entry.commands;
      if (entry.state != DirectoryStatus.pending) unawaited(refresh(sessionId));
      await _settled(entry, deadline);
      if (entry.state == DirectoryStatus.failed) {
        throw StateError(
          'command directory warmup failed: ${entry.lastError ?? 'unknown error'}',
        );
      }
      // Still pending (the awaited pull was superseded) → wait for the winner.
    }
  }

  /// Drops every cached entry (plugin teardown).
  void clearAll() => _entries.clear();

  _Entry _entry(SessionId sessionId) =>
      _entries.putIfAbsent(sessionId, _Entry.new);

  /// One settlement tick for one entry: completes at the next winning publish
  /// (refresh's finally notifies the waiters), or at [deadline].
  Future<void> _settled(_Entry entry, DateTime? deadline) {
    final completer = Completer<void>();
    entry.waiters.add(() {
      if (!completer.isCompleted) completer.complete();
    });
    if (deadline != null) {
      unawaited(
        Future<void>.delayed(deadline.difference(DateTime.now())).then((_) {
          if (!completer.isCompleted) completer.complete();
        }),
      );
    }
    return completer.future;
  }

  void _notifyWaiters(_Entry entry) {
    final woken = List.of(entry.waiters);
    entry.waiters.clear();
    for (final wake in woken) {
      wake();
    }
  }
}
