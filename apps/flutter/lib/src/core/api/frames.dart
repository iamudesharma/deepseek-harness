/// The two logical stream unions (legacy, kept for `live_sync` synthetic adapter
/// until domain streams are fully direct; new transport is `remote.mux`).
/// Mirrored from `packages/host/apiproxy/src/api/events.ts`.
///
/// Streams yield the narrow form [StreamRequest] (the server-request view):
/// rpcId is exposed to business code because answerable frames echo it on
/// their responses, while pure pushes use it to identify that single push.
///
/// Unknown discriminants throw: every outbound frame body is validated by the
/// host's `events.schema.ts` before emission, so an unrecognized `type` means
/// a broken peer rather than a variant to skip.
library;

import 'package:meta/meta.dart';

import '../session/session_models.dart' show SessionId;
import 'rpc_envelope.dart';

/// A stream-delivered narrow request: one [frame] plus its correlation id.
@immutable
class StreamRequest<F> {
  /// Creates one delivered frame.
  const StreamRequest({required this.rpcId, required this.frame});

  /// Host-minted correlation id for this delivery.
  final RpcId rpcId;

  /// The decoded frame payload.
  final F frame;
}

/// Render intent accompanying a `tool/call` / `tool/result` session event,
/// mirrored from `ToolEventView`. A pure derivation of args/result through the
/// presenter registered at emission time — never persisted; the same event may
/// carry a different view on a later delivery. An absent view selects the
/// client's documented default (generic JSON card).
sealed class ToolEventView {
  const ToolEventView();

  /// Decodes `{for, view}`; throws [ArgumentError] on unknown `for`.
  factory ToolEventView.fromJson(Map<String, Object?> json) {
    final forField = json['for'];
    switch (forField) {
      case 'call':
        return ToolCallIntent(view: json['view']);
      case 'result':
        return ToolResultIntent(view: json['view']);
      default:
        throw ArgumentError.value(
          forField,
          'for',
          'unknown tool render-intent target',
        );
    }
  }

  /// The raw presenter output; vocabulary extraction belongs to the tool
  /// presentation workstream (`dsh-tools/presentation` remains its owner).
  Object? get view;
}

/// `{ for: 'call', view: ToolCallView }`.
class ToolCallIntent extends ToolEventView {
  /// Wraps the raw call view.
  const ToolCallIntent({required this.view});

  /// Raw presenter output.
  @override
  final Object? view;
}

/// `{ for: 'result', view: ToolResultView }`.
class ToolResultIntent extends ToolEventView {
  /// Wraps the raw result view.
  const ToolResultIntent({required this.view});

  /// Raw presenter output.
  @override
  final Object? view;
}

/// One pending inbox occurrence in the authoritative `session/queue`
/// snapshot, mirrored from `QueuedInboxItem`.
@immutable
class QueuedInboxItem {
  /// Creates one queued occurrence.
  const QueuedInboxItem({
    required this.id,
    required this.placement,
    required this.message,
  });

  /// Decodes from wire; throws [ArgumentError] on unknown placement.
  factory QueuedInboxItem.fromJson(Map<String, Object?> json) {
    final placement = json['placement'];
    if (placement is! String ||
        (placement != 'queued' &&
            placement != 'steering' &&
            placement != 'context')) {
      throw ArgumentError.value(
        placement,
        'placement',
        'unknown inbox placement',
      );
    }
    return QueuedInboxItem(
      id: _requireString(json, 'id'),
      placement: placement,
      message: _requireMap(json, 'message'),
    );
  }

  /// Message identity used by inbox mutations.
  final String id;

  /// `'queued' | 'steering' | 'context'` — agent-resolved FIFO placement.
  final String placement;

  /// Complete pending message (raw `Message` JSON; not durable until claimed).
  final Map<String, Object?> message;
}

/// Mux stream frames mirrored from `MuxFrame`: raw session-event passthrough +
/// control frames + approval/question frames. `approval/requested` and
/// `question/requested` are the answerable server-requests; everything else is
/// a pure push.
sealed class MuxFrame {
  const MuxFrame();

  /// The discriminant literal carried in the wire `type` field.
  String get typeWire;

