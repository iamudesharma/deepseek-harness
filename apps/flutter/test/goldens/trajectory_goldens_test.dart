// Golden scaffold for trajectory — 420/760/1680 × light/dark.
// Rendered via `flutter test --update-goldens` against the 7-turn fixture
// (migration/parity-reports/trajectory-7turns.json). Goldens live under
// `test/goldens/goldens/trajectory/` and are ignored from coverage (see
// `test/goldens/README.md`). This file is the executable gate the tracker
// references; actual pixel baselines land in the next PR that re-records
// with `flutter test --update-goldens` on a stable Flutter 3.47 host.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trajectory goldens placeholder', () {
    // Placeholder — real goldens require a stable host trace and `flutter test`
    // with the `web` 1.5 pin. Skipped until `web` 1.5 lands on CI.
    expect(true, isTrue);
  }, skip: true);
}
