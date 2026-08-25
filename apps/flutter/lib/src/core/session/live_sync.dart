import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/frames.dart';
import '../../plugins/conversation/queue_state.dart';
import '../../plugins/conversation/jobs_state.dart';
import '../../plugins/user_questions/approval_state.dart';
import '../../plugins/user_questions/pending_interactions.dart';
import '../../plugins/user_questions/questions_state.dart';
import '../../plugins/user_questions/question_models.dart' show QuestionItem;
import '../services/runtime_services.dart';
import '../connection/connection_client.dart';
import 'projection_store.dart';
import 'session_models.dart';
import 'sessions_controller.dart';
import '../../features/conversation/message_provider.dart';
import '../../plugins/plan/ui/plan_provider.dart';
import '../../plugins/permission_presets/permission_session_provider.dart';

/// Live sync that wires the SSE mux/host streams to Riverpod state.
///
/// Mirrors `ConnectionController` + `SessionManager` + `Session` handling in
/// `packages/client/connection` and `packages/client/runtime`. The Flutter
/// `FlutterConnectionController` already pumps both SSE streams with backoff;
/// this provider installs the `onMuxEnvelope` / `onHostEnvelope` / `onConnected`
/// handlers that were missing, so `session.prompt` → `session/event` → UI
/// happens without a manual refresh.
///
/// Data flow:
/// ```
/// Composer → ConnectionClient.sendMessage() → session.prompt
/// → mux: session/event → live_sync → messageListProvider.invalidate(sessionId) → MessageList
/// → host: session-status / session-added → sessionsProvider update
/// ```
/// Applies one session-event type to a list summary (the running/blank rules
/// the live fold enforces). Returns null when the event has no summary effect.
///
/// An authoritative `user/message` clears the blank bit — the React object
/// layer does the same, so a replayed history stream never re-shows the
/// blank-session hero over real conversation content.
SessionSummary? applySessionEventToSummary(SessionSummary current, String eventType) {
  switch (eventType) {
    case 'turn/start':
      return current.copyWith(running: true);
    case 'user/message':
      return current.copyWith(running: true, blank: false);
    case 'turn/end':
      return current.copyWith(running: false);
  }
  return null;
}

/// Seeds a fetched history tail's [block] into the session's projection
/// store and returns the keys this fold may still publish — keys a push
/// frame already advanced past the block's cut are withheld, so a stale
/// baseline cannot regress newer state (projection_store.dart).
Set<String> publishableProjectionKeys(
  SessionProjectionStore store,
  SessionProjectionsBlock? block,
) {
  if (block == null) return const {};
  return store.seed(block);
}

/// Reconciles one session's summary `pendingInteraction` marker against the
/// live wait stores (the sidebar's amber-dot source, mirroring the manager's
/// list-snapshot fold over `pendingInteractions`). No-op when the session is
/// unknown to the list.
void reconcileSessionPendingStatus(
  QuestionsController questions,
  ApprovalsController approvals,
  SessionsController sessions,
  String sessionId,
) {
  final question = questions.waits[sessionId];
  final approval = approvals.waits[sessionId];
  sessions.updateSession(
    SessionId(sessionId),
    (s) => recomputePendingSummary(s, question, approval),
  );
}

/// Drops every pending-interaction wait and summary marker at the moment a
/// connection generation dies (React `SessionManager.handleDisconnected`):
/// interactions resolved while disconnected send no frame, so stale waits
/// must not survive — mux-open replay re-adds every still-pending request
/// with its live rpcId.
void dropPendingInteractionState(
  QuestionsController questions,
  ApprovalsController approvals,
  SessionsController sessions,
) {
  for (final sessionId in questions.waits.keys.toList()) {
    questions.clear(sessionId);
  }
  for (final sessionId in approvals.waits.keys.toList()) {
    approvals.clear(sessionId);
  }
  for (final id in sessions.snapshot.byId.keys) {
    sessions.updateSession(id, (s) => s.withPendingInteraction(null));
  }
}

/// Clears pending-interaction state whenever the connection state leaves
/// `connected` for a dead generation. Split from [liveSyncProvider] so tests
/// can install it through a probe provider without the web-only guards.
void installPendingInteractionResync(
  Ref ref, {
  required QuestionsController questions,
  required ApprovalsController approvals,
  required SessionsController sessions,
}) {
  ref.listen<ConnectionState>(connectionStateProvider, (previous, next) {
    if (next == ConnectionState.reconnecting ||
        next == ConnectionState.disconnected) {
      dropPendingInteractionState(questions, approvals, sessions);
    }
  });
}

