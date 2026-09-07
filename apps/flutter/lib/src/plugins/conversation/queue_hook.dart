import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/frames.dart';
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import 'hub.dart';
import 'queue_state.dart';
import 'ui/composer.dart' show composerQueueSteerHookProvider;

/// Installs the empty-draft steer hook for [sessionId].
///
/// Mirrors React `InputBar.keyboard.steerQueue`: when the draft is empty and
/// there are still-pending `queued` items, Enter steers the whole queue.
/// The hook is installed as a side-effect of watching the authoritative
/// `queueProvider` and the session's running state, and cleared when
/// preconditions are not met. Host confirmation arrives via `session/queue`.
class QueueSteerHook extends ConsumerWidget {
  const QueueSteerHook({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = activatedHub;
    final queue =
        ref.watch(queueProvider)[sessionId] ?? const <QueuedInboxItem>[];
    final summary = ref.watch(
      sessionsProvider.select((s) => s.byId[SessionId(sessionId)]),
    );
    final running = summary?.running ?? false;

    final hasQueued = queue.any((i) => i.placement == 'queued');
    // Only install when there is something to steer and the session is running
    // (host would reject otherwise). The composer also gates on draftEmpty
    // etc., so this hook being non-null is necessary but not sufficient.
    final shouldInstall = hasQueued && running && hub != null;

    // Post-frame to avoid "setState during build" — mirrors the mount-time
    // registration pattern used for composer submit hooks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(
        composerQueueSteerHookProvider(sessionId).notifier,
      );
      if (!shouldInstall) {
        if (notifier.state != null) notifier.state = null;
        return;
      }
      // Install a stable closure that steers every still-queued item via
      // the canonical host RPC. Host authoritative — no optimistic local
      // mutation, host will push the updated `session/queue` snapshot.
      notifier.state = () {
        final hubNow = activatedHub;
        final queueNow =
            ref.read(queueProvider)[sessionId] ?? const <QueuedInboxItem>[];
        final toSteer = queueNow.where((i) => i.placement == 'queued').toList();
        for (final item in toSteer) {
          unawaited(
            hubNow?.controller
                .updateQueue(
                  SessionId(sessionId),
                  MessageId(item.id),
                  const QueueActionSteer(),
                )
                .catchError((_) {}),
          );
        }
      };
    });

    return const SizedBox.shrink();
  }
}
