---
name: verification
description: Verification gates — pnpm build/typecheck/lint/test, flutter analyze/test/build, tracker; classify failures P0/P1/P2/P3/UNKNOWN, never mislabel environment.
---

# Verification — Shared Skill

## Host gates

```
pnpm build              # tsdown bundles Host + Client (tsc + tsdown)
pnpm typecheck          # tsc -b tsconfig.client.json (contracts)
pnpm lint               # oxlint
pnpm test               # vitest unit
pnpm test:coverage      # per-file 100% (CI gate)
pnpm test:snapshot      # keyless recorded-session replay
verify-cordis-catalog --check
verify-flutter-tracker --check  # migration/migration-tracker.json
```

## Flutter gates

```
flutter analyze --no-pub
flutter test                    # focused P0/P1 + full
flutter build web --wasm --release
flutter build macos --debug
flutter build apk --debug       # Android (iOS/Windows/Linux only on request)

# Platforms Always verified:
# Web, macOS, Android
```

Flutter parity surfaces always verified:

```
session list/create/page/follow, prompt, queue, tool events, reasoning,
approvals, questions, workspaces, models, agent presets, settings, attachments,
reconnect, remote.mux, authentication
```

## Tracker

```
pnpm run verify-flutter-tracker --check
pnpm run verify-flutter-tracker          # writes migration/migration-tracker.json evidence
```

Every non-trivial model/product-user-visible change updates a keyless recorded-session snapshot.

## Failure classification

- **PRODUCT:** real parity or contract failure (fix code)
- **TEST:** stale expected output (re-record with `DSH_SNAPSHOT=refresh` if contract legit)
- **ENVIRONMENT:** missing `DEEPSEEK_API_KEY`, `flutter` not installed, network — **never label without evidence**
- **UPSTREAM:** upstream introduced breaking change (needs migration)
- **FLUTTER:** Flutter-only regression
- **TOOLCHAIN:** `pnpm`/`flutter`/`tsc` version drift

## Execution

- `pnpm upstream:verify` runs `build:lib` + `typecheck:contracts-ready` + `flutter analyze` + `verify-flutter-tracker` (CI full: `build`, `lint`, `test`, `test:coverage`).
- Focused tests for every `P0`/`P1` mismatch (e.g., `flutter test test/features/session/live_history_test.dart`).
- Add contract tests when `api-diff.json`/`stream-diff.json` changes.

## Never

- Skip tests because a failure “looks unrelated.”
- Label a failure `ENVIRONMENT` without proving `which flutter` / `env` / `DEEPSEEK_API_KEY`.
- Hide a transport error as an empty UI state.

## Severity mapping

- **P0:** runtime-breaking → blocks `flutter-sync` merge
- **P1:** feature-breaking/degraded
- **P2:** compat risk
- **P3:** informational
- **UNKNOWN:** must be classified before final merge (gates `Verified`)
