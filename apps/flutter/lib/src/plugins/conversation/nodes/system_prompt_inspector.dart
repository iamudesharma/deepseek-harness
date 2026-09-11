/// System-prompt inspector — Dart port of React
/// `packages/client/ui-conversation/src/client/contract/system-prompt.ts`
/// (`inspectSystemPrompt`).
///
/// Immutable system-only interpretation of the loaded surface: replacement
/// positions inherit their start endpoint (not chronological seq); unknown
/// older endpoint order withholds the prompt until prepend replay resolves
/// it; the effective prompt is the last non-empty surviving node.
library;

import '../../../core/session/session_event_map.dart';

/// One positioned system node: the surface position it folds at plus the
/// interpreted prompt facts. Mirrors `PositionedSystem` + `SystemPromptNode`.
class InspectedSystemPrompt {
  /// Creates the interpreted node.
  const InspectedSystemPrompt({
    required this.seq,
    required this.time,
    required this.turn,
    required this.step,
    required this.text,
    required this.update,
  });

  /// Owning event seq.
  final int seq;

  /// Event wall time.
  final int time;

  /// Turn number from the event payload.
  final int turn;

  /// Step number from the event payload.
  final int step;

  /// Exact model-visible text with original line breaks.
  final String text;

  /// Whether this event updates an already-shown prompt (append while a
  /// previous node carries non-empty text).
  final bool update;
}

/// One node with its inherited surface position.
class PositionedSystemPrompt {
  /// Creates the positioned node.
  const PositionedSystemPrompt({required this.position, required this.node});

  /// Surface position (inherited from the replaced start endpoint).
  final int position;

  /// Interpreted prompt facts.
  final InspectedSystemPrompt node;
}

/// Prompt facts at one log prefix. Earlier instances stay valid for
/// historical cards.
class SystemPromptState {
  /// Creates the state.
  const SystemPromptState({
    required this.firstSeq,
    required this.uncertain,
    required this.nodes,
    required this.replacements,
    this.effective,
    this.introduced,
  });

  /// Earliest relevant loaded event.
  final int firstSeq;

  /// Missing endpoint order: the prompt is unavailable until prepend replay
  /// supplies it.
  final bool uncertain;

  /// Loaded system nodes in surface order, including empty dormant nodes.
  final List<PositionedSystemPrompt> nodes;

  /// Surviving replacement endpoints mapped to inherited positions.
  final Map<int, int> replacements;

  /// Effective prompt and its change origin; null means unavailable.
  final InspectedSystemPrompt? effective;

  /// System event at this position, if any.
  final InspectedSystemPrompt? introduced;
}

/// Extracts model-visible text from a `system/message` payload: `message`
/// content text blocks joined (mirrors the inspector's `flatMap`).
String inspectSystemPromptText(Map<String, Object?> data) {
  final message = data['message'];
  if (message is! Map) return '';
  final content = message['content'];
  if (content is! List) return '';
  final parts = <String>[];
  for (final block in content) {
    if (block is Map && block['type'] == 'text') {
      final text = block['text'];
      if (text is String) parts.add(text);
    }
  }
  return parts.join('');
}

/// Surface position of the effective prompt, for row anchoring (React
/// positions inherit the replaced start endpoint, not chronological seq).
/// Null when the effective node has no position (withheld/removed).
int? effectivePosition(SystemPromptState state) {
  final effective = state.effective;
  if (effective == null) return null;
  for (final item in state.nodes) {
    if (identical(item.node, effective)) return item.position;
  }
  return null;
}

/// Applies one system event or positional replacement without retaining
/// ordinary messages. Mirrors Host/React `inspectSystemPrompt` exactly:
/// unknown older endpoints wipe to uncertain; replacements inherit the
/// start endpoint and prune covered nodes; `update` marks appends that
/// follow a shown prompt; empty text records removal.
/// @param previous - interpretation at the preceding relevant event (null
/// for the first).
/// @param envelope - system message or surface replacement event.
/// @returns the new immutable system facts.
SystemPromptState inspectSystemPrompt(
  SystemPromptState? previous,
  SessionEventEnvelope envelope,
) {
  final op = envelope.isSurfaceEligible ? envelope.surfaceOp : null;
  final firstSeq = previous?.firstSeq ?? envelope.seq;
  var nodes = previous?.nodes ?? const <PositionedSystemPrompt>[];
  var replacements = previous?.replacements ?? const <int, int>{};
  bool unknownEndpoint(int seq) =>
      seq < firstSeq && !replacements.containsKey(seq);
  final uncertain =
      (previous?.uncertain ?? false) ||
      (op != null &&
          op.isReplace &&
          (unknownEndpoint(op.startSeq!) || unknownEndpoint(op.endSeq!)));
  if (uncertain) {
    return SystemPromptState(
      firstSeq: firstSeq,
      uncertain: true,
      nodes: const [],
      replacements: const {},
    );
  }
  var position = envelope.seq;
  if (op != null && op.isReplace) {
    position = replacements[op.startSeq!] ?? op.startSeq!;
    final end = replacements[op.endSeq!] ?? op.endSeq!;
    nodes = nodes
        .where((item) => item.position < position || item.position > end)
        .toList();
    final retained = Map<int, int>.fromEntries(
      replacements.entries.where(
        (e) => e.value < position || e.value > end,
      ),
    );
    retained[envelope.seq] = position;
    replacements = Map.unmodifiable(retained);
  }
  InspectedSystemPrompt? introduced;
  if (envelope.type == 'system/message') {
    final data = envelope.data;
    introduced = InspectedSystemPrompt(
      seq: envelope.seq,
      time: envelope.time,
      turn: data['turn'] is int ? data['turn'] as int : 0,
      step: data['step'] is int ? data['step'] as int : 0,
      text: inspectSystemPromptText(data),
      update: op != null &&
          !op.isReplace &&
          (previous?.nodes.any((item) => item.node.text.isNotEmpty) ?? false),
    );
  }
  if (introduced != null) {
    nodes = [
      ...nodes,
      PositionedSystemPrompt(position: position, node: introduced),
    ]..sort((a, b) => a.position.compareTo(b.position));
  }
  InspectedSystemPrompt? surviving;
  for (final item in nodes) {
    if (item.node.text.isNotEmpty) surviving = item.node;
  }
  InspectedSystemPrompt? previousSurviving;
  if (previous != null) {
    for (final item in previous.nodes) {
      if (item.node.text.isNotEmpty) previousSurviving = item.node;
    }
  }
  final InspectedSystemPrompt? effective;
  if (surviving == null) {
    effective = null;
  } else if (identical(surviving, previousSurviving)) {
    effective = previous?.effective;
  } else if (introduced != null && identical(introduced, surviving)) {
    effective = introduced;
  } else {
    effective = InspectedSystemPrompt(
      seq: envelope.seq,
      time: envelope.time,
      turn: surviving.turn,
      step: surviving.step,
      text: surviving.text,
      update: false,
    );
  }
  return SystemPromptState(
    firstSeq: firstSeq,
    uncertain: false,
    nodes: List.unmodifiable(nodes),
    replacements: replacements,
    effective: effective,
    introduced: introduced,
  );
}
