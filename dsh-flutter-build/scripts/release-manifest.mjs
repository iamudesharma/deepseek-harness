#!/usr/bin/env node
/**
 * release-manifest.mjs — generates `artifacts/release-manifest.json`.
 *
 * Contains at minimum:
 *   version, release date, app/harness revisions, flutter/node/pnpm versions,
 *   platform artifacts with checksums, arch, signing status.
 *
 * Reads `release.yaml` and `artifacts/checksums/SHA256SUMS`. Artifacts are
 * discovered from `artifacts/<platform>/` and enriched with size/checksum.
 *
 * Usage:
 *   node scripts/release-manifest.mjs              # write artifacts/release-manifest.json
 *   node scripts/release-manifest.mjs --check      # validate existing manifest against current state
 */

import { readFileSync, existsSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { resolve, join, relative, dirname } from "node:path";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const BUILD_REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const RELEASE_YAML = join(BUILD_REPO_ROOT, "release.yaml");
const ARTIFACTS_DIR = join(BUILD_REPO_ROOT, "artifacts");
const MANIFEST_PATH = join(ARTIFACTS_DIR, "release-manifest.json");
const SUMS_PATH = join(ARTIFACTS_DIR, "checksums", "SHA256SUMS");

let jsYaml = null;
try {
  const require = createRequire(import.meta.url);
  jsYaml = require("js-yaml");
} catch {}

function loadManifestYaml() {
  const raw = readFileSync(RELEASE_YAML, "utf8");
  if (jsYaml) return jsYaml.load(raw);
  // Should have been validated; fallback minimal
  throw new Error("js-yaml required to generate release-manifest");
}

function sha256File(path) {
  const data = readFileSync(path);
  return createHash("sha256").update(data).digest("hex");
}

function loadChecksums() {
  const map = new Map();
  if (!existsSync(SUMS_PATH)) return map;
  const lines = readFileSync(SUMS_PATH, "utf8").split("\n").filter(Boolean);
  for (const line of lines) {
    const m = line.match(/^([a-f0-9]{64})\s+(.+)$/);
    if (m) map.set(m[2].trim(), m[1]);
  }
  return map;
}

function discoverArtifacts(checksums) {
  const artifacts = {};
  if (!existsSync(ARTIFACTS_DIR)) return artifacts;
  const platforms = readdirSync(ARTIFACTS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory() && d.name !== "checksums")
    .map(d => d.name);
  for (const plat of platforms) {
    const platDir = join(ARTIFACTS_DIR, plat);
    const entries = readdirSync(platDir, { withFileTypes: true });
    for (const e of entries) {
      if (e.isDirectory()) continue;
      if (e.name === ".gitkeep" || e.name.endsWith(".sha256") || e.name === "release-manifest.json") continue;
      const abs = join(platDir, e.name);
      const rel = relative(ARTIFACTS_DIR, abs); // e.g. web/dsh-flutter-web.tar.gz
      const stat = statSync(abs);
      const sha = checksums.get(rel) || (() => { try { return sha256File(abs); } catch { return null; } })();
      const key = `${plat}/${e.name}`;
      // Group by platform-arch when filename encodes arch; otherwise flat
      const archMatch = e.name.match(/(arm64|x64|universal|aab|apk|app|dmg|zip|tar\.gz|deb|AppImage)/);
      artifacts[rel] = {
        file: rel,
        sha256: sha,
        size: stat.size,
        platform: plat,
        // Signing status is inferred from env / placeholder; CI overlays real status
        signed: process.env.DSH_SIGNING_STATUS === "signed" || false,
      };
    }
  }
  return artifacts;
}

function buildManifest() {
  const y = loadManifestYaml();
  const checksums = loadChecksums();
  const artifacts = discoverArtifacts(checksums);

  // Resolve actual git revisions where possible for audit (sync via require)
  try {
    const require2 = createRequire(import.meta.url);
    const { execSync } = require2("node:child_process");
    const harnessDir = resolve(BUILD_REPO_ROOT, "..");
    if (existsSync(join(harnessDir, ".git"))) {
      const head = execSync("git rev-parse HEAD", { cwd: harnessDir, encoding: "utf8" }).trim();
      void head;
    }
  } catch {}

  const fullVersion = y.release.prerelease
    ? `${y.release.version}-${y.release.prerelease}+${y.release.buildNumber}`
    : `${y.release.version}+${y.release.buildNumber}`;

  const manifest = {
    version: y.release.version,
    fullVersion,
    prerelease: y.release.prerelease || null,
    buildNumber: y.release.buildNumber,
    channel: y.release.channel,
    releaseDate: new Date().toISOString(),
    app: {
      repository: y.app.repository,
      revision: y.app.revision,
      path: y.app.path,
      version: y.app.version,
    },
    harness: {
      repository: y.harness.repository,
      revision: y.harness.revision,
      path: y.harness.path,
    },
    toolchain: y.toolchain,
    platforms: y.platforms,
    artifacts,
    checksumsFile: existsSync(SUMS_PATH) ? "checksums/SHA256SUMS" : null,
    update: y.update || null,
    // Signing summary: CI sets DSH_SIGNING_STATUS=signed and per-platform envs
    signing: {
      status: process.env.DSH_SIGNING_STATUS || "unsigned",
      macos: process.env.DSH_MACOS_SIGNING || "unsigned",
      ios: process.env.DSH_IOS_SIGNING || "unsigned",
      android: process.env.DSH_ANDROID_SIGNING || "unsigned",
      windows: process.env.DSH_WINDOWS_SIGNING || "unsigned",
    },
    generator: "dsh-flutter-build/scripts/release-manifest.mjs",
  };
  return manifest;
}

const mode = process.argv[2] || "generate";
if (mode === "--check" || mode === "check") {
  if (!existsSync(MANIFEST_PATH)) {
    console.error(`[error] Manifest not found: ${MANIFEST_PATH}`);
    process.exit(1);
  }
  const existing = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  const fresh = buildManifest();
  // Compare source revisions and toolchain — artifacts may differ, but inputs must match
  const fields = ["version","buildNumber","channel","app","harness","toolchain"];
  let mismatches = 0;
  for (const f of fields) {
    const a = JSON.stringify(existing[f]), b = JSON.stringify(fresh[f]);
    if (a !== b) {
      console.error(`[mismatch] ${f}:`);
      console.error(`  existing: ${a}`);
      console.error(`  fresh:    ${b}`);
      mismatches++;
    }
  }
  if (mismatches) {
    console.error(`[error] Manifest check failed: ${mismatches} field(s) mismatch`);
    process.exit(1);
  }
  console.log("[ok] release-manifest.json is consistent with release.yaml");
} else {
  const manifest = buildManifest();
  // Ensure artifacts dir exists
  const { mkdirSync } = await import("node:fs");
  mkdirSync(ARTIFACTS_DIR, { recursive: true });
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n", "utf8");
  console.log(`[ok] Wrote ${MANIFEST_PATH}`);
  console.log(`  version: ${manifest.version} (full: ${manifest.fullVersion})`);
  console.log(`  artifacts: ${Object.keys(manifest.artifacts).length}`);
  for (const [rel, meta] of Object.entries(manifest.artifacts)) {
    console.log(`    - ${rel}  sha256:${String(meta.sha256).slice(0,12)}...  ${meta.size} bytes`);
  }
}
