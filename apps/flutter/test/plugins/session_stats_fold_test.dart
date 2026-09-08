/// Session stats line tests — window fold math over tail/step nodes.
library;

import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/session_stats_line.dart';
import 'package:flutter_test/flutter_test.dart';

TurnTailNode _tail({
  required int turn,
  int? runMs,
  int? ttftMs,
  TurnTokenUsage? usage,
}) {
  return TurnTailNode(
    key: 'tail-$turn',
    sourceSeqs: [turn],
    turn: turn,
    seq: turn,
    time: turn,
    runMs: runMs,
    ttftMs: ttftMs,
    tokenUsage: usage,
  );
}

StepGroupNode _group(int turn, int step) {
  return StepGroupNode(
    key: 'group-$turn-$step',
    sourceSeqs: [turn],
    turn: turn,
    step: step,
    children: const [],
    summary: '',
    settled: true,
  );
}

const _usage = TurnTokenUsage(
  uncachedInputTokens: 70000,
  outputTokens: 9000,
  totalTokens: 79000,
  cacheReadTokens: 60000,
  cacheWriteTokens: 1000,
);

void main() {
  test('empty window folds to zeros', () {
    const stats = WindowStats(
      turns: 0,
      steps: 0,
      llmMs: 0,
      toolMs: 0,
      ttftMs: 0,
      ttftSteps: 0,
      decodeMs: 0,
      decodeTokens: 0,
    );
    final folded = deriveWindowStats(const []);
    expect(folded.turns, stats.turns);
    expect(folded.steps, stats.steps);
    expect(folded.llmMs, 0);
    expect(aggregateSessionTokenUsage(const []), isNull);
  });

  test('tails and groups fold counts, timings, and decode', () {
    final stats = deriveWindowStats([
      _tail(turn: 1, runMs: 30000, ttftMs: 5000, usage: _usage),
      _tail(turn: 2, runMs: 5200, ttftMs: 5100, usage: _usage),
      _group(1, 1),
      _group(2, 1),
    ]);
    expect(stats.turns, 2);
    expect(stats.steps, 2);
    expect(stats.llmMs, 35200);
    expect(stats.toolMs, 0);
    expect(stats.ttftSteps, 2);
    expect(stats.ttftMs, 10100);
    // Decode per tail = runMs - ttftMs (both present): 25000 + 100.
    expect(stats.decodeMs, 25100);
    expect(stats.decodeTokens, 18000);
  });

  test('usage aggregates with the all-or-nothing bucket rule', () {
    final usage = aggregateSessionTokenUsage([
      _tail(turn: 1, usage: _usage),
      _tail(turn: 2, usage: _usage),
    ])!;
    expect(usage.billedInputTokens, 2 * (70000 + 60000 + 1000));
    expect(usage.outputTokens, 18000);
    expect(usage.cacheReadTokens, 120000);

    // One tail without cache buckets drops the sums to null (React parity).
    const partial = TurnTokenUsage(
      uncachedInputTokens: 100,
      outputTokens: 10,
      totalTokens: 110,
    );
    final mixed = aggregateSessionTokenUsage([
      _tail(turn: 1, usage: _usage),
      _tail(turn: 2, usage: partial),
    ])!;
    expect(mixed.cacheReadTokens, isNull);
    expect(mixed.outputTokens, 9010);
  });
}