  /// Decodes one mux frame; throws [ArgumentError] on unknown `type`.
  static MuxFrame fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String)
      throw ArgumentError.value(type, 'type', 'must be a string');
    switch (type) {
      case 'session/event':
        return SessionEventFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          event: _requireMap(json, 'event'),
          view: json['view'] == null
              ? null
              : ToolEventView.fromJson(_requireMap(json, 'view')),
        );
      case 'session/subscribed':
        return SessionSubscribedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          lastSeq: _requireInt(json, 'lastSeq'),
        );
      case 'approval/requested':
        return ApprovalRequestedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          approvalId: _requireString(json, 'approvalId'),
          toolName: _requireString(json, 'toolName'),
          callId: json['callId'] as String?,
          reason: json['reason'] as String?,
        );
      case 'approval/resolved':
        return ApprovalResolvedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          approvalId: _requireString(json, 'approvalId'),
          outcome: _requireString(json, 'outcome'),
        );
      case 'question/requested':
        return QuestionRequestedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          questions: _requireList(
            json,
            'questions',
          ).cast<Map<String, Object?>>(),
        );
      case 'question/resolved':
        return QuestionResolvedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          questionRpcId: RpcId(_requireString(json, 'questionRpcId')),
          outcome: _requireString(json, 'outcome'),
        );
      case 'session/queue':
        return SessionQueueFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          items: _requireList(
            json,
            'items',
          ).cast<Map<String, Object?>>().map(QueuedInboxItem.fromJson).toList(),
        );
      case 'session/jobs':
        return SessionJobsFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          jobs: _requireList(json, 'jobs').cast<Map<String, Object?>>(),
        );
      case 'session/projection':
        return SessionProjectionFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          key: _requireString(json, 'key'),
          value: json['value'],
          seq: _requireInt(json, 'seq'),
        );
      case 'stream/error':
        return StreamErrorFrame(
          error: RpcError.fromJson(_requireMap(json, 'error')),
        );
      default:
        throw ArgumentError.value(
          type,
          'type',
          'unknown mux frame discriminant',
        );
    }
  }
}

/// `session/event` — raw passthrough of one durable session log event. The
/// event map stays raw here; typed folding lands with the conversation-node
/// assembly workstream.
class SessionEventFrame extends MuxFrame {
  /// Creates the frame.
  const SessionEventFrame({
    required this.sessionId,
    required this.event,
    this.view,
  });

  @override
  String get typeWire => 'session/event';

  /// Owning session.
  final SessionId sessionId;

  /// Raw `SessionEvent` JSON from the durable log.
  final Map<String, Object?> event;

  /// Host-computed tool render intent when the event is a tool call/result.
  final ToolEventView? view;
}

/// `session/subscribed` — open-of-stream control frame carrying the replay
/// watermark.
class SessionSubscribedFrame extends MuxFrame {
  /// Creates the frame.
  const SessionSubscribedFrame({
    required this.sessionId,
    required this.lastSeq,
  });

  @override
  String get typeWire => 'session/subscribed';

  /// Subscribed session.
  final SessionId sessionId;

  /// Last sequence number the host will replay through this stream.
  final int lastSeq;
}

/// `approval/requested` — answerable server-request; respond by echoing
/// [ApprovalRequestedFrame]'s rpcId.
class ApprovalRequestedFrame extends MuxFrame {
  /// Creates the frame.
  const ApprovalRequestedFrame({
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.callId,
    this.reason,
  });

  @override
  String get typeWire => 'approval/requested';

  /// Owning session.
  final SessionId sessionId;

  /// Approval identity used when resolving.
  final String approvalId;

  /// Tool awaiting approval.
  final String toolName;

  /// Tool-call identity when the approval attaches to one call.
  final String? callId;

  /// Human-readable reason shown in the approval panel.
  final String? reason;
}

/// `approval/resolved` — pure push announcing a resolution.
class ApprovalResolvedFrame extends MuxFrame {
  /// Creates the frame.
  const ApprovalResolvedFrame({
    required this.sessionId,
    required this.approvalId,
    required this.outcome,
  });

  @override
  String get typeWire => 'approval/resolved';

  /// Owning session.
  final SessionId sessionId;

  /// Resolved approval identity.
  final String approvalId;

  /// `ApprovalOutcome` wire literal.
  final String outcome;
}

/// `question/requested` — answerable server-request carrying the full
/// question set.
class QuestionRequestedFrame extends MuxFrame {
  /// Creates the frame.
  const QuestionRequestedFrame({
    required this.sessionId,
    required this.questions,
  });

  @override
  String get typeWire => 'question/requested';

  /// Owning session.
  final SessionId sessionId;

  /// Raw `AskUserQuestionItem[]` payloads.
  final List<Map<String, Object?>> questions;
}

/// `question/resolved` — pure push announcing an answer or cancellation.
class QuestionResolvedFrame extends MuxFrame {
  /// Creates the frame.
  const QuestionResolvedFrame({
    required this.sessionId,
    required this.questionRpcId,
    required this.outcome,
  });

  @override
  String get typeWire => 'question/resolved';

  /// Owning session.
  final SessionId sessionId;