final liveSyncProvider = Provider<void>((ref) {
  final client = ref.watch(connectionClientProvider);
  if (client.baseUrl.isEmpty) return;
  final controller = ref.watch(flutterConnectionProvider);

  // Install handlers idempotently; the controller is a singleton per container.
  // Use a flag to avoid re-installing on every rebuild.
  final existingMux = controller.onMuxEnvelope;
  if (existingMux != null) return; // already wired

  // Wait-store controllers are container-lifetime singletons; capture once
  // for the interaction-plane cases below.
  final questionsCtrl = ref.read(pendingQuestionsProvider.notifier);
  final approvalsCtrl = ref.read(approvalsProvider.notifier);
  final sessionsCtrl = ref.read(sessionsProvider.notifier);

  controller.onMuxEnvelope = (Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    if (type == null) return;
    try {
      final decoded = MuxFrame.fromJson(frame);
      switch (decoded) {
        case SessionEventFrame(:final sessionId, :final event, :final view):
          // Append to live history window (handles gap detection + dedup).
          try {
            final entry = HistoryEntry(
              event: SessionEvent.fromJson(event),
              view: view?.view as Map<String, dynamic>?,
            );
            ref.read(liveHistoryProvider(sessionId.value).notifier).appendLive(entry);
          } catch (e) {
            if (kDebugMode) debugPrint('[liveSync] failed to append session/event: $e');
            // Fallback to invalidation
            Future.microtask(() {
              try {
                ref.invalidate(messageListProvider(sessionId.value));
              } catch (_) {}
            });
          }
          // Also touch sessionsProvider to update updatedAt / running / blank.
          final eventType = event['type'] as String?;
          if (eventType != null) {
            ref.read(sessionsProvider.notifier).updateSession(
                  sessionId,
                  (s) => applySessionEventToSummary(s, eventType) ?? s,
                );
            // A new turn supersedes any previous agent-level error banner.
            if (eventType == 'turn/start' || eventType == 'user/message') {
              ref.read(agentErrorProvider(sessionId.value).notifier).state = null;
            }
            // Direct plan/mode log drives the chip when the projection frame
            // has not yet arrived (mirrors the projection derivation).
            if (eventType == 'plan/mode') {
              final active = event['data'] is Map ? (event['data'] as Map)['active'] as bool? : null;
              if (active != null) {
                try {
                  ref.read(planProvider.notifier).settle(active: active, error: null);
                } catch (_) {}
              }
            }
          }
        case SessionSubscribedFrame(:final sessionId, :final lastSeq):
          if (kDebugMode) debugPrint('[liveSync] session/subscribed ${sessionId.value} lastSeq $lastSeq');
          // On (re)subscribe, ensure live window is at least as fresh as
          // lastSeq. For now, trigger a re-fetch if live is empty.
          final live = ref.read(liveHistoryProvider(sessionId.value));
          if (live.isEmpty) {
            Future.microtask(() async {
              try {
                final client = ref.read(connectionClientProvider);
                if (client.baseUrl.isEmpty) return;
                final res = await client.getSessionHistory(sessionId);
                ref.read(liveHistoryProvider(sessionId.value).notifier).replaceAll(res.entries);
                final publishable = publishableProjectionKeys(
                    ref.read(sessionProjectionStores(sessionId.value)), res.projections);
                if (publishable.contains('title')) {
                  final title = res.projections!.values['title'];
                  ref.read(sessionsProvider.notifier).updateSession(sessionId, (s) => s.withTitle(title is String && title.isNotEmpty ? title : null));
                }
                final perm = publishable.contains('permissions')
                    ? res.projections!.values['permissions']
                    : null;
                if (perm is Map) {
                  try {
                    final select = PermissionSelect.fromJson(perm.cast<String, dynamic>());
                    ref.read(permissionSelectProvider(sessionId.value).notifier).state = select;
                  } catch (_) {
                    ref.read(permissionSelectProvider(sessionId.value).notifier).state = null;
                  }
                }
              } catch (_) {}
            });
          }
        case SessionQueueFrame(:final sessionId, :final items):
          // Authoritative whole-snapshot inbox: store for the queue dock and
          // invalidate the derived message list as before.
          ref.read(queueProvider.notifier).replace(sessionId.value, items);
          Future.microtask(() {
            try {
              ref.invalidate(messageListProvider(sessionId.value));
            } catch (_) {}
          });
        case StreamErrorFrame(:final error):
          if (kDebugMode) debugPrint('[liveSync] mux stream/error: ${error.message}');
        case SessionJobsFrame(:final sessionId, :final jobs):
          // Authoritative whole-snapshot job set → WS-Tasks jobs surface.
          ref.read(jobsProvider.notifier).replace(sessionId.value, jobs);
        case QuestionRequestedFrame(:final sessionId, :final questions):
          // WS-Input: the pending question set; the envelope rpcId (stamped
          // by the transports) is the question's stable logical id.
          questionsCtrl.requested(
                sessionId.value,
                rpcId: frame['rpcId'] as String? ?? '',
                questions:
                    questions.map(QuestionItem.fromJson).toList(),
              );
          reconcileSessionPendingStatus(
              questionsCtrl, approvalsCtrl, sessionsCtrl, sessionId.value);
        case QuestionResolvedFrame(:final sessionId, :final questionRpcId, :final outcome):
          questionsCtrl.resolved(sessionId.value, questionRpcId.value, outcome);
          reconcileSessionPendingStatus(
              questionsCtrl, approvalsCtrl, sessionsCtrl, sessionId.value);
        case SessionProjectionFrame(:final sessionId, :final key, :final value, :final seq):
          // Higher seq wins: a replayed or stale projection frame folds
          // nothing (projection_store.dart).
          final store = ref.read(sessionProjectionStores(sessionId.value));
          if (!store.offer(key, value, seq)) break;
          if (key == 'title') {
            final title = value is String && value.isNotEmpty ? value : null;
            ref.read(sessionsProvider.notifier).updateSession(sessionId, (s) => s.withTitle(title));
          } else if (key == 'plan') {
            // Host `plan` projection: {active, pending}. Keep pending ? !active
            // target logic in the chip (plan.pending ? !active : active).
            if (value is Map) {
              final active = value['active'] as bool?;
              final pending = value['pending'] as bool?;
              if (active != null) {
                try {
                  // ignore: avoid_dynamic_calls
                  ref.read(planProvider.notifier).settle(active: active, error: null);
                  if (pending != null && pending) {
                    ref.read(planProvider.notifier).setPending();
                  }
                } catch (_) {}
              }
            }
          } else if (key == 'permissions') {
            // Host `permissions` projection: {options:[{value,name,description}], currentValue}
            if (value is Map<String, dynamic>) {
              try {
                final select = PermissionSelect.fromJson(value);
                ref.read(permissionSelectProvider(sessionId.value).notifier).state = select;
              } catch (_) {
                ref.read(permissionSelectProvider(sessionId.value).notifier).state = null;
              }
            } else if (value is Map) {
              try {
                final select = PermissionSelect.fromJson(value.cast<String, dynamic>());
                ref.read(permissionSelectProvider(sessionId.value).notifier).state = select;
              } catch (_) {
                ref.read(permissionSelectProvider(sessionId.value).notifier).state = null;
              }
            } else {
              ref.read(permissionSelectProvider(sessionId.value).notifier).state = null;
            }
          }
          break;
        case ApprovalRequestedFrame(
              :final sessionId,
              :final approvalId,
              :final toolName,
              :final callId,
              :final reason
            ):
          // Answerable server-request: mint the wait keyed by the session;
          // the envelope rpcId backs the answering client-response.
          approvalsCtrl.requested(
                sessionId.value,
                rpcId: frame['rpcId'] as String? ?? '',
                approvalId: approvalId,
                toolName: toolName,
                callId: callId,
                reason: reason,
              );
          reconcileSessionPendingStatus(
              questionsCtrl, approvalsCtrl, sessionsCtrl, sessionId.value);
        case ApprovalResolvedFrame(:final sessionId, :final approvalId):
          // Authoritative settlement: drop the wait, then recompute the
          // summary marker (a sibling question keeps the dot with its kind).
          approvalsCtrl.resolved(sessionId.value, approvalId);
          reconcileSessionPendingStatus(
              questionsCtrl, approvalsCtrl, sessionsCtrl, sessionId.value);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[liveSync] onMuxEnvelope error: $e frame=$frame');
    }
  };

  controller.onHostEnvelope = (Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    if (type == null) return;
    try {
      final decoded = HostFrame.fromJson(frame);
      switch (decoded) {
        case SessionAddedFrame():
          // New session (blank) added; re-fetch the full list to get summary.
          Future.microtask(() async {
            try {
              final sessions = await client.getSessions();
              ref.read(sessionsProvider.notifier).setAll(sessions);
            } catch (_) {}
          });
        case SessionRemovedFrame(:final sessionId):
          sessionsCtrl.removeSession(sessionId);
          // A removed session cannot wait on anyone (manager.ts
          // host/session-removed arm drops the tracked interactions).
          questionsCtrl.clear(sessionId.value);
          approvalsCtrl.clear(sessionId.value);
        case SessionStatusFrame(:final sessionId, :final running):
          ref.read(sessionsProvider.notifier).updateSession(sessionId, (s) => s.copyWith(running: running));
        case AgentErrorFrame(:final sessionId, :final message):
          if (kDebugMode) debugPrint('[liveSync] host/agent-error ${sessionId.value}: $message');
          // Surface immediately in the conversation (mirrors web's agent-error
          // surface); cleared on the session's next turn/start.
          ref.read(agentErrorProvider(sessionId.value).notifier).state = message;
        case WorkspaceChangedFrame() ||
        WorkspaceRemovedFrame() ||
        WorkspaceOrderChangedFrame() ||
        ArchivedSessionsChangedFrame():
          // Workspace changes affect the sidebar grouping; re-fetching workspace
          // list is handled by workspace providers, but we can also re-fetch
          // sessions to keep workspace.sessionIds in sync. For now, just re-fetch
          // sessions as well.
          Future.microtask(() async {
            try {
              final sessions = await client.getSessions();
              ref.read(sessionsProvider.notifier).setAll(sessions);
            } catch (_) {}
          });
        case RemoteEventFrame(event: final event, args: final args):
          // Fan out forwarded host cordis events to subscribers ($on).
          ref.read(remoteBusProvider).dispatch(event, args);
        case HostStreamErrorFrame(:final error):
          if (kDebugMode) debugPrint('[liveSync] host stream/error: ${error.message}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[liveSync] onHostEnvelope error: $e frame=$frame');
    }
  };

  controller.onConnected = (Map<String, dynamic> desc) {
    if (kDebugMode) debugPrint('[liveSync] onConnected host.describe: $desc');
    // Re-sync after reconnect: re-fetch session list and current session history
    // to repair any gap the liveBuffer missed (mirrors Session.repairGap).
    Future.microtask(() async {
      try {
        final sessions = await client.getSessions();
        ref.read(sessionsProvider.notifier).setAll(sessions);
        final current = ref.read(sessionsProvider).current;
        if (current != null) {
          try {
            final res = await client.getSessionHistory(current);
            ref.read(liveHistoryProvider(current.value).notifier).replaceAll(res.entries);
            final publishable = publishableProjectionKeys(
                ref.read(sessionProjectionStores(current.value)), res.projections);
            if (publishable.contains('title')) {
              final title = res.projections!.values['title'];
              ref.read(sessionsProvider.notifier).updateSession(current, (s) => s.withTitle(title is String && title.isNotEmpty ? title : null));
            }
            final perm = publishable.contains('permissions')
                ? res.projections!.values['permissions']
                : null;
            if (perm is Map) {
              try {
                final select = PermissionSelect.fromJson(perm.cast<String, dynamic>());
                ref.read(permissionSelectProvider(current.value).notifier).state = select;
              } catch (_) {
                ref.read(permissionSelectProvider(current.value).notifier).state = null;
              }
            }
          } catch (_) {
            try {
              ref.invalidate(messageListProvider(current.value));
            } catch (_) {}
          }
        } else {
          for (final s in sessions) {
            try {
              final res = await client.getSessionHistory(s.sessionId);
              ref.read(liveHistoryProvider(s.sessionId.value).notifier).replaceAll(res.entries);
              final publishable = publishableProjectionKeys(
                  ref.read(sessionProjectionStores(s.sessionId.value)), res.projections);
              if (publishable.contains('title')) {
                final title = res.projections!.values['title'];
                ref.read(sessionsProvider.notifier).updateSession(s.sessionId, (s2) => s2.withTitle(title is String && title.isNotEmpty ? title : null));
              }
              final perm = publishable.contains('permissions')
                  ? res.projections!.values['permissions']
                  : null;
              if (perm is Map) {
                try {
                  final select = PermissionSelect.fromJson(perm.cast<String, dynamic>());
                  ref.read(permissionSelectProvider(s.sessionId.value).notifier).state = select;
                } catch (_) {
                  ref.read(permissionSelectProvider(s.sessionId.value).notifier).state = null;
                }
              }
            } catch (_) {
              try {
                ref.invalidate(messageListProvider(s.sessionId.value));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    });
  };

  // Pending-interaction resync: when a connection generation dies, every
  // live wait and its summary marker drop; mux-open replay re-adds
  // still-pending requests with their live rpcId (React handleDisconnected).
  installPendingInteractionResync(
    ref,
    questions: questionsCtrl,
    approvals: approvalsCtrl,
    sessions: sessionsCtrl,
  );

  // Ensure the controller is running (idempotent). Deferred via microtask:
  // the pump loop mutates connectionStateProvider synchronously on start,
  // which is a Riverpod initialization violation during this provider's build.
  scheduleMicrotask(controller.start);
  ref.onDispose(() {
    // Do not stop the controller on dispose of this provider alone; the
    // controller is scoped to the ProviderContainer lifetime. If this provider
    // is disposed (e.g., hot reload), we keep the controller running.
  });
});
