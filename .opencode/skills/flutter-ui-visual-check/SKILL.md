---
name: flutter-ui-visual-check
description: Use when performing pixel-level visual validation between web and Flutter — golden tests, screenshot comparison, responsive breakpoints, and theme token fidelity.
---

# Flutter UI Visual Check — Pixel Validation Skill

Validates visual fidelity at the pixel level, complementing behavioral parity.

## Workflow

### 1. Establish baselines

* Web baseline: `apps/web` Playwright screenshots at canonical viewports:
  * Desktop 1200×800, Tablet 768×800, Mobile 400×800, Ultra 1600×900
  * Light + dark theme (`ui-theme`)
  * With and without session (blank vs active `detailsSession` guard)

```sh
DSH_SNAPSHOT=replay pnpm exec playwright test --project=chromium --reporter=html
ls apps/web/tests/snapshots/**/*.expected.json
```

* Flutter baseline: `flutter test --update-goldens` in `apps/flutter/test/goldens/`

### 2. Golden test pattern

```dart
// apps/flutter/test/goldens/button_test.dart
void main() {
  testWidgets('DsButton golden - light desktop', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: DsButton(...))));
    await expectLater(find.byType(DsButton), matchesGoldenFile('goldens/button_light.png'));
  });
  testWidgets('DsButton golden - dark narrow', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: darkTheme, home: DsButton(...))));
    await expectLater(find.byType(DsButton), matchesGoldenFile('goldens/button_dark_narrow.png'));
  });
}
```

* One golden per `tracker` component per viewport+theme combination
* Use `golden_toolkit` for multi-screen load: `multiScreenGolden(tester, 'button', devices: [...])`

### 3. Diff thresholds

* Exact: text, icons, spacing (token-anchored) — 0% tolerance
* Antialiasing/rounding — ≤ 0.1% diff (CanvasKit vs Skia)
* Approve diffs by viewing `flutter test --update-goldens` diff image, not by blindly updating

### 4. Theme fidelity checks

* No literal colors outside `dsw_tokens.dart` — enforced by `grep -R "Color(0x" apps/flutter/lib --exclude="dsw_tokens.dart"`
* TextTheme fidelity: `katex` math & markdown rendering vs Flutter `flutter_markdown` + `flutter_math_fork` — snapshot markdown fixture

### 5. Responsive goldens

* Same widget at 3 breakpoints → 3 goldens; verify `computeColumns` Dart port matches `ui-layout` expectation

### 6. Report

Append to `migration/parity-reports/<item>.md` visual section:

```md
Visual: 3/3 goldens PASS (desktop light 0.01%, tablet 0.00%, mobile 0.03%)
Theme tokens: PASS (0 literals)
```

## Anti-patterns

* Do not run goldens on different OS without `SkiaGold` — use Linux CI goldens as source
* Do not snapshot whole page — snapshot per-component for actionable diffs