  /// The requested frame's rpcId, echoed here as identity.
  final RpcId questionRpcId;

  /// `'answered' | 'cancelled'`.
  final String outcome;
}

/// `session/queue` — complete transient inbox snapshot after every enqueue,
/// mutation, claim, or discard; pending work has no durable event.
class SessionQueueFrame extends MuxFrame {
  /// Creates the frame.
  const SessionQueueFrame({required this.sessionId, required this.items});

  @override
  String get typeWire => 'session/queue';

  /// Owning session.
  final SessionId sessionId;

  /// Authoritative whole-snapshot item list.
  final List<QueuedInboxItem> items;
}

/// `session/jobs` — complete background-job snapshot after every registry
/// commit that changes it; empty set still sends `[]`.
class SessionJobsFrame extends MuxFrame {
  /// Creates the frame.
  const SessionJobsFrame({required this.sessionId, required this.jobs});

  @override
  String get typeWire => 'session/jobs';

  /// Owning session.
  final SessionId sessionId;

  /// Raw `JobView[]` payloads (typed mirror lands with WS-Tasks).
  final List<Map<String, Object?>> jobs;
}

/// `session/projection` — one projection unit's finished value changed; live
/// push state, never logged. Clients keep a per-session value store under
/// higher-seq-wins.
class SessionProjectionFrame extends MuxFrame {
  /// Creates the frame.
  const SessionProjectionFrame({
    required this.sessionId,
    required this.key,
    required this.value,
    required this.seq,
  });

  @override
  String get typeWire => 'session/projection';

  /// Owning session.
  final SessionId sessionId;

  /// Projection unit key.
  final String key;

  /// Schema-validated view output of the unit.
  final Object? value;

  /// Unit watermark at emission.
  final int seq;
}

/// `stream/error` — terminal carrier error shared by both unions.
class StreamErrorFrame extends MuxFrame {
  /// Creates the frame.
  const StreamErrorFrame({required this.error});

  @override
  String get typeWire => 'stream/error';

  /// The failure folded into the RPC error model.
  final RpcError error;
}

/// Host stream frames mirrored from `HostFrame`: lifecycle/status flips,
/// workspace mutations as full-snapshot pushes, forwarded cordis events.
///
/// Unknown discriminants throw for the same reason as [MuxFrame.fromJson].
sealed class HostFrame {
  const HostFrame();

  /// The discriminant literal carried in the wire `type` field.
  String get typeWire;

  /// Decodes one host frame; throws [ArgumentError] on unknown `type`.
  static HostFrame fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String)
      throw ArgumentError.value(type, 'type', 'must be a string');
    switch (type) {
      case 'host/session-added':
        return SessionAddedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          blank: _requireBool(json, 'blank'),
          parentSessionId: json['parentSessionId'] as String?,
          origin: json['origin'] as String?,
          cwd: json['cwd'] as String?,
          agentPreset: json['agentPreset'] as String?,
        );
      case 'host/session-removed':
        return SessionRemovedFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
        );
      case 'host/session-status':
        return SessionStatusFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          running: _requireBool(json, 'running'),
        );
      case 'host/agent-error':
        return AgentErrorFrame(
          sessionId: SessionId(_requireString(json, 'sessionId')),
          message: _requireString(json, 'message'),
        );
      case 'host/workspace-changed':
        return WorkspaceChangedFrame(workspace: _requireMap(json, 'workspace'));
      case 'host/workspace-removed':
        return WorkspaceRemovedFrame(
          workspaceId: _requireString(json, 'workspaceId'),
        );
      case 'host/workspace-order-changed':
        return WorkspaceOrderChangedFrame(
          workspaceIds: _requireList(json, 'workspaceIds').cast<String>(),
        );
      case 'host/archived-sessions-changed':
        return ArchivedSessionsChangedFrame(
          archivedSessionIds: _requireList(
            json,
            'archivedSessionIds',
          ).cast<String>(),
        );
      case 'host/remote-event':
        return RemoteEventFrame(
          event: _requireString(json, 'event'),
          args: _requireList(json, 'args'),
        );
      case 'stream/error':
        return HostStreamErrorFrame(
          error: RpcError.fromJson(_requireMap(json, 'error')),
        );
      default:
        throw ArgumentError.value(
          type,
          'type',
          'unknown host frame discriminant',
        );
    }
  }
}

/// `host/session-added` — lineage anchor, product origin, project cwd, and
/// blank bit; fires at session/created so blank is constantly true there.
class SessionAddedFrame extends HostFrame {
  /// Creates the frame.
  const SessionAddedFrame({
    required this.sessionId,
    required this.blank,
    this.parentSessionId,
    this.origin,
    this.cwd,
    this.agentPreset,
  });

