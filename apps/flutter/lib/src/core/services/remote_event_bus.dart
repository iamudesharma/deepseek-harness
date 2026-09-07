/// Remote event bus over forwarded host cordis events (`host/remote-event`
/// frames): `$on(name, handler)` subscribe, `dispatch(name, args)` fanout.
///
/// Carried here as its own module so [runtime.remote-event-dispatch] names a
/// real unique carrier; re-exported by `runtime_services.dart` alongside the
/// other service faces it ships with.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subscribes per event name; dispatch fans out to the live handler list.
class RemoteEventBus {
  final Map<String, List<void Function(List<Object?> args)>> _listeners = {};

  /// Subscribes to one remote event name; returns an unsubscriber.
  VoidCallback $on(String event, void Function(List<Object?> args) handler) {
    _listeners.putIfAbsent(event, () => []).add(handler);
    return () {
      final list = _listeners[event];
      if (list == null) return;
      list.remove(handler);
      if (list.isEmpty) _listeners.remove(event);
    };
  }

  /// Fans out one forwarded event to its subscribers.
  void dispatch(String event, List<Object?> args) {
    for (final handler in List.of(_listeners[event] ?? const [])) {
      handler(args);
    }
  }

  /// Whether anyone listens to [event] (integration assertions).
  bool hasListeners(String event) => (_listeners[event] ?? []).isNotEmpty;
}

/// App-wide remote event bus instance (provided as the `'remote'` service).
final remoteBusProvider = Provider<RemoteEventBus>((ref) => RemoteEventBus());
