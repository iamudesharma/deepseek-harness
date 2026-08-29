# Tools

This directory houses build-repo owned verification helpers that are not part of
the product app but support reproducibility and release hygiene.

Current helpers live in `../scripts/`:

- `validate-manifest.mjs` — `release.yaml` schema / semver / SHA / platform checks
- `release-manifest.mjs` — `artifacts/release-manifest.json` generation + `--check`
- `bootstrap.sh` — toolchain + lockfile + revision pinning
- `version.sh` — `release.yaml` ↔ `pubspec.yaml` + `VERSION` propagation
- `checksum.sh` — SHA-256 generation / verification
- `test-build-repo.sh` — §27 build-repo tests (manifest, revisions, artifacts, etc.)
- `reproducibility.sh` — two-build comparison with documented non-determinism

Add new helpers here when they are reusable across scripts and CI, keeping
`scripts/` as the user-facing CLI surface and `tools/` as the library / test
support layer.