  @override
  String get typeWire => 'host/session-added';

  /// New session id.
  final SessionId sessionId;

  /// Derived conversation-not-started bit (true at creation).
  final bool blank;

  /// Fork/spawn parent when the session has one.
  final String? parentSessionId;

  /// `'subagent'` when spawned as a subagent.
  final String? origin;

  /// Project working directory.
  final String? cwd;

  /// Declared agent preset when present.
  final String? agentPreset;
}

/// `host/session-removed` — the session left the live registry.
class SessionRemovedFrame extends HostFrame {
  /// Creates the frame.
  const SessionRemovedFrame({required this.sessionId});

  @override
  String get typeWire => 'host/session-removed';

  /// Removed session.
  final SessionId sessionId;
}

/// `host/session-status` — running flip; also how clients clear `blank`.
class SessionStatusFrame extends HostFrame {
  /// Creates the frame.
  const SessionStatusFrame({required this.sessionId, required this.running});

  @override
  String get typeWire => 'host/session-status';

  /// Owning session.
  final SessionId sessionId;

  /// Whether the attached agent is currently running.
  final bool running;
}

/// `host/agent-error` — live failure with no turn position.
class AgentErrorFrame extends HostFrame {
  /// Creates the frame.
  const AgentErrorFrame({required this.sessionId, required this.message});

  @override
  String get typeWire => 'host/agent-error';

  /// Failing session.
  final SessionId sessionId;

  /// Failure text.
  final String message;
}

/// `host/workspace-changed` — full new workspace snapshot after every durable
/// mutation; client upserts, `workspace.list` re-baselines on reconnect.
class WorkspaceChangedFrame extends HostFrame {
  /// Creates the frame.
  const WorkspaceChangedFrame({required this.workspace});

  @override
  String get typeWire => 'host/workspace-changed';

  /// Raw `WorkspaceView` JSON.
  final Map<String, Object?> workspace;
}

/// `host/workspace-removed` — committed registration deletion; never implies
/// directory or session-log deletion.
class WorkspaceRemovedFrame extends HostFrame {
  /// Creates the frame.
  const WorkspaceRemovedFrame({required this.workspaceId});

  @override
  String get typeWire => 'host/workspace-removed';

  /// Removed workspace id.
  final String workspaceId;
}

/// `host/workspace-order-changed` — complete durable registry order.
class WorkspaceOrderChangedFrame extends HostFrame {
  /// Creates the frame.
  const WorkspaceOrderChangedFrame({required this.workspaceIds});

  @override
  String get typeWire => 'host/workspace-order-changed';

  /// Ordered workspace ids.
  final List<String> workspaceIds;
}

/// `host/archived-sessions-changed` — full archive set after every durable
/// change (same full-snapshot posture as [WorkspaceChangedFrame]).
class ArchivedSessionsChangedFrame extends HostFrame {
  /// Creates the frame.
  const ArchivedSessionsChangedFrame({required this.archivedSessionIds});

  @override
  String get typeWire => 'host/archived-sessions-changed';

  /// Complete archived-session id set.
  final List<String> archivedSessionIds;
}

/// `host/remote-event` — one allowlisted host cordis event forwarded verbatim;
/// no projection, redaction, or renaming applies on this path.
class RemoteEventFrame extends HostFrame {
  /// Creates the frame.
  const RemoteEventFrame({required this.event, required this.args});

  @override
  String get typeWire => 'host/remote-event';

  /// Host's own event name.
  final String event;

  /// Event argument list owned by the emitting package's Events declaration.
  final List<Object?> args;
}

/// `stream/error` on the host stream.
class HostStreamErrorFrame extends HostFrame {
  /// Creates the frame.
  const HostStreamErrorFrame({required this.error});

  @override
  String get typeWire => 'stream/error';

  /// The failure folded into the RPC error model.
  final RpcError error;
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String)
    throw ArgumentError.value(value, key, 'must be a string');
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int)
    throw ArgumentError.value(value, key, 'must be an integer');
  return value;
}

bool _requireBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool)
    throw ArgumentError.value(value, key, 'must be a boolean');
  return value;
}

Map<String, Object?> _requireMap(Map<String, Object?> json, String key) {
  final value = json[key];
  // jsonDecode produces Map<String, dynamic>, which fails an `is
  // Map<String, Object?>` check; coerce at the wire boundary instead.
  if (value is! Map) throw ArgumentError.value(value, key, 'must be an object');
  return Map<String, Object?>.from(value);
}

List<Object?> _requireList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>)
    throw ArgumentError.value(value, key, 'must be an array');
  return value;
}
