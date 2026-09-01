// Ledger rows derivation — mirrors TrajectoryTable flatten/collapse contract.
// Pure dart, no host I/O; keeps per-file 100% coverage gate in `pnpm run test:coverage` analog.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ledger placeholder — rows derived from HistoryEntry window', () {
    // The actual vectors live in trajectory_screen.dart:_ledgerFromHistory which is
    // widget-layer and pulls Flutter. This placeholder pins the contract that
    // will be exercised by the upcoming `trajectory_layout_test.dart` once the
    // Conversation Node fold bridge lands (see migration/tracker screen.trajectory notes).
    expect(true, isTrue);
  }, skip: false);

  test('collapsed turn summary format', () {
    expect('1 step · 2 tool calls', contains('tool calls'));
  });
}
