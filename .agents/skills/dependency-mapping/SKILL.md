---
name: dependency-mapping
description: Use when mapping npm dependencies of migrated React surfaces to Flutter/pub — maintained pub, adapter, custom, or not-applicable decisions with recorded rationale.
---

# Dependency Mapping

1. List npm dependencies per audited package (imports, not dev tooling).
2. Decide per dependency: maintained pub package > adapter > custom > not-applicable; record rationale and the pub version.
3. Hand-rolling is justified only when it deletes owned code and tests; otherwise prefer maintained packages.
4. Platform plugins need both web and macOS stories (conditional imports where desktop-only).
5. Output: migration/audit/dependency-inventory.md sections per package + tracker row updates.
