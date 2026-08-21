---
name: flutter-test-generation
description: Use when generating tests for migrated Flutter code — mirrors web's three-tier testing (unit/widget/integration) to validate screens, navigation, responsiveness, API interactions, and platform-specific behavior before marking Tested → Verified.
---

# Flutter Test Generation — Testing & Verification Skill

Generate tests that mirror web's three-tier system and gate tracker progression.

## Tier mapping

| Web tier | Flutter equivalent | Command |
|----------|-------------------|---------|
| Unit / data layer (`runtime` object layer) | Dart pure unit tests for controllers, pure functions `computeColumns`, Typert clients | `flutter test test/unit` |
| Component (`test:gui` jsdom, 100% per-file) | Widget tests via `testWidgets` + `ProviderContainer` | `flutter test test/features` |
| Assembled (`test:web` replay + `test:e2e` real-API) | `integration_test` on `chrome` (web) and `macos` + replay fixtures | `flutter test integration_test -d chrome` |

## Workflow

### 1. Determine scope

For tracker item `id`, read `source` + `tests` from `migration/migration-tracker.json` and collect owning web specs (`packages/client/<name>/tests/*.client.spec.tsx`).

### 2. Generate tests

#### Unit (controller / pure)

```dart
// apps/flutter/test/unit/layout_controller_test.dart
void main() {
  test('setSidebar updates state', () {
    final c = ProviderContainer();
    c.read(layoutProvider.notifier).setSidebar(300);
    expect(c.read(layoutProvider).sidebar, 300);
  });
  test('computeColumns matches web fixture', () {
    expect(computeColumns(1200, 280, 360), equals(Columns(sidebar:280, details:360)));
  });
}
```

#### Widget (presentation, mirrors `test:gui`)

```dart
testWidgets('ConversationComposer sends on Enter', (tester) async {
  final container = ProviderContainer(overrides: [sessionProvider.overrideWith((ref, id) => fakeSession)]);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: ConversationComposer())));
  await tester.enterText(find.byType(TextField), 'hello');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  expect(container.read(composerProvider).draft, isEmpty);
  verify(mockConnection.send).called(1);
});
```

* Use `ProviderContainer` factories (mirrors `createXXXStore().create()`), plain stubs for framework hooks, no render machinery.
* Assert user-visible behavior, not class names or render counts (per `packages/client/AGENTS.md:Testing`).

#### Integration (assembled, mirrors `test:web` / `test:e2e`)

* Replay fixtures under `apps/flutter/integration_test/fixtures/` derived from `apps/web/tests/snapshots/*` and `SessionEventMap` sequences
* Drive real `dsh web` host when `DEEPSEEK_API_KEY` present, else replay mode self-skips (same as web)

### 3. Coverage

```sh
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
# Gate: 100% per-file for migrated lib/src/features/<scope>/**/*.dart
```

Use `// coverage:ignore-file` with reason for genuinely unreachable defensive arms (like `/* v8 ignore */` in web).

### 4. Responsiveness & platform

* Pump at multiple sizes: `tester.view.physicalSize = Size(400,800)`
* Override `TargetPlatform.macOS` + `kIsWeb` via test binding; assert `PlatformMenuBar` vs `HtmlElementView`.

### 5. Advance tracker

On passing tier for scope:

```json
{ "id": "...", "status": "Tested", "tests": ["apps/flutter/test/features/<feature>/*_test.dart"] }
```

`Verified` only after `flutter-parity-check` also passes.

## Anti-patterns

* Do not copy jsdom `document` behavior — use `tester` gestures and `ProviderContainer`
* Do not lower coverage thresholds — keep per-file 100% inside migrated scope
* Do not claim Verified without parity + coverage evidence
