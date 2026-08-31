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
import '../connection/remote_mux_client.dart';
import 'projection_store.dart';
import 'session_models.dart';
import 'sessions_controller.dart';
import 'session_provider.dart';
import '../../features/conversation/message_provider.dart';
import '../../plugins/plan/ui/plan_provider.dart';
import '../../plugins/permission_presets/permission_session_provider.dart';
import '../../plugins/attachment/attachment_limits.dart';
import '../../platform/drag_drop.dart' show ImageLimits;
import '../../features/model_selection/model_directory.dart'
    show modelSelectionProjectionProvider, ModelSelection;

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
SessionSummary? applySessionEventToSummary(
  SessionSummary current,
  String eventType,
) {
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

ModelSelection? _parseLiveModelSelection(Map<String, dynamic> json) {
  Map<String, dynamic>? pick(Map<String, dynamic>? node) {
    if (node == null) return null;
    final p = node['provider'] as String?;
    final m = node['model'] as String?;
    if (p == null || p.isEmpty || m == null || m.isEmpty) return null;
    return {
      'provider': p,
      'model': m,
      if (node['reasoningEffort'] is String) 'reasoningEffort': node['reasoningEffort'],
    };
  }

  final next = pick(json['next'] as Map<String, dynamic>?);
  if (next != null) {
    return ModelSelection(
      provider: next['provider'] as String,
      model: next['model'] as String,
      reasoningEffort: next['reasoningEffort'] as String?,
    );
  }
  final last = pick(json['lastUsed'] as Map<String, dynamic>?);
  if (last != null) {
    return ModelSelection(
      provider: last['provider'] as String,
      model: last['model'] as String,
      reasoningEffort: last['reasoningEffort'] as String?,
    );
  }
  final direct = pick(json);
  if (direct != null) {
    return ModelSelection(
      provider: direct['provider'] as String,
      model: direct['model'] as String,
      reasoningEffort: direct['reasoningEffort'] as String?,
    );
  }
  return null;
}

/// Mirrors the controller's `RemoteMuxClient` as a Riverpod provider so the
/// follow-stream opener can re-evaluate when the mux itself becomes
/// available — independent of `currentSession` or `ConnectionState` change
/// orders during startup.
final remoteMuxProvider = Provider<RemoteMuxClient?>((ref) {
  return ref.watch(flutterConnectionProvider).remoteMux;
});

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
            ref
                .read(liveHistoryProvider(sessionId.value).notifier)
                .appendLive(entry);
          } catch (e) {
            if (kDebugMode)
              debugPrint('[liveSync] failed to append session/event: $e');
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
            ref
                .read(sessionsProvider.notifier)
                .updateSession(
                  sessionId,
                  (s) => applySessionEventToSummary(s, eventType) ?? s,
                );
            // Host-authoritative agent preset switch for blank sessions
            // (React ui-agent-preset folds agent-preset/selected into the
            // session row; Flutter hero chip reads session.agentPreset).
            if (eventType == 'agent-preset/selected') {
              final preset = (event['data'] as Map?)?['agentPreset'] as String?;
              if (preset != null) {
                ref
                    .read(sessionsProvider.notifier)
                    .updateSession(
                      sessionId,
                      (s) => s.copyWith(agentPreset: preset),
                    );
              }
            }
            // A new turn supersedes any previous agent-level error banner.
            if (eventType == 'turn/start' || eventType == 'user/message') {
              ref.read(agentErrorProvider(sessionId.value).notifier).state =
                  null;
            }
            // Direct plan/mode log drives the chip when the projection frame
            // has not yet arrived (mirrors the projection derivation).
            if (eventType == 'plan/mode') {
              final active = event['data'] is Map
                  ? (event['data'] as Map)['active'] as bool?
                  : null;
              if (active != null) {
                try {
                  ref
                      .read(planProvider.notifier)
                      .settle(active: active, error: null);
                } catch (_) {}
              }
            }
          }
        case SessionSubscribedFrame(:final sessionId, :final lastSeq):
          // Deprecated: legacy `MuxFrame session/subscribed` path. New master uses
          // `session/follow` snapshot via `openFollowFor → replaceAll` (0 HTTP).
          // Keep decode for backward-compat with old host frames, but do not HTTP
          // `session/page` here — that storm was 1× `page` per subscribed event
          // and contributed to the 25-pending screenshot.
          if (kDebugMode) {
            debugPrint(
              '[liveSync] session/subscribed (legacy, no page) ${sessionId.value} lastSeq $lastSeq',
            );
          }
          // No `getSessionHistory` — follow snapshot owns the window.
        case SessionQueueFrame(:final sessionId, :final items):
          // Authoritative whole-snapshot inbox: store for the queue dock.
          // No `messageListProvider` invalidation — that provider is now a pure
          // view of `liveHistory` (React parity: queue does not page history).
          // Previously `invalidate(messageListProvider)` → 1× `session/page` per
          // queue update → storm when queue ticks during streaming.
          ref.read(queueProvider.notifier).replace(sessionId.value, items);
        case StreamErrorFrame(:final error):
          if (kDebugMode)
            debugPrint('[liveSync] mux stream/error: ${error.message}');
        case SessionJobsFrame(:final sessionId, :final jobs):
          // Authoritative whole-snapshot job set → WS-Tasks jobs surface.
          ref.read(jobsProvider.notifier).replace(sessionId.value, jobs);
        case QuestionRequestedFrame(:final sessionId, :final questions):
          // WS-Input: the pending question set; the envelope rpcId (stamped
          // by the transports) is the question's stable logical id.
          questionsCtrl.requested(
            sessionId.value,
            rpcId: frame['rpcId'] as String? ?? '',
            questions: questions.map(QuestionItem.fromJson).toList(),
          );
          reconcileSessionPendingStatus(
            questionsCtrl,
            approvalsCtrl,
            sessionsCtrl,
            sessionId.value,
          );
        case QuestionResolvedFrame(
          :final sessionId,
          :final questionRpcId,
          :final outcome,
        ):
          questionsCtrl.resolved(sessionId.value, questionRpcId.value, outcome);
          reconcileSessionPendingStatus(
            questionsCtrl,
            approvalsCtrl,
            sessionsCtrl,
            sessionId.value,
          );
        case SessionProjectionFrame(
          :final sessionId,
          :final key,
          :final value,
          :final seq,
        ):
          // Higher seq wins: a replayed or stale projection frame folds
          // nothing (projection_store.dart).
          final store = ref.read(sessionProjectionStores(sessionId.value));
          if (!store.offer(key, value, seq)) break;
          if (key == 'title') {
            final title = value is String && value.isNotEmpty ? value : null;
            ref
                .read(sessionsProvider.notifier)
                .updateSession(sessionId, (s) => s.withTitle(title));
          } else if (key == 'plan') {
            // Host `plan` projection: {active, pending}. Keep pending ? !active
            // target logic in the chip (plan.pending ? !active : active).
            if (value is Map) {
              final active = value['active'] as bool?;
              final pending = value['pending'] as bool?;
              if (active != null) {
                try {
                  // ignore: avoid_dynamic_calls
                  ref
                      .read(planProvider.notifier)
                      .settle(active: active, error: null);
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
                ref
                        .read(
                          permissionSelectProvider(sessionId.value).notifier,
                        )
                        .state =
                    select;
              } catch (_) {
                ref
                        .read(
                          permissionSelectProvider(sessionId.value).notifier,
                        )
                        .state =
                    null;
              }
            } else if (value is Map) {
              try {
                final select = PermissionSelect.fromJson(
                  value.cast<String, dynamic>(),
                );
                ref
                        .read(
                          permissionSelectProvider(sessionId.value).notifier,
                        )
                        .state =
                    select;
              } catch (_) {
                ref
                        .read(
                          permissionSelectProvider(sessionId.value).notifier,
                        )
                        .state =
                    null;
              }
            } else {
              ref
                      .read(permissionSelectProvider(sessionId.value).notifier)
                      .state =
                  null;
            }
          } else if (key == 'imageLimits') {
            // Host `imageLimits` projection: {mediaTypes, maxImagesPerMessage, maxImageBytes, maxMessageImageBytes, ...}
            // Mirrors LocalAttachmentStore defaults; extra fields ignored.
            try {
              if (value is Map) {
                final map = value is Map<String, dynamic>
                    ? value
                    : (value as Map).cast<String, dynamic>();
                final mediaTypes = (map['mediaTypes'] as List?)
                    ?.whereType<String>()
                    .toList();
                final maxImages = map['maxImagesPerMessage'] as int?;
                final maxBytes = map['maxImageBytes'] as int?;
                final maxTotal = map['maxMessageImageBytes'] as int?;
                if (mediaTypes != null &&
                    maxImages != null &&
                    maxBytes != null &&
                    maxTotal != null) {
                  ref.read(imageLimitsProvider.notifier).state = ImageLimits(
                    mediaTypes: mediaTypes,
                    maxImagesPerMessage: maxImages,
                    maxImageBytes: maxBytes,
                    maxMessageImageBytes: maxTotal,
                  );
                }
              }
            } catch (_) {}
          } else if (key == 'modelSelection') {
            try {
              if (value is Map) {
                final sel = _parseLiveModelSelection(
                  (value is Map<String, dynamic>
                          ? value
                          : (value as Map).cast<String, dynamic>()),
                );
                ref
                    .read(modelSelectionProjectionProvider(sessionId.value).notifier)
                    .state = sel;
              } else {
                ref
                    .read(modelSelectionProjectionProvider(sessionId.value).notifier)
                    .state = null;
              }
            } catch (_) {}
          }
          break;
        case ApprovalRequestedFrame(
          :final sessionId,
          :final approvalId,
          :final toolName,
          :final callId,
          :final reason,
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
            questionsCtrl,
            approvalsCtrl,
            sessionsCtrl,
            sessionId.value,
          );
        case ApprovalResolvedFrame(:final sessionId, :final approvalId):
          // Authoritative settlement: drop the wait, then recompute the
          // summary marker (a sibling question keeps the dot with its kind).
          approvalsCtrl.resolved(sessionId.value, approvalId);
          reconcileSessionPendingStatus(
            questionsCtrl,
            approvalsCtrl,
            sessionsCtrl,
            sessionId.value,
          );
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[liveSync] onMuxEnvelope error: $e frame=$frame');
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
          ref
              .read(sessionsProvider.notifier)
              .updateSession(sessionId, (s) => s.copyWith(running: running));
        case AgentErrorFrame(:final sessionId, :final message):
          if (kDebugMode)
            debugPrint(
              '[liveSync] host/agent-error ${sessionId.value}: $message',
            );
          // Surface immediately in the conversation (mirrors web's agent-error
          // surface); cleared on the session's next turn/start.
          ref.read(agentErrorProvider(sessionId.value).notifier).state =
              message;
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
          // Host-authoritative preset switch fanout (React ui-agent-preset
          // folds agent-preset/selected into the session row; the hero chip
          // reads session.agentPreset).
          if (event == 'agent-preset/selected' &&
              args.length >= 2 &&
              args[0] is String &&
              args[1] is String) {
            final sid = SessionId(args[0] as String);
            final preset = args[1] as String;
            ref
                .read(sessionsProvider.notifier)
                .updateSession(sid, (s) => s.copyWith(agentPreset: preset));
          }
          // Fan out forwarded host cordis events to subscribers ($on).
          ref.read(remoteBusProvider).dispatch(event, args);
        case HostStreamErrorFrame(:final error):
          if (kDebugMode)
            debugPrint('[liveSync] host stream/error: ${error.message}');
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[liveSync] onHostEnvelope error: $e frame=$frame');
    }
  };

  controller.onConnected = (Map<String, dynamic> desc) {
    if (kDebugMode) debugPrint('[liveSync] onConnected host.describe: $desc');
    // Re-sync after reconnect: single `session/list` refresh. History is
    // repaired solely by the follow snapshot (`openFollowFor → replaceAll`).
    // Previously this invalidated every `messageListProvider` (N× `session/page`
    // → storm) — removed. React only re-opens `session/follow` on Generation
    // reset, 0× `page` if contiguous (`journal-stream.ts:149`).
    Future.microtask(() async {
      try {
        final sessions = await client.getSessions();
        ref.read(sessionsProvider.notifier).setAll(sessions);
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

  // Domain streams over remote.mux: session/follow for current session,
  // session/control and workspace/follow are handled in connection_controller
  // via synthetic queue/jobs/projection frames. Per-session follow streaming
  // is wired here for the current session; it uses the shared RemoteMuxClient
  // from the controller so one physical WSS carries all logical streams.
  StreamSubscription<Map<String, dynamic>>? followSub;
  SessionId? followSessionId;
  int? followGen;
  void openFollowFor(SessionId sid, int gen, RemoteMuxClient mux) {
    followSub?.cancel();
    followSessionId = sid;
    followGen = gen;
    final stream = mux.openSessionFollow(sid.value, maxMessages: 50);
    followSub = stream.listen(
      (raw) {
        if (followGen != gen || followSessionId != sid) return;
        final type = raw['type'] as String?;
        if (type == 'snapshot') {
          try {
            final records = (raw['records'] as List? ?? const [])
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList();
            final entries = <HistoryEntry>[];
            for (final r in records) {
              if (r['type'] == 'event' && r['event'] is Map) {
                try {
                  entries.add(HistoryEntry(
                    event: SessionEvent.fromJson((r['event'] as Map).cast<String, dynamic>()),
                    view: (r['view'] as Map?)?.cast<String, dynamic>(),
                  ));
                } catch (_) {}
              } else if (r['type'] == 'chunks') {
                // Chunk rows are packed assistant deltas; live streaming handles
                // them via 'event' type 'assistant/chunk' etc, ignore for history
              } else if (r.containsKey('type') && r.containsKey('seq')) {
                try {
                  entries.add(HistoryEntry(event: SessionEvent.fromJson(r), view: null));
                } catch (_) {}
              }
            }
            final int cursor = (raw['cursor'] as int?) ?? (entries.isEmpty ? -1 : entries.last.event.seq);
            final bool hasMore = raw['hasMore'] as bool? ?? false;
            // Use cursor-aware replace to fence live events <= cursor per master sequence rule.
            try {
              ref
                  .read(liveHistoryProvider(sid.value).notifier)
                  .replaceAllWithCursorAndHasMore(entries, cursor, hasMore);
            } catch (_) {
              try {
                ref.read(liveHistoryProvider(sid.value).notifier).replaceAllWithCursor(entries, cursor);
                ref.read(liveHistoryProvider(sid.value).notifier).setHasMore(hasMore);
              } catch (_) {
                ref.read(liveHistoryProvider(sid.value).notifier).replaceAll(entries);
              }
            }
            final proj = raw['projections'] as Map?;
            if (proj != null) {
              try {
                final block = SessionProjectionsBlock.fromJson(proj.cast<String, dynamic>());
                final publishable = publishableProjectionKeys(
                  ref.read(sessionProjectionStores(sid.value)),
                  block,
                );
                if (publishable.contains('title')) {
                  final title = block.values['title'];
                  ref.read(sessionsProvider.notifier).updateSession(
                        sid,
                        (s) => s.withTitle(title is String && title.isNotEmpty ? title : null),
                      );
                }
                if (publishable.contains('modelSelection')) {
                  final rawMs = block.values['modelSelection'];
                  if (rawMs is Map) {
                    try {
                      final sel = _parseLiveModelSelection(
                        rawMs.cast<String, dynamic>(),
                      );
                      ref
                          .read(
                            modelSelectionProjectionProvider(sid.value).notifier,
                          )
                          .state = sel;
                    } catch (_) {}
                  } else {
                    ref
                        .read(modelSelectionProjectionProvider(sid.value).notifier)
                        .state = null;
                  }
                }
              } catch (_) {}
            }
          } catch (_) {}
        } else if (type == 'event') {
          final ev = raw['event'] as Map?;
          if (ev == null) return;
          try {
            final entry = HistoryEntry(
              event: SessionEvent.fromJson(ev.cast<String, dynamic>()),
              view: (raw['view'] as Map?)?.cast<String, dynamic>(),
            );
            ref.read(liveHistoryProvider(sid.value).notifier).appendLive(entry);
            final eventType = ev['type'] as String?;
            if (eventType != null) {
              ref.read(sessionsProvider.notifier).updateSession(
                    sid,
                    (s) => applySessionEventToSummary(s, eventType) ?? s,
                  );
            }
          } catch (_) {}
        }
      },
      onError: (_) {},
    );
  }

  // State-driven follow-stream opening. Three signals feed the same effect:
  // current session selection, remote-mux availability on the controller, and
  // connection-state transitions. Any one of them may arrive first depending
  // on startup order; the previous per-listener guards bailed silently when a
  // dependency was not yet ready and never re-fired, so `session/follow` could
  // stay closed even though both sides were healthy.
  void closeFollow() {
    followSub?.cancel();
    followSub = null;
    followSessionId = null;
    followGen = null;
  }

  void maybeOpenFollow() {
    final cur = ref.read(currentSessionProvider);
    final mux = controller.remoteMux;
    final gen = controller.generation;
    final sid = cur?.sessionId;
    if (sid == null || mux == null) return;
    if (followSessionId == sid && followGen == gen) return;
    openFollowFor(sid, gen, mux);
  }

  ref.listen<SessionSummary?>(currentSessionProvider, (prev, next) {
    maybeOpenFollow();
  });
  ref.listen<RemoteMuxClient?>(remoteMuxProvider, (prev, next) {
    maybeOpenFollow();
  });
  ref.listen<ConnectionState>(connectionStateProvider, (prev, next) {
    if (next == ConnectionState.connected) {
      maybeOpenFollow();
    } else if (next == ConnectionState.reconnecting ||
        next == ConnectionState.disconnected) {
      // Generation will be invalidated; follow will be reopened on next connected
      closeFollow();
    }
  });
  // Eagerly attempt to open follow if both session and mux are already
  // available at provider init (otherwise the three listeners above would
  // never fire and the selected session would stay "No messages yet"
  // even though host has history — React's Session.open is eager).
  scheduleMicrotask(maybeOpenFollow);

  // Ensure the controller is running (idempotent). Deferred via microtask:
  // the pump loop mutates connectionStateProvider synchronously on start,
  // which is a Riverpod initialization violation during this provider's build.
  scheduleMicrotask(controller.start);
  ref.onDispose(() {
    followSub?.cancel();
    // Do not stop the controller on dispose of this provider alone; the
    // controller is scoped to the ProviderContainer lifetime. If this provider
    // is disposed (e.g., hot reload), we keep the controller running.
  });
});
