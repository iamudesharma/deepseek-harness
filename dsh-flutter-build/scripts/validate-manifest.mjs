#!/usr/bin/env node
/**
 * validate-manifest.mjs — validates `release.yaml` for reproducibility and
 * version hygiene. Uses js-yaml when available, falls back to minimal parser.
 *
 * Exit 0 on success, non-zero with diagnostics on failure.
 */

import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const YAML_PATH = resolve(REPO_ROOT, "release.yaml");
const VERSION_PATH = resolve(REPO_ROOT, "VERSION");

let jsYaml = null;
try {
  const require = createRequire(import.meta.url);
  jsYaml = require("js-yaml");
} catch {}

let manifest;
try {
  const raw = readFileSync(YAML_PATH, "utf8");
  if (jsYaml) manifest = jsYaml.load(raw);
  else manifest = parseMinimalYaml(raw);
} catch (e) {
  console.error(`[error] Failed to load ${YAML_PATH}: ${e.message}`);
  process.exit(1);
}

function parseMinimalYaml(raw) {
  const lines = raw.split("\n");
  const obj = {};
  let stack = [obj];
  let indentStack = [0];
  for (const line of lines) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    const indent = line.match(/^(\s*)/)[1].length;
    const m = line.trim().match(/^([A-Za-z0-9_.-]+):\s*(.*)$/);
    if (!m) continue;
    const key = m[1];
    let val = m[2].trim();
    // Strip inline comments not inside quotes
    if (val.includes("#") && !val.startsWith('"') && !val.startsWith("'")) {
      val = val.split("#")[0].trim();
    }
    if (val === "" || val === "{}") val = {};
    else if (val === "null") val = null;
    else if (val === "true") val = true;
    else if (val === "false") val = false;
    else if (/^-?\d+$/.test(val)) val = parseInt(val, 10);
    else if (/^".*"$/.test(val) || /^'.*'$/.test(val)) val = val.slice(1, -1);
    else if (val === "[]") val = [];
    else if (val.startsWith("[")) {
      // Simple array like ["arm64", "x64"]
      try { val = JSON.parse(val.replace(/'/g, '"')); } catch {}
    }
    while (indentStack[indentStack.length - 1] >= indent && stack.length > 1) {
      stack.pop();
      indentStack.pop();
    }
    const parent = stack[stack.length - 1];
    if (typeof val === "object" && val !== null && !Array.isArray(val) && Object.keys(val).length === 0) {
      parent[key] = {};
      stack.push(parent[key]);
      indentStack.push(indent);
    } else {
      parent[key] = val;
    }
  }
  return obj;
}

const errors = [];
const warnings = [];

function err(msg) { errors.push(msg); }
function warn(msg) { warnings.push(msg); }

function isSemver(v) {
  return /^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(String(v));
}
function isSha(v) {
  return /^[0-9a-f]{7,40}$/.test(String(v));
}

if (!manifest) err("Manifest is empty or failed to parse");
else {
  if (manifest.formatVersion !== 1) err(`formatVersion must be 1 (got ${manifest.formatVersion})`);

  if (!manifest.release) err("Missing `release` section");
  else {
    if (!isSemver(manifest.release.version)) err(`release.version must be semver (got ${manifest.release.version})`);
    if (!["stable","beta","nightly","dev"].includes(manifest.release.channel)) err(`release.channel must be stable|beta|nightly|dev (got ${manifest.release.channel})`);
    if (!Number.isInteger(manifest.release.buildNumber) || manifest.release.buildNumber < 1) err("release.buildNumber must be integer >=1");
  }

  for (const k of ["app","harness"]) {
    const s = manifest[k];
    if (!s) { err(`Missing \`${k}\` section`); continue; }
    if (!s.repository) err(`${k}.repository is required`);
    if (!isSha(s.revision)) err(`${k}.revision must be a git SHA (got ${s.revision})`);
  }
  if (manifest.app) {
    if (!isSemver(manifest.app.version)) err(`app.version must be semver (got ${manifest.app.version})`);
    if (manifest.release && manifest.app.version !== manifest.release.version) {
      warn(`app.version (${manifest.app.version}) != release.version (${manifest.release.version}) — they should match`);
    }
    if (manifest.app.buildNumber !== manifest.release?.buildNumber) {
      warn(`app.buildNumber (${manifest.app.buildNumber}) != release.buildNumber (${manifest.release.buildNumber})`);
    }
  }

  const tc = manifest.toolchain;
  if (!tc) err("Missing `toolchain` section");
  else {
    if (!tc.flutter?.version) err("toolchain.flutter.version is required");
    if (!tc.dart?.version) err("toolchain.dart.version is required");
    if (!tc.node?.version) err("toolchain.node.version is required");
    if (!tc.pnpm?.version) err("toolchain.pnpm.version is required");
    if (tc.flutter?.channel && !["stable","beta","dev","master","main"].includes(tc.flutter.channel)) {
      err(`toolchain.flutter.channel invalid: ${tc.flutter.channel}`);
    }
    if (tc.node?.range && !/[\d]/.test(tc.node.range)) err(`toolchain.node.range looks invalid: ${tc.node.range}`);
  }

  if (!manifest.platforms) err("Missing `platforms` section");
  else {
    for (const [name, cfg] of Object.entries(manifest.platforms)) {
      if (typeof cfg.enabled !== "boolean") err(`platforms.${name}.enabled must be boolean`);
    }
    if (manifest.platforms.macos?.bundleId && !/^[A-Za-z0-9.-]+$/.test(manifest.platforms.macos.bundleId)) {
      err(`platforms.macos.bundleId invalid: ${manifest.platforms.macos.bundleId}`);
    }
    if (manifest.platforms.ios?.bundleId && !/^[A-Za-z0-9.-]+$/.test(manifest.platforms.ios.bundleId)) {
      err(`platforms.ios.bundleId invalid: ${manifest.platforms.ios.bundleId}`);
    }
    if (manifest.platforms.android?.applicationId && !/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(manifest.platforms.android.applicationId)) {
      err(`platforms.android.applicationId invalid: ${manifest.platforms.android.applicationId}`);
    }
  }

  if (manifest.branding?.icons) {
    for (const [k,v] of Object.entries(manifest.branding.icons)) {
      if (typeof v !== "string" || v.length === 0) err(`branding.icons.${k} must be non-empty string`);
    }
  }
}

if (existsSync(VERSION_PATH)) {
  const v = readFileSync(VERSION_PATH, "utf8").trim();
  if (manifest?.release?.version && v !== manifest.release.version) {
    err(`VERSION file (${v}) != release.version (${manifest.release.version})`);
  }
  if (!isSemver(v)) err(`VERSION file is not semver: ${v}`);
}

if (warnings.length) {
  for (const w of warnings) console.warn(`[warn] ${w}`);
}
if (errors.length) {
  for (const e of errors) console.error(`[error] ${e}`);
  console.error(`\nManifest validation failed: ${errors.length} error(s)`);
  process.exit(1);
}
console.log("[ok] release.yaml validation passed");
if (warnings.length) console.log(`[ok] with ${warnings.length} warning(s)`);
