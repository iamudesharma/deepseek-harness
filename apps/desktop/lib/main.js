import ro, { readFile, writeFile } from "node:fs/promises";
import cr, { basename, delimiter, dirname, extname, isAbsolute, join, normalize, posix, relative, resolve, sep, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { BrowserWindow, Menu, app, dialog, ipcMain, protocol } from "electron";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import Kt, { closeSync, constants, copyFileSync, cpSync, existsSync, fsyncSync, ftruncateSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, unlinkSync, writeFileSync, writeSync } from "node:fs";
import { valid } from "semver";
import { DatabaseSync } from "node:sqlite";
import Qr, { EventEmitter } from "events";
import I from "fs";
import { EventEmitter as EventEmitter$1, once } from "node:events";
import Cs, { Readable, Writable } from "node:stream";
import { StringDecoder } from "node:string_decoder";
import js, { dirname as dirname$1, parse } from "path";
import zi from "assert";
import { Buffer as Buffer$1 } from "buffer";
import * as Ps from "zlib";
import en from "zlib";
import co from "node:assert";
import electronUpdater from "electron-updater";
//#region ../../packages/util/home-paths/src/index.ts
/** Directory name for the default DeepSeek Harness home under the OS home. */
const DSH_HOME_DIR_NAME = ".dsh";
/** Environment variable that overrides the default DeepSeek Harness home. */
const DSH_HOME_ENV = "DSH_HOME";
/**
* Resolve the default DeepSeek Harness home using Node's platform path rules.
* @returns the absolute default harness home path.
*/
function defaultDshHome() {
	return join(homedir(), DSH_HOME_DIR_NAME);
}
/**
* Expand supported tilde prefixes against the operating-system home.
* @param path - configured path that may begin with `~`, `~/`, or `~\`.
* @returns the expanded path, or the original value when no supported prefix is present.
*/
function expandHomePath(path) {
	if (path === "~") return homedir();
	if (path.startsWith("~/") || path.startsWith("~\\")) return join(homedir(), path.slice(2));
	return path;
}
/**
* Resolve the single-root DeepSeek Harness home.
*
* Precedence, highest first: an explicit configured path, `$DSH_HOME`, then
* `~/.dsh`. The harness keeps all user data under one root. An empty or
* whitespace-only `$DSH_HOME` is treated as unset, so a blank override never
* resolves the home to the current working directory.
* @param configured - explicit harness-home override, which has highest precedence.
* @param env - environment mapping used to read `DSH_HOME`.
* @returns the normalized absolute harness home path.
*/
function resolveDshHome(configured, env = process.env) {
	const fromEnv = env[DSH_HOME_ENV];
	return resolve(expandHomePath(configured ?? (fromEnv !== void 0 && fromEnv.trim().length > 0 ? fromEnv : defaultDshHome())));
}
//#endregion
//#region lib/types/paths.js
/** Filesystem ownership for the Electron-managed desktop installation. */
/**
* Resolve every Electron-owned path without changing the shared data roots.
* @param dshHome - Harness home shared with npm-installed dsh.
* @returns immutable desktop path set.
*/
function resolveDesktopPaths(dshHome = resolveDshHome()) {
	const root = join(dshHome, "desktop");
	const pnpm = join(root, "pnpm");
	return {
		root,
		profile: join(dshHome, "profiles", "desktop"),
		staging: join(root, "staging"),
		rollback: join(root, "rollback", "profile"),
		pending: join(root, "pending.json"),
		lock: join(root, "lock"),
		pnpm: {
			root: pnpm,
			store: join(pnpm, "store"),
			cache: join(pnpm, "cache"),
			state: join(pnpm, "state"),
			config: join(pnpm, "config"),
			home: join(pnpm, "home")
		}
	};
}
//#endregion
//#region lib/types/core-package-set.js
/** Signed local npm package set that supplies the Desktop-owned dsh runtime and private Host. */
/** Descriptor copied beside every Desktop profile's local core tarballs. */
const DESKTOP_PACKAGE_SET_FILE = "desktop-packages.json";
/** Profile-relative directory containing immutable core npm tarballs. */
const DESKTOP_PACKAGES_DIR = "desktop-packages";
/** Private package installed beside dsh to boot the Desktop Host process. */
const DESKTOP_HOST_PACKAGE = "@deepseek-ai/dsh-desktop-host";
const PACKAGE_NAME_PATTERN$1 = /^(?:@[a-z0-9][a-z0-9._~-]*\/[a-z0-9][a-z0-9._~-]*|[a-z0-9][a-z0-9._~-]*)$/u;
const VERSION_PATTERN$1 = /^[0-9A-Za-z][0-9A-Za-z.+_-]*$/u;
const FILE_PATTERN = /^[a-zA-Z0-9][a-zA-Z0-9._-]*\.tgz$/u;
const INTEGRITY_PATTERN = /^sha512-[A-Za-z0-9+/]+={0,2}$/u;
const DSH_PACKAGE$1 = "@deepseek-ai/dsh";
const RELEASE_PACKAGES = [DSH_PACKAGE$1, DESKTOP_HOST_PACKAGE];
function isRecord$3(value) {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}
/**
* Validate package-set data read from a release artifact or active profile.
* @param value - Parsed descriptor JSON.
* @param expectedReleaseVersion - Required dsh and Desktop Host version when validating one release.
* @returns The normalized package set in deterministic name order.
*/
function parseDesktopCorePackageSet(value, expectedReleaseVersion) {
	if (!isRecord$3(value) || value.schemaVersion !== 1 || !Array.isArray(value.packages)) throw new Error("desktop package set: invalid descriptor");
	const packages = value.packages.map((entry) => {
		if (!isRecord$3(entry) || typeof entry.name !== "string" || !PACKAGE_NAME_PATTERN$1.test(entry.name) || typeof entry.version !== "string" || !VERSION_PATTERN$1.test(entry.version) || typeof entry.file !== "string" || !FILE_PATTERN.test(entry.file) || typeof entry.bytes !== "number" || !Number.isSafeInteger(entry.bytes) || entry.bytes < 0 || typeof entry.integrity !== "string" || !INTEGRITY_PATTERN.test(entry.integrity)) throw new Error("desktop package set: invalid package record");
		return {
			name: entry.name,
			version: entry.version,
			file: entry.file,
			bytes: entry.bytes,
			integrity: entry.integrity
		};
	});
	const names = new Set(packages.map((entry) => entry.name));
	const files = new Set(packages.map((entry) => entry.file));
	if (names.size !== packages.length || files.size !== packages.length) throw new Error("desktop package set: duplicate package name or filename");
	const sorted = [...packages].sort((left, right) => left.name.localeCompare(right.name));
	if (JSON.stringify(sorted) !== JSON.stringify(packages)) throw new Error("desktop package set: packages must be sorted by name");
	for (const name of RELEASE_PACKAGES) {
		const entry = packages.find((candidate) => candidate.name === name);
		if (entry === void 0) throw new Error(`desktop package set: missing ${name}`);
		if (expectedReleaseVersion !== void 0 && entry.version !== expectedReleaseVersion) throw new Error(`desktop package set: ${name}@${entry.version} does not match Desktop ${expectedReleaseVersion}`);
	}
	return {
		schemaVersion: 1,
		packages
	};
}
/** Read and structurally validate one profile's core package descriptor. */
function readDesktopCorePackageSet(projectDir, expectedReleaseVersion) {
	const path = join(projectDir, DESKTOP_PACKAGE_SET_FILE);
	let value;
	try {
		value = JSON.parse(readFileSync(path, "utf8"));
	} catch (error) {
		throw new Error(`desktop package set: failed to read ${path}: ${String(error)}`);
	}
	return parseDesktopCorePackageSet(value, expectedReleaseVersion);
}
/** Return the project-relative `file:` spec for one local core tarball. */
function desktopCorePackageSpec(record) {
	return `file:./${DESKTOP_PACKAGES_DIR}/${record.file}`;
}
/** Return the exact pnpm override map that keeps every core package off registries. */
function desktopCorePackageOverrides(packageSet) {
	return Object.fromEntries(packageSet.packages.map((record) => [record.name, desktopCorePackageSpec(record)]));
}
/** Return the local direct dependency spec for the dsh package. */
function desktopDshPackageSpec(packageSet) {
	const record = packageSet.packages.find((entry) => entry.name === DSH_PACKAGE$1);
	if (record === void 0) throw new Error(`desktop package set: missing ${DSH_PACKAGE$1}`);
	return desktopCorePackageSpec(record);
}
/**
* Verify every local tarball and reject extra package files before pnpm executes them.
* @param projectDir - Seed or profile directory containing the package set.
* @param expectedReleaseVersion - Exact dsh and Desktop Host version bound to Electron.
* @returns The verified package set.
*/
function verifyDesktopCorePackageSet(projectDir, expectedReleaseVersion) {
	const packageSet = readDesktopCorePackageSet(projectDir, expectedReleaseVersion);
	const packageDir = join(projectDir, DESKTOP_PACKAGES_DIR);
	const expectedFiles = packageSet.packages.map((entry) => entry.file).sort();
	let actualFiles;
	try {
		actualFiles = readdirSync(packageDir).sort();
	} catch (error) {
		throw new Error(`desktop package set: failed to read ${packageDir}: ${String(error)}`);
	}
	if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) throw new Error("desktop package set: package directory does not match its descriptor");
	for (const record of packageSet.packages) {
		const path = join(packageDir, record.file);
		if (!existsSync(path) || !lstatSync(path).isFile()) throw new Error(`desktop package set: ${record.file} is not a regular file`);
		const body = readFileSync(path);
		const integrity = `sha512-${createHash("sha512").update(body).digest("base64")}`;
		if (body.byteLength !== record.bytes || integrity !== record.integrity) throw new Error(`desktop package set: integrity check failed for ${record.file}`);
	}
	return packageSet;
}
//#endregion
//#region lib/types/host-protocol.js
/** Maximum raw body bytes carried by one data frame. */
const DESKTOP_PIPE_CHUNK_BYTES = 64 * 1024;
const FRAME_MAGIC = 1146308659;
const FRAME_HEADER_BYTES = 13;
const MAX_CONTROL_PAYLOAD_BYTES = 1024 * 1024;
const REQUEST_FRAME_START = 1;
const REQUEST_FRAME_DATA = 2;
const REQUEST_FRAME_END = 3;
const REQUEST_FRAME_CANCEL = 4;
const RESPONSE_FRAME_START = 1;
const RESPONSE_FRAME_DATA = 2;
const RESPONSE_FRAME_END = 3;
const RESPONSE_FRAME_ERROR = 4;
function isRecord$2(value) {
	return typeof value === "object" && value !== null;
}
function isHeaders(value) {
	return Array.isArray(value) && value.every((header) => Array.isArray(header) && header.length === 2 && typeof header[0] === "string" && typeof header[1] === "string");
}
function assertStreamId(streamId) {
	if (!Number.isInteger(streamId) || streamId < 1 || streamId > 4294967295) throw new Error(`dsh desktop: invalid pipe stream id ${String(streamId)}`);
}
function encodeFrame(type, streamId, payload) {
	assertStreamId(streamId);
	const limit = type === REQUEST_FRAME_DATA ? DESKTOP_PIPE_CHUNK_BYTES : MAX_CONTROL_PAYLOAD_BYTES;
	if (payload.byteLength > limit) throw new Error(`dsh desktop: request pipe frame exceeds the ${String(limit)}-byte limit`);
	const frame = Buffer.allocUnsafe(FRAME_HEADER_BYTES + payload.byteLength);
	frame.writeUInt32BE(FRAME_MAGIC, 0);
	frame.writeUInt8(type, 4);
	frame.writeUInt32BE(streamId, 5);
	frame.writeUInt32BE(payload.byteLength, 9);
	payload.copy(frame, FRAME_HEADER_BYTES);
	return frame;
}
function encodeJsonFrame(type, streamId, value) {
	return encodeFrame(type, streamId, Buffer.from(JSON.stringify(value), "utf8"));
}
/** Encode the metadata opening one request stream. */
function encodeDesktopRequestStart(streamId, request) {
	return encodeJsonFrame(REQUEST_FRAME_START, streamId, request);
}
/** Encode one bounded raw request-body chunk. */
function encodeDesktopRequestData(streamId, data) {
	return encodeFrame(REQUEST_FRAME_DATA, streamId, Buffer.from(data));
}
/** Encode normal request-body completion. */
function encodeDesktopRequestEnd(streamId) {
	return encodeFrame(REQUEST_FRAME_END, streamId, Buffer.alloc(0));
}
/** Encode cancellation of one request and its response. */
function encodeDesktopRequestCancel(streamId) {
	return encodeFrame(REQUEST_FRAME_CANCEL, streamId, Buffer.alloc(0));
}
/** Incrementally decode validated response frames from the Host byte pipe. */
var DesktopHostResponseDecoder = class {
	buffer = Buffer.alloc(0);
	/**
	* Append bytes and return every complete response frame.
	* @param chunk - next bytes read from the Host response pipe.
	* @returns complete frames in pipe order.
	*/
	push(chunk) {
		this.buffer = this.buffer.byteLength === 0 ? chunk : Buffer.concat([this.buffer, chunk]);
		const frames = [];
		for (;;) {
			const frame = this.next();
			if (frame === void 0) return frames;
			frames.push(frame);
		}
	}
	/** Reject EOF that splits a frame. */
	finish() {
		if (this.buffer.byteLength !== 0) throw new Error("dsh desktop: Host response pipe ended inside a frame");
	}
	next() {
		if (this.buffer.byteLength < FRAME_HEADER_BYTES) return void 0;
		if (this.buffer.readUInt32BE(0) !== FRAME_MAGIC) throw new Error("dsh desktop: invalid Host response frame marker");
		const rawType = this.buffer.readUInt8(4);
		const streamId = this.buffer.readUInt32BE(5);
		const payloadLength = this.buffer.readUInt32BE(9);
		assertStreamId(streamId);
		const limit = rawType === RESPONSE_FRAME_DATA ? DESKTOP_PIPE_CHUNK_BYTES : MAX_CONTROL_PAYLOAD_BYTES;
		if (payloadLength > limit) throw new Error(`dsh desktop: Host response frame exceeds the ${String(limit)}-byte limit`);
		const frameLength = FRAME_HEADER_BYTES + payloadLength;
		if (this.buffer.byteLength < frameLength) return void 0;
		const payload = this.buffer.subarray(FRAME_HEADER_BYTES, frameLength);
		this.buffer = this.buffer.subarray(frameLength);
		switch (rawType) {
			case RESPONSE_FRAME_START: return this.parseStart(streamId, payload);
			case RESPONSE_FRAME_DATA: return {
				type: "data",
				streamId,
				data: payload
			};
			case RESPONSE_FRAME_END:
				if (payloadLength !== 0) throw new Error("dsh desktop: Host response end frame carried a payload");
				return {
					type: "end",
					streamId
				};
			case RESPONSE_FRAME_ERROR: return this.parseError(streamId, payload);
			default: throw new Error(`dsh desktop: unknown Host response frame type ${String(rawType)}`);
		}
	}
	parseStart(streamId, payload) {
		const value = this.parseJson(payload, "start");
		if (!isRecord$2(value) || !Number.isInteger(value.status) || value.status < 100 || value.status > 599 || !isHeaders(value.headers) || typeof value.hasBody !== "boolean") throw new Error("dsh desktop: invalid Host response start payload");
		return {
			type: "start",
			streamId,
			status: value.status,
			headers: value.headers,
			hasBody: value.hasBody
		};
	}
	parseError(streamId, payload) {
		const value = this.parseJson(payload, "error");
		if (!isRecord$2(value) || typeof value.message !== "string") throw new Error("dsh desktop: invalid Host response error payload");
		return {
			type: "error",
			streamId,
			message: value.message
		};
	}
	parseJson(payload, subject) {
		try {
			return JSON.parse(payload.toString("utf8"));
		} catch (error) {
			throw new Error(`dsh desktop: Host response ${subject} payload is not JSON: ${error instanceof Error ? error.message : String(error)}`);
		}
	}
};
//#endregion
//#region lib/types/release.js
/** Immutable version identity shared by one Electron shell and its dsh seed. */
function isRecord$1(value) {
	return typeof value === "object" && value !== null;
}
/** Validate release data read from an installed or packaged filesystem resource. */
function parseDesktopRelease(value) {
	if (!isRecord$1(value) || value.schemaVersion !== 1 || typeof value.version !== "string" || valid(value.version) === null || value.hostProtocolVersion !== 3 || typeof value.nodeVersion !== "string" || valid(value.nodeVersion) === null || typeof value.pnpmVersion !== "string" || valid(value.pnpmVersion) === null) throw new Error("dsh desktop: invalid desktop release metadata");
	return {
		schemaVersion: 1,
		version: value.version,
		hostProtocolVersion: 3,
		nodeVersion: value.nodeVersion,
		pnpmVersion: value.pnpmVersion
	};
}
//#endregion
//#region ../../node_modules/.pnpm/tar@7.5.22/node_modules/tar/dist/esm/index.min.js
var zr = Object.defineProperty;
var Ur = (s, t) => {
	for (var e in t) zr(s, e, {
		get: t[e],
		enumerable: !0
	});
};
var Ds = typeof process == "object" && process ? process : {
	stdout: null,
	stderr: null
}, Wr = (s) => !!s && typeof s == "object" && (s instanceof A || s instanceof Cs || Gr(s) || Zr(s)), Gr = (s) => !!s && typeof s == "object" && s instanceof EventEmitter$1 && typeof s.pipe == "function" && s.pipe !== Cs.Writable.prototype.pipe, Zr = (s) => !!s && typeof s == "object" && s instanceof EventEmitter$1 && typeof s.write == "function" && typeof s.end == "function", Q = Symbol("EOF"), J = Symbol("maybeEmitEnd"), nt = Symbol("emittedEnd"), De = Symbol("emittingEnd"), qt = Symbol("emittedError"), Ne = Symbol("closed"), Ns = Symbol("read"), Ae = Symbol("flush"), As = Symbol("flushChunk"), z = Symbol("encoding"), Mt = Symbol("decoder"), g = Symbol("flowing"), Qt = Symbol("paused"), Bt = Symbol("resume"), b = Symbol("buffer"), N = Symbol("pipes"), _ = Symbol("bufferLength"), bi = Symbol("bufferPush"), Ie = Symbol("bufferShift"), L = Symbol("objectMode"), S = Symbol("destroyed"), _i = Symbol("error"), Oi = Symbol("emitData"), Is = Symbol("emitEnd"), Ti = Symbol("emitEnd2"), Z = Symbol("async"), xi = Symbol("abort"), Ce = Symbol("aborted"), Jt = Symbol("signal"), Rt = Symbol("dataListeners"), C = Symbol("discarded"), jt = (s) => Promise.resolve().then(s), Yr = (s) => s(), Kr = (s) => s === "end" || s === "finish" || s === "prefinish", Vr = (s) => s instanceof ArrayBuffer || !!s && typeof s == "object" && s.constructor && s.constructor.name === "ArrayBuffer" && s.byteLength >= 0, $r = (s) => !Buffer.isBuffer(s) && ArrayBuffer.isView(s), Fe = class {
	src;
	dest;
	opts;
	ondrain;
	constructor(t, e, i) {
		this.src = t, this.dest = e, this.opts = i, this.ondrain = () => t[Bt](), this.dest.on("drain", this.ondrain);
	}
	unpipe() {
		this.dest.removeListener("drain", this.ondrain);
	}
	proxyErrors(t) {}
	end() {
		this.unpipe(), this.opts.end && this.dest.end();
	}
}, Li = class extends Fe {
	unpipe() {
		this.src.removeListener("error", this.proxyErrors), super.unpipe();
	}
	constructor(t, e, i) {
		super(t, e, i), this.proxyErrors = (r) => this.dest.emit("error", r), t.on("error", this.proxyErrors);
	}
}, Xr = (s) => !!s.objectMode, qr = (s) => !s.objectMode && !!s.encoding && s.encoding !== "buffer", A = class extends EventEmitter$1 {
	[g] = !1;
	[Qt] = !1;
	[N] = [];
	[b] = [];
	[L];
	[z];
	[Z];
	[Mt];
	[Q] = !1;
	[nt] = !1;
	[De] = !1;
	[Ne] = !1;
	[qt] = null;
	[_] = 0;
	[S] = !1;
	[Jt];
	[Ce] = !1;
	[Rt] = 0;
	[C] = !1;
	writable = !0;
	readable = !0;
	constructor(...t) {
		let e = t[0] || {};
		if (super(), e.objectMode && typeof e.encoding == "string") throw new TypeError("Encoding and objectMode may not be used together");
		Xr(e) ? (this[L] = !0, this[z] = null) : qr(e) ? (this[z] = e.encoding, this[L] = !1) : (this[L] = !1, this[z] = null), this[Z] = !!e.async, this[Mt] = this[z] ? new StringDecoder(this[z]) : null, e && e.debugExposeBuffer === !0 && Object.defineProperty(this, "buffer", { get: () => this[b] }), e && e.debugExposePipes === !0 && Object.defineProperty(this, "pipes", { get: () => this[N] });
		let { signal: i } = e;
		i && (this[Jt] = i, i.aborted ? this[xi]() : i.addEventListener("abort", () => this[xi]()));
	}
	get bufferLength() {
		return this[_];
	}
	get encoding() {
		return this[z];
	}
	set encoding(t) {
		throw new Error("Encoding must be set at instantiation time");
	}
	setEncoding(t) {
		throw new Error("Encoding must be set at instantiation time");
	}
	get objectMode() {
		return this[L];
	}
	set objectMode(t) {
		throw new Error("objectMode must be set at instantiation time");
	}
	get async() {
		return this[Z];
	}
	set async(t) {
		this[Z] = this[Z] || !!t;
	}
	[xi]() {
		this[Ce] = !0, this.emit("abort", this[Jt]?.reason), this.destroy(this[Jt]?.reason);
	}
	get aborted() {
		return this[Ce];
	}
	set aborted(t) {}
	write(t, e, i) {
		if (this[Ce]) return !1;
		if (this[Q]) throw new Error("write after end");
		if (this[S]) return this.emit("error", Object.assign(/* @__PURE__ */ new Error("Cannot call write after a stream was destroyed"), { code: "ERR_STREAM_DESTROYED" })), !0;
		typeof e == "function" && (i = e, e = "utf8"), e || (e = "utf8");
		let r = this[Z] ? jt : Yr;
		if (!this[L] && !Buffer.isBuffer(t)) {
			if ($r(t)) t = Buffer.from(t.buffer, t.byteOffset, t.byteLength);
			else if (Vr(t)) t = Buffer.from(t);
			else if (typeof t != "string") throw new Error("Non-contiguous data written to non-objectMode stream");
		}
		return this[L] ? (this[g] && this[_] !== 0 && this[Ae](!0), this[g] ? this.emit("data", t) : this[bi](t), this[_] !== 0 && this.emit("readable"), i && r(i), this[g]) : t.length ? (typeof t == "string" && !(e === this[z] && !this[Mt]?.lastNeed) && (t = Buffer.from(t, e)), Buffer.isBuffer(t) && this[z] && (t = this[Mt].write(t)), this[g] && this[_] !== 0 && this[Ae](!0), this[g] ? this.emit("data", t) : this[bi](t), this[_] !== 0 && this.emit("readable"), i && r(i), this[g]) : (this[_] !== 0 && this.emit("readable"), i && r(i), this[g]);
	}
	read(t) {
		if (this[S]) return null;
		if (this[C] = !1, this[_] === 0 || t === 0 || t && t > this[_]) return this[J](), null;
		this[L] && (t = null), this[b].length > 1 && !this[L] && (this[b] = [this[z] ? this[b].join("") : Buffer.concat(this[b], this[_])]);
		let e = this[Ns](t || null, this[b][0]);
		return this[J](), e;
	}
	[Ns](t, e) {
		if (this[L]) this[Ie]();
		else {
			let i = e;
			t === i.length || t === null ? this[Ie]() : typeof i == "string" ? (this[b][0] = i.slice(t), e = i.slice(0, t), this[_] -= t) : (this[b][0] = i.subarray(t), e = i.subarray(0, t), this[_] -= t);
		}
		return this.emit("data", e), !this[b].length && !this[Q] && this.emit("drain"), e;
	}
	end(t, e, i) {
		return typeof t == "function" && (i = t, t = void 0), typeof e == "function" && (i = e, e = "utf8"), t !== void 0 && this.write(t, e), i && this.once("end", i), this[Q] = !0, this.writable = !1, (this[g] || !this[Qt]) && this[J](), this;
	}
	[Bt]() {
		this[S] || (!this[Rt] && !this[N].length && (this[C] = !0), this[Qt] = !1, this[g] = !0, this.emit("resume"), this[b].length ? this[Ae]() : this[Q] ? this[J]() : this.emit("drain"));
	}
	resume() {
		return this[Bt]();
	}
	pause() {
		this[g] = !1, this[Qt] = !0, this[C] = !1;
	}
	get destroyed() {
		return this[S];
	}
	get flowing() {
		return this[g];
	}
	get paused() {
		return this[Qt];
	}
	[bi](t) {
		this[L] ? this[_] += 1 : this[_] += t.length, this[b].push(t);
	}
	[Ie]() {
		return this[L] ? this[_] -= 1 : this[_] -= this[b][0].length, this[b].shift();
	}
	[Ae](t = !1) {
		do		;
while (this[As](this[Ie]()) && this[b].length);
		!t && !this[b].length && !this[Q] && this.emit("drain");
	}
	[As](t) {
		return this.emit("data", t), this[g];
	}
	pipe(t, e) {
		if (this[S]) return t;
		this[C] = !1;
		let i = this[nt];
		return e = e || {}, t === Ds.stdout || t === Ds.stderr ? e.end = !1 : e.end = e.end !== !1, e.proxyErrors = !!e.proxyErrors, i ? e.end && t.end() : (this[N].push(e.proxyErrors ? new Li(this, t, e) : new Fe(this, t, e)), this[Z] ? jt(() => this[Bt]()) : this[Bt]()), t;
	}
	unpipe(t) {
		let e = this[N].find((i) => i.dest === t);
		e && (this[N].length === 1 ? (this[g] && this[Rt] === 0 && (this[g] = !1), this[N] = []) : this[N].splice(this[N].indexOf(e), 1), e.unpipe());
	}
	addListener(t, e) {
		return this.on(t, e);
	}
	on(t, e) {
		let i = super.on(t, e);
		if (t === "data") this[C] = !1, this[Rt]++, !this[N].length && !this[g] && this[Bt]();
		else if (t === "readable" && this[_] !== 0) super.emit("readable");
		else if (Kr(t) && this[nt]) super.emit(t), this.removeAllListeners(t);
		else if (t === "error" && this[qt]) {
			let r = e;
			this[Z] ? jt(() => r.call(this, this[qt])) : r.call(this, this[qt]);
		}
		return i;
	}
	removeListener(t, e) {
		return this.off(t, e);
	}
	off(t, e) {
		let i = super.off(t, e);
		return t === "data" && (this[Rt] = this.listeners("data").length, this[Rt] === 0 && !this[C] && !this[N].length && (this[g] = !1)), i;
	}
	removeAllListeners(t) {
		let e = super.removeAllListeners(t);
		return (t === "data" || t === void 0) && (this[Rt] = 0, !this[C] && !this[N].length && (this[g] = !1)), e;
	}
	get emittedEnd() {
		return this[nt];
	}
	[J]() {
		!this[De] && !this[nt] && !this[S] && this[b].length === 0 && this[Q] && (this[De] = !0, this.emit("end"), this.emit("prefinish"), this.emit("finish"), this[Ne] && this.emit("close"), this[De] = !1);
	}
	emit(t, ...e) {
		let i = e[0];
		if (t !== "error" && t !== "close" && t !== S && this[S]) return !1;
		if (t === "data") return !this[L] && !i ? !1 : this[Z] ? (jt(() => this[Oi](i)), !0) : this[Oi](i);
		if (t === "end") return this[Is]();
		if (t === "close") {
			if (this[Ne] = !0, !this[nt] && !this[S]) return !1;
			let n = super.emit("close");
			return this.removeAllListeners("close"), n;
		} else if (t === "error") {
			this[qt] = i, super.emit(_i, i);
			let n = !this[Jt] || this.listeners("error").length ? super.emit("error", i) : !1;
			return this[J](), n;
		} else if (t === "resume") {
			let n = super.emit("resume");
			return this[J](), n;
		} else if (t === "finish" || t === "prefinish") {
			let n = super.emit(t);
			return this.removeAllListeners(t), n;
		}
		let r = super.emit(t, ...e);
		return this[J](), r;
	}
	[Oi](t) {
		for (let i of this[N]) i.dest.write(t) === !1 && this.pause();
		let e = this[C] ? !1 : super.emit("data", t);
		return this[J](), e;
	}
	[Is]() {
		return this[nt] ? !1 : (this[nt] = !0, this.readable = !1, this[Z] ? (jt(() => this[Ti]()), !0) : this[Ti]());
	}
	[Ti]() {
		if (this[Mt]) {
			let e = this[Mt].end();
			if (e) {
				for (let i of this[N]) i.dest.write(e);
				this[C] || super.emit("data", e);
			}
		}
		for (let e of this[N]) e.end();
		let t = super.emit("end");
		return this.removeAllListeners("end"), t;
	}
	async collect() {
		let t = Object.assign([], { dataLength: 0 });
		this[L] || (t.dataLength = 0);
		let e = this.promise();
		return this.on("data", (i) => {
			t.push(i), this[L] || (t.dataLength += i.length);
		}), await e, t;
	}
	async concat() {
		if (this[L]) throw new Error("cannot concat in objectMode");
		let t = await this.collect();
		return this[z] ? t.join("") : Buffer.concat(t, t.dataLength);
	}
	async promise() {
		return new Promise((t, e) => {
			this.on(S, () => e(/* @__PURE__ */ new Error("stream destroyed"))), this.on("error", (i) => e(i)), this.on("end", () => t());
		});
	}
	[Symbol.asyncIterator]() {
		this[C] = !1;
		let t = !1, e = async () => (this.pause(), t = !0, {
			value: void 0,
			done: !0
		});
		return {
			next: () => {
				if (t) return e();
				let r = this.read();
				if (r !== null) return Promise.resolve({
					done: !1,
					value: r
				});
				if (this[Q]) return e();
				let n, o, h = (d) => {
					this.off("data", a), this.off("end", l), this.off(S, c), e(), o(d);
				}, a = (d) => {
					this.off("error", h), this.off("end", l), this.off(S, c), this.pause(), n({
						value: d,
						done: !!this[Q]
					});
				}, l = () => {
					this.off("error", h), this.off("data", a), this.off(S, c), e(), n({
						done: !0,
						value: void 0
					});
				}, c = () => h(/* @__PURE__ */ new Error("stream destroyed"));
				return new Promise((d, y) => {
					o = y, n = d, this.once(S, c), this.once("error", h), this.once("end", l), this.once("data", a);
				});
			},
			throw: e,
			return: e,
			[Symbol.asyncIterator]() {
				return this;
			},
			[Symbol.asyncDispose]: async () => {}
		};
	}
	[Symbol.iterator]() {
		this[C] = !1;
		let t = !1, e = () => (this.pause(), this.off(_i, e), this.off(S, e), this.off("end", e), t = !0, {
			done: !0,
			value: void 0
		}), i = () => {
			if (t) return e();
			let r = this.read();
			return r === null ? e() : {
				done: !1,
				value: r
			};
		};
		return this.once("end", e), this.once(_i, e), this.once(S, e), {
			next: i,
			throw: e,
			return: e,
			[Symbol.iterator]() {
				return this;
			},
			[Symbol.dispose]: () => {}
		};
	}
	destroy(t) {
		if (this[S]) return t ? this.emit("error", t) : this.emit(S), this;
		this[S] = !0, this[C] = !0, this[b].length = 0, this[_] = 0;
		let e = this;
		return typeof e.close == "function" && !this[Ne] && e.close(), t ? this.emit("error", t) : this.emit(S), this;
	}
	static get isStream() {
		return Wr;
	}
};
var Jr = I.writev, ht = Symbol("_autoClose"), H = Symbol("_close"), te = Symbol("_ended"), m = Symbol("_fd"), Ni = Symbol("_finished"), tt = Symbol("_flags"), Ai = Symbol("_flush"), ki = Symbol("_handleChunk"), vi = Symbol("_makeBuf"), ie = Symbol("_mode"), ke = Symbol("_needDrain"), Ut = Symbol("_onerror"), Ht = Symbol("_onopen"), Ii = Symbol("_onread"), Pt = Symbol("_onwrite"), at = Symbol("_open"), U = Symbol("_path"), ot = Symbol("_pos"), Y = Symbol("_queue"), zt = Symbol("_read"), Ci = Symbol("_readSize"), j = Symbol("_reading"), ee = Symbol("_remain"), Fi = Symbol("_size"), ve = Symbol("_write"), gt = Symbol("_writing"), Me = Symbol("_defaultFlag"), bt = Symbol("_errored"), _t = class extends A {
	[bt] = !1;
	[m];
	[U];
	[Ci];
	[j] = !1;
	[Fi];
	[ee];
	[ht];
	constructor(t, e) {
		if (e = e || {}, super(e), this.readable = !0, this.writable = !1, typeof t != "string") throw new TypeError("path must be a string");
		this[bt] = !1, this[m] = typeof e.fd == "number" ? e.fd : void 0, this[U] = t, this[Ci] = e.readSize || 16 * 1024 * 1024, this[j] = !1, this[Fi] = typeof e.size == "number" ? e.size : Infinity, this[ee] = this[Fi], this[ht] = typeof e.autoClose == "boolean" ? e.autoClose : !0, typeof this[m] == "number" ? this[zt]() : this[at]();
	}
	get fd() {
		return this[m];
	}
	get path() {
		return this[U];
	}
	write() {
		throw new TypeError("this is a readable stream");
	}
	end() {
		throw new TypeError("this is a readable stream");
	}
	[at]() {
		I.open(this[U], "r", (t, e) => this[Ht](t, e));
	}
	[Ht](t, e) {
		t ? this[Ut](t) : (this[m] = e, this.emit("open", e), this[zt]());
	}
	[vi]() {
		return Buffer.allocUnsafe(Math.min(this[Ci], this[ee]));
	}
	[zt]() {
		if (!this[j]) {
			this[j] = !0;
			let t = this[vi]();
			if (t.length === 0) return process.nextTick(() => this[Ii](null, 0, t));
			I.read(this[m], t, 0, t.length, null, (e, i, r) => this[Ii](e, i, r));
		}
	}
	[Ii](t, e, i) {
		this[j] = !1, t ? this[Ut](t) : this[ki](e, i) && this[zt]();
	}
	[H]() {
		if (this[ht] && typeof this[m] == "number") {
			let t = this[m];
			this[m] = void 0, I.close(t, (e) => e ? this.emit("error", e) : this.emit("close"));
		}
	}
	[Ut](t) {
		this[j] = !0, this[H](), this.emit("error", t);
	}
	[ki](t, e) {
		let i = !1;
		return this[ee] -= t, t > 0 && (i = super.write(t < e.length ? e.subarray(0, t) : e)), (t === 0 || this[ee] <= 0) && (i = !1, this[H](), super.end()), i;
	}
	emit(t, ...e) {
		switch (t) {
			case "prefinish":
			case "finish": return !1;
			case "drain": return typeof this[m] == "number" && this[zt](), !1;
			case "error": return this[bt] ? !1 : (this[bt] = !0, super.emit(t, ...e));
			default: return super.emit(t, ...e);
		}
	}
}, Be = class extends _t {
	[at]() {
		let t = !0;
		try {
			this[Ht](null, I.openSync(this[U], "r")), t = !1;
		} finally {
			t && this[H]();
		}
	}
	[zt]() {
		let t = !0;
		try {
			if (!this[j]) {
				this[j] = !0;
				do {
					let e = this[vi](), i = e.length === 0 ? 0 : I.readSync(this[m], e, 0, e.length, null);
					if (!this[ki](i, e)) break;
				} while (!0);
				this[j] = !1;
			}
			t = !1;
		} finally {
			t && this[H]();
		}
	}
	[H]() {
		if (this[ht] && typeof this[m] == "number") {
			let t = this[m];
			this[m] = void 0, I.closeSync(t), this.emit("close");
		}
	}
}, et = class extends Qr {
	readable = !1;
	writable = !0;
	[bt] = !1;
	[gt] = !1;
	[te] = !1;
	[Y] = [];
	[ke] = !1;
	[U];
	[ie];
	[ht];
	[m];
	[Me];
	[tt];
	[Ni] = !1;
	[ot];
	constructor(t, e) {
		e = e || {}, super(e), this[U] = t, this[m] = typeof e.fd == "number" ? e.fd : void 0, this[ie] = e.mode === void 0 ? 438 : e.mode, this[ot] = typeof e.start == "number" ? e.start : void 0, this[ht] = typeof e.autoClose == "boolean" ? e.autoClose : !0;
		let i = this[ot] !== void 0 ? "r+" : "w";
		this[Me] = e.flags === void 0, this[tt] = e.flags === void 0 ? i : e.flags, this[m] === void 0 && this[at]();
	}
	emit(t, ...e) {
		if (t === "error") {
			if (this[bt]) return !1;
			this[bt] = !0;
		}
		return super.emit(t, ...e);
	}
	get fd() {
		return this[m];
	}
	get path() {
		return this[U];
	}
	[Ut](t) {
		this[H](), this[gt] = !0, this.emit("error", t);
	}
	[at]() {
		I.open(this[U], this[tt], this[ie], (t, e) => this[Ht](t, e));
	}
	[Ht](t, e) {
		this[Me] && this[tt] === "r+" && t && t.code === "ENOENT" ? (this[tt] = "w", this[at]()) : t ? this[Ut](t) : (this[m] = e, this.emit("open", e), this[gt] || this[Ai]());
	}
	end(t, e) {
		return t && this.write(t, e), this[te] = !0, !this[gt] && !this[Y].length && typeof this[m] == "number" && this[Pt](null, 0), this;
	}
	write(t, e) {
		return typeof t == "string" && (t = Buffer.from(t, e)), this[te] ? (this.emit("error", /* @__PURE__ */ new Error("write() after end()")), !1) : this[m] === void 0 || this[gt] || this[Y].length ? (this[Y].push(t), this[ke] = !0, !1) : (this[gt] = !0, this[ve](t), !0);
	}
	[ve](t) {
		I.write(this[m], t, 0, t.length, this[ot], (e, i) => this[Pt](e, i));
	}
	[Pt](t, e) {
		t ? this[Ut](t) : (this[ot] !== void 0 && typeof e == "number" && (this[ot] += e), this[Y].length ? this[Ai]() : (this[gt] = !1, this[te] && !this[Ni] ? (this[Ni] = !0, this[H](), this.emit("finish")) : this[ke] && (this[ke] = !1, this.emit("drain"))));
	}
	[Ai]() {
		if (this[Y].length === 0) this[te] && this[Pt](null, 0);
		else if (this[Y].length === 1) this[ve](this[Y].pop());
		else {
			let t = this[Y];
			this[Y] = [], Jr(this[m], t, this[ot], (e, i) => this[Pt](e, i));
		}
	}
	[H]() {
		if (this[ht] && typeof this[m] == "number") {
			let t = this[m];
			this[m] = void 0, I.close(t, (e) => e ? this.emit("error", e) : this.emit("close"));
		}
	}
}, Wt = class extends et {
	[at]() {
		let t;
		if (this[Me] && this[tt] === "r+") try {
			t = I.openSync(this[U], this[tt], this[ie]);
		} catch (e) {
			if (e?.code === "ENOENT") return this[tt] = "w", this[at]();
			throw e;
		}
		else t = I.openSync(this[U], this[tt], this[ie]);
		this[Ht](null, t);
	}
	[H]() {
		if (this[ht] && typeof this[m] == "number") {
			let t = this[m];
			this[m] = void 0, I.closeSync(t), this.emit("close");
		}
	}
	[ve](t) {
		let e = !0;
		try {
			this[Pt](null, I.writeSync(this[m], t, 0, t.length, this[ot])), e = !1;
		} finally {
			if (e) try {
				this[H]();
			} catch {}
		}
	}
};
var jr = new Map([
	["C", "cwd"],
	["f", "file"],
	["z", "gzip"],
	["P", "preservePaths"],
	["U", "unlink"],
	["strip-components", "strip"],
	["stripComponents", "strip"],
	["keep-newer", "newer"],
	["keepNewer", "newer"],
	["keep-newer-files", "newer"],
	["keepNewerFiles", "newer"],
	["k", "keep"],
	["keep-existing", "keep"],
	["keepExisting", "keep"],
	["m", "noMtime"],
	["no-mtime", "noMtime"],
	["p", "preserveOwner"],
	["L", "follow"],
	["h", "follow"],
	["onentry", "onReadEntry"]
]), Fs = (s) => !!s.sync && !!s.file, ks = (s) => !s.sync && !!s.file, vs = (s) => !!s.sync && !s.file, Ms = (s) => !s.sync && !s.file;
var Bs = (s) => !!s.file;
var tn = (s) => {
	return jr.get(s) || s;
}, se = (s = {}) => {
	if (!s) return {};
	let t = {};
	for (let [e, i] of Object.entries(s)) {
		let r = tn(e);
		t[r] = i;
	}
	return t.chmod === void 0 && t.noChmod === !1 && (t.chmod = !0), delete t.noChmod, t;
};
var K = (s, t, e, i, r) => Object.assign((n = [], o, h) => {
	Array.isArray(n) && (o = n, n = {}), typeof o == "function" && (h = o, o = void 0), o = o ? Array.from(o) : [];
	let a = se(n);
	if (r?.(a, o), Fs(a)) {
		if (typeof h == "function") throw new TypeError("callback not supported for sync tar functions");
		return s(a, o);
	} else if (ks(a)) {
		let l = t(a, o);
		return h ? l.then(() => h(), h) : l;
	} else if (vs(a)) {
		if (typeof h == "function") throw new TypeError("callback not supported for sync tar functions");
		return e(a, o);
	} else if (Ms(a)) {
		if (typeof h == "function") throw new TypeError("callback only supported with file option");
		return i(a, o);
	}
	throw new Error("impossible options??");
}, {
	syncFile: s,
	asyncFile: t,
	syncNoFile: e,
	asyncNoFile: i,
	validate: r
});
var sn = en.constants || { ZLIB_VERNUM: 4736 }, M = Object.freeze(Object.assign(Object.create(null), {
	Z_NO_FLUSH: 0,
	Z_PARTIAL_FLUSH: 1,
	Z_SYNC_FLUSH: 2,
	Z_FULL_FLUSH: 3,
	Z_FINISH: 4,
	Z_BLOCK: 5,
	Z_OK: 0,
	Z_STREAM_END: 1,
	Z_NEED_DICT: 2,
	Z_ERRNO: -1,
	Z_STREAM_ERROR: -2,
	Z_DATA_ERROR: -3,
	Z_MEM_ERROR: -4,
	Z_BUF_ERROR: -5,
	Z_VERSION_ERROR: -6,
	Z_NO_COMPRESSION: 0,
	Z_BEST_SPEED: 1,
	Z_BEST_COMPRESSION: 9,
	Z_DEFAULT_COMPRESSION: -1,
	Z_FILTERED: 1,
	Z_HUFFMAN_ONLY: 2,
	Z_RLE: 3,
	Z_FIXED: 4,
	Z_DEFAULT_STRATEGY: 0,
	DEFLATE: 1,
	INFLATE: 2,
	GZIP: 3,
	GUNZIP: 4,
	DEFLATERAW: 5,
	INFLATERAW: 6,
	UNZIP: 7,
	BROTLI_DECODE: 8,
	BROTLI_ENCODE: 9,
	Z_MIN_WINDOWBITS: 8,
	Z_MAX_WINDOWBITS: 15,
	Z_DEFAULT_WINDOWBITS: 15,
	Z_MIN_CHUNK: 64,
	Z_MAX_CHUNK: Infinity,
	Z_DEFAULT_CHUNK: 16384,
	Z_MIN_MEMLEVEL: 1,
	Z_MAX_MEMLEVEL: 9,
	Z_DEFAULT_MEMLEVEL: 8,
	Z_MIN_LEVEL: -1,
	Z_MAX_LEVEL: 9,
	Z_DEFAULT_LEVEL: -1,
	BROTLI_OPERATION_PROCESS: 0,
	BROTLI_OPERATION_FLUSH: 1,
	BROTLI_OPERATION_FINISH: 2,
	BROTLI_OPERATION_EMIT_METADATA: 3,
	BROTLI_MODE_GENERIC: 0,
	BROTLI_MODE_TEXT: 1,
	BROTLI_MODE_FONT: 2,
	BROTLI_DEFAULT_MODE: 0,
	BROTLI_MIN_QUALITY: 0,
	BROTLI_MAX_QUALITY: 11,
	BROTLI_DEFAULT_QUALITY: 11,
	BROTLI_MIN_WINDOW_BITS: 10,
	BROTLI_MAX_WINDOW_BITS: 24,
	BROTLI_LARGE_MAX_WINDOW_BITS: 30,
	BROTLI_DEFAULT_WINDOW: 22,
	BROTLI_MIN_INPUT_BLOCK_BITS: 16,
	BROTLI_MAX_INPUT_BLOCK_BITS: 24,
	BROTLI_PARAM_MODE: 0,
	BROTLI_PARAM_QUALITY: 1,
	BROTLI_PARAM_LGWIN: 2,
	BROTLI_PARAM_LGBLOCK: 3,
	BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING: 4,
	BROTLI_PARAM_SIZE_HINT: 5,
	BROTLI_PARAM_LARGE_WINDOW: 6,
	BROTLI_PARAM_NPOSTFIX: 7,
	BROTLI_PARAM_NDIRECT: 8,
	BROTLI_DECODER_RESULT_ERROR: 0,
	BROTLI_DECODER_RESULT_SUCCESS: 1,
	BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT: 2,
	BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT: 3,
	BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION: 0,
	BROTLI_DECODER_PARAM_LARGE_WINDOW: 1,
	BROTLI_DECODER_NO_ERROR: 0,
	BROTLI_DECODER_SUCCESS: 1,
	BROTLI_DECODER_NEEDS_MORE_INPUT: 2,
	BROTLI_DECODER_NEEDS_MORE_OUTPUT: 3,
	BROTLI_DECODER_ERROR_FORMAT_EXUBERANT_NIBBLE: -1,
	BROTLI_DECODER_ERROR_FORMAT_RESERVED: -2,
	BROTLI_DECODER_ERROR_FORMAT_EXUBERANT_META_NIBBLE: -3,
	BROTLI_DECODER_ERROR_FORMAT_SIMPLE_HUFFMAN_ALPHABET: -4,
	BROTLI_DECODER_ERROR_FORMAT_SIMPLE_HUFFMAN_SAME: -5,
	BROTLI_DECODER_ERROR_FORMAT_CL_SPACE: -6,
	BROTLI_DECODER_ERROR_FORMAT_HUFFMAN_SPACE: -7,
	BROTLI_DECODER_ERROR_FORMAT_CONTEXT_MAP_REPEAT: -8,
	BROTLI_DECODER_ERROR_FORMAT_BLOCK_LENGTH_1: -9,
	BROTLI_DECODER_ERROR_FORMAT_BLOCK_LENGTH_2: -10,
	BROTLI_DECODER_ERROR_FORMAT_TRANSFORM: -11,
	BROTLI_DECODER_ERROR_FORMAT_DICTIONARY: -12,
	BROTLI_DECODER_ERROR_FORMAT_WINDOW_BITS: -13,
	BROTLI_DECODER_ERROR_FORMAT_PADDING_1: -14,
	BROTLI_DECODER_ERROR_FORMAT_PADDING_2: -15,
	BROTLI_DECODER_ERROR_FORMAT_DISTANCE: -16,
	BROTLI_DECODER_ERROR_DICTIONARY_NOT_SET: -19,
	BROTLI_DECODER_ERROR_INVALID_ARGUMENTS: -20,
	BROTLI_DECODER_ERROR_ALLOC_CONTEXT_MODES: -21,
	BROTLI_DECODER_ERROR_ALLOC_TREE_GROUPS: -22,
	BROTLI_DECODER_ERROR_ALLOC_CONTEXT_MAP: -25,
	BROTLI_DECODER_ERROR_ALLOC_RING_BUFFER_1: -26,
	BROTLI_DECODER_ERROR_ALLOC_RING_BUFFER_2: -27,
	BROTLI_DECODER_ERROR_ALLOC_BLOCK_TYPE_TREES: -30,
	BROTLI_DECODER_ERROR_UNREACHABLE: -31
}, sn));
var rn = Buffer$1.concat, zs = Object.getOwnPropertyDescriptor(Buffer$1, "concat"), nn = (s) => s, Bi = zs?.writable === !0 || zs?.set !== void 0 ? (s) => {
	Buffer$1.concat = s ? nn : rn;
} : (s) => {}, Tt = Symbol("_superWrite"), Gt = class extends Error {
	code;
	errno;
	constructor(t, e) {
		super("zlib: " + t.message, { cause: t }), this.code = t.code, this.errno = t.errno, this.code || (this.code = "ZLIB_ERROR"), this.message = "zlib: " + t.message, Error.captureStackTrace(this, e ?? this.constructor);
	}
	get name() {
		return "ZlibError";
	}
}, Pi = Symbol("flushFlag"), re = class extends A {
	#t = !1;
	#i = !1;
	#s;
	#n;
	#r;
	#e;
	#o;
	get sawError() {
		return this.#t;
	}
	get handle() {
		return this.#e;
	}
	get flushFlag() {
		return this.#s;
	}
	constructor(t, e) {
		if (!t || typeof t != "object") throw new TypeError("invalid options for ZlibBase constructor");
		if (super(t), this.#s = t.flush ?? 0, this.#n = t.finishFlush ?? 0, this.#r = t.fullFlushFlag ?? 0, typeof Ps[e] != "function") throw new TypeError("Compression method not supported: " + e);
		try {
			this.#e = new Ps[e](t);
		} catch (i) {
			throw new Gt(i, this.constructor);
		}
		this.#o = (i) => {
			this.#t || (this.#t = !0, this.close(), this.emit("error", i));
		}, this.#e?.on("error", (i) => this.#o(new Gt(i))), this.once("end", () => this.close);
	}
	close() {
		this.#e && (this.#e.close(), this.#e = void 0, this.emit("close"));
	}
	reset() {
		if (!this.#t) return zi(this.#e, "zlib binding closed"), this.#e.reset?.();
	}
	flush(t) {
		this.ended || (typeof t != "number" && (t = this.#r), this.write(Object.assign(Buffer$1.alloc(0), { [Pi]: t })));
	}
	end(t, e, i) {
		return typeof t == "function" && (i = t, e = void 0, t = void 0), typeof e == "function" && (i = e, e = void 0), t && (e ? this.write(t, e) : this.write(t)), this.flush(this.#n), this.#i = !0, super.end(i);
	}
	get ended() {
		return this.#i;
	}
	[Tt](t) {
		return super.write(t);
	}
	write(t, e, i) {
		if (typeof e == "function" && (i = e, e = "utf8"), typeof t == "string" && (t = Buffer$1.from(t, e)), this.#t) return;
		zi(this.#e, "zlib binding closed");
		let r = this.#e._handle, n = r.close;
		r.close = () => {};
		let o = this.#e.close;
		this.#e.close = () => {}, Bi(!0);
		let h;
		try {
			let l = typeof t[Pi] == "number" ? t[Pi] : this.#s;
			h = this.#e._processChunk(t, l), Bi(!1);
		} catch (l) {
			Bi(!1), this.#o(new Gt(l, this.write));
		} finally {
			this.#e && (this.#e._handle = r, r.close = n, this.#e.close = o, this.#e.removeAllListeners("error"));
		}
		this.#e && this.#e.on("error", (l) => this.#o(new Gt(l, this.write)));
		let a;
		if (h) if (Array.isArray(h) && h.length > 0) {
			let l = h[0];
			a = this[Tt](Buffer$1.from(l));
			for (let c = 1; c < h.length; c++) a = this[Tt](h[c]);
		} else a = this[Tt](Buffer$1.from(h));
		return i && i(), a;
	}
}, Pe = class extends re {
	#t;
	#i;
	constructor(t, e) {
		t = t || {}, t.flush = t.flush || M.Z_NO_FLUSH, t.finishFlush = t.finishFlush || M.Z_FINISH, t.fullFlushFlag = M.Z_FULL_FLUSH, super(t, e), this.#t = t.level, this.#i = t.strategy;
	}
	params(t, e) {
		if (!this.sawError) {
			if (!this.handle) throw new Error("cannot switch params when binding is closed");
			if (!this.handle.params) throw new Error("not supported in this implementation");
			if (this.#t !== t || this.#i !== e) {
				this.flush(M.Z_SYNC_FLUSH), zi(this.handle, "zlib binding closed");
				let i = this.handle.flush;
				this.handle.flush = (r, n) => {
					typeof r == "function" && (n = r, r = this.flushFlag), this.flush(r), n?.();
				};
				try {
					this.handle.params(t, e);
				} finally {
					this.handle.flush = i;
				}
				this.handle && (this.#t = t, this.#i = e);
			}
		}
	}
};
var ze = class extends Pe {
	#t;
	constructor(t) {
		super(t, "Gzip"), this.#t = t && !!t.portable;
	}
	[Tt](t) {
		return this.#t ? (this.#t = !1, t[9] = 255, super[Tt](t)) : super[Tt](t);
	}
};
var Ue = class extends Pe {
	constructor(t) {
		super(t, "Unzip");
	}
}, He = class extends re {
	constructor(t, e) {
		t = t || {}, t.flush = t.flush || M.BROTLI_OPERATION_PROCESS, t.finishFlush = t.finishFlush || M.BROTLI_OPERATION_FINISH, t.fullFlushFlag = M.BROTLI_OPERATION_FLUSH, super(t, e);
	}
}, We = class extends He {
	constructor(t) {
		super(t, "BrotliCompress");
	}
}, Ge = class extends He {
	constructor(t) {
		super(t, "BrotliDecompress");
	}
}, Ze = class extends re {
	constructor(t, e) {
		t = t || {}, t.flush = t.flush || M.ZSTD_e_continue, t.finishFlush = t.finishFlush || M.ZSTD_e_end, t.fullFlushFlag = M.ZSTD_e_flush, super(t, e);
	}
}, Ye = class extends Ze {
	constructor(t) {
		super(t, "ZstdCompress");
	}
}, Ke = class extends Ze {
	constructor(t) {
		super(t, "ZstdDecompress");
	}
};
var Us = (s, t) => {
	if (Number.isSafeInteger(s)) s < 0 ? an(s, t) : hn(s, t);
	else throw Error("cannot encode number outside of javascript safe integer range");
	return t;
}, hn = (s, t) => {
	t[0] = 128;
	for (var e = t.length; e > 1; e--) t[e - 1] = s & 255, s = Math.floor(s / 256);
}, an = (s, t) => {
	t[0] = 255;
	var e = !1;
	s = s * -1;
	for (var i = t.length; i > 1; i--) {
		var r = s & 255;
		s = Math.floor(s / 256), e ? t[i - 1] = Ws(r) : r === 0 ? t[i - 1] = 0 : (e = !0, t[i - 1] = Gs(r));
	}
}, Hs = (s) => {
	let t = s[0], e = t === 128 ? cn(s.subarray(1, s.length)) : t === 255 ? ln(s) : null;
	if (e === null) throw Error("invalid base256 encoding");
	if (!Number.isSafeInteger(e)) throw Error("parsed number outside of javascript safe integer range");
	return e;
}, ln = (s) => {
	for (var t = s.length, e = 0, i = !1, r = t - 1; r > -1; r--) {
		var n = Number(s[r]), o;
		i ? o = Ws(n) : n === 0 ? o = n : (i = !0, o = Gs(n)), o !== 0 && (e -= o * Math.pow(256, t - r - 1));
	}
	return e;
}, cn = (s) => {
	for (var t = s.length, e = 0, i = t - 1; i > -1; i--) {
		var r = Number(s[i]);
		r !== 0 && (e += r * Math.pow(256, t - i - 1));
	}
	return e;
}, Ws = (s) => (255 ^ s) & 255, Gs = (s) => (255 ^ s) + 1 & 255;
Ur({}, {
	code: () => Ve,
	isCode: () => ne,
	isName: () => dn,
	name: () => oe,
	normalFsTypes: () => Ui
});
var ne = (s) => oe.has(s), dn = (s) => Ve.has(s), Ui = new Set([
	"0",
	"",
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"D"
]), oe = new Map([
	["0", "File"],
	["", "OldFile"],
	["1", "Link"],
	["2", "SymbolicLink"],
	["3", "CharacterDevice"],
	["4", "BlockDevice"],
	["5", "Directory"],
	["6", "FIFO"],
	["7", "ContiguousFile"],
	["g", "GlobalExtendedHeader"],
	["x", "ExtendedHeader"],
	["A", "SolarisACL"],
	["D", "GNUDumpDir"],
	["I", "Inode"],
	["K", "NextFileHasLongLinkpath"],
	["L", "NextFileHasLongPath"],
	["M", "ContinuationFile"],
	["N", "OldGnuLongPath"],
	["S", "SparseFile"],
	["V", "TapeVolumeHeader"],
	["X", "OldExtendedHeader"]
]), Ve = new Map(Array.from(oe).map((s) => [s[1], s[0]]));
var un = (s) => s === void 0 || s < 0 ? void 0 : s, F = class {
	cksumValid = !1;
	needPax = !1;
	nullBlock = !1;
	block;
	path;
	mode;
	uid;
	gid;
	size;
	cksum;
	#t = "Unsupported";
	linkpath;
	uname;
	gname;
	devmaj = 0;
	devmin = 0;
	atime;
	ctime;
	mtime;
	charset;
	comment;
	constructor(t, e = 0, i, r) {
		Buffer.isBuffer(t) ? this.decode(t, e || 0, i, r) : t && this.#i(t);
	}
	decode(t, e, i, r) {
		if (e || (e = 0), !t || !(t.length >= e + 512)) throw new Error("need 512 bytes for header");
		let n = xt(t, e + 156, 1), o = Ui.has(n), h = o ? i : void 0, a = o ? r : void 0;
		if (this.path = h?.path ?? xt(t, e, 100), this.mode = h?.mode ?? a?.mode ?? lt(t, e + 100, 8), this.uid = h?.uid ?? a?.uid ?? lt(t, e + 108, 8), this.gid = h?.gid ?? a?.gid ?? lt(t, e + 116, 8), this.size = un(h?.size ?? a?.size ?? lt(t, e + 124, 12)), this.mtime = h?.mtime ?? a?.mtime ?? Wi(t, e + 136, 12), this.cksum = lt(t, e + 148, 12), a && this.#i(a, !0), h && this.#i(h), ne(n) && (this.#t = n || "0"), this.#t === "0" && this.path.slice(-1) === "/" && (this.#t = "5"), this.#t === "5" && (this.size = 0), this.linkpath = xt(t, e + 157, 100), t.subarray(e + 257, e + 265).toString() === "ustar\x0000") if (this.uname = h?.uname ?? a?.uname ?? xt(t, e + 265, 32), this.gname = h?.gname ?? a?.gname ?? xt(t, e + 297, 32), this.devmaj = h?.devmaj ?? a?.devmaj ?? lt(t, e + 329, 8) ?? 0, this.devmin = h?.devmin ?? a?.devmin ?? lt(t, e + 337, 8) ?? 0, t[e + 475] !== 0) {
			let c = xt(t, e + 345, 155);
			this.path = c + "/" + this.path;
		} else {
			let c = xt(t, e + 345, 130);
			c && (this.path = c + "/" + this.path), this.atime = i?.atime ?? r?.atime ?? Wi(t, e + 476, 12), this.ctime = i?.ctime ?? r?.ctime ?? Wi(t, e + 488, 12);
		}
		let l = 256;
		for (let c = e; c < e + 148; c++) l += t[c];
		for (let c = e + 156; c < e + 512; c++) l += t[c];
		this.cksumValid = l === this.cksum, this.cksum === void 0 && l === 256 && (this.nullBlock = !0);
	}
	#i(t, e = !1) {
		Object.assign(this, Object.fromEntries(Object.entries(t).filter(([i, r]) => !(r == null || i === "size" && Number(r) < 0 || i === "path" && e || i === "linkpath" && e || i === "global"))));
	}
	encode(t, e = 0) {
		if (t || (t = this.block = Buffer.alloc(512)), this.#t === "Unsupported" && (this.#t = "0"), !(t.length >= e + 512)) throw new Error("need 512 bytes for header");
		let i = this.ctime || this.atime ? 130 : 155, r = mn(this.path || "", i), n = r[0], o = r[1];
		this.needPax = !!r[2], this.needPax = Lt(t, e, 100, n) || this.needPax, this.needPax = ct(t, e + 100, 8, this.mode) || this.needPax, this.needPax = ct(t, e + 108, 8, this.uid) || this.needPax, this.needPax = ct(t, e + 116, 8, this.gid) || this.needPax, this.needPax = ct(t, e + 124, 12, this.size) || this.needPax, this.needPax = Gi(t, e + 136, 12, this.mtime) || this.needPax, t[e + 156] = Number(this.#t.codePointAt(0)), this.needPax = Lt(t, e + 157, 100, this.linkpath) || this.needPax, t.write("ustar\x0000", e + 257, 8), this.needPax = Lt(t, e + 265, 32, this.uname) || this.needPax, this.needPax = Lt(t, e + 297, 32, this.gname) || this.needPax, this.needPax = ct(t, e + 329, 8, this.devmaj) || this.needPax, this.needPax = ct(t, e + 337, 8, this.devmin) || this.needPax, this.needPax = Lt(t, e + 345, i, o) || this.needPax, t[e + 475] !== 0 ? this.needPax = Lt(t, e + 345, 155, o) || this.needPax : (this.needPax = Lt(t, e + 345, 130, o) || this.needPax, this.needPax = Gi(t, e + 476, 12, this.atime) || this.needPax, this.needPax = Gi(t, e + 488, 12, this.ctime) || this.needPax);
		let h = 256;
		for (let a = e; a < e + 148; a++) h += t[a];
		for (let a = e + 156; a < e + 512; a++) h += t[a];
		return this.cksum = h, ct(t, e + 148, 8, this.cksum), this.cksumValid = !0, this.needPax;
	}
	get type() {
		return this.#t === "Unsupported" ? this.#t : oe.get(this.#t);
	}
	get typeKey() {
		return this.#t;
	}
	set type(t) {
		let e = String(Ve.get(t));
		if (ne(e) || e === "Unsupported") this.#t = e;
		else if (ne(t)) this.#t = t;
		else throw new TypeError("invalid entry type: " + t);
	}
}, mn = (s, t) => {
	let i = s, r = "", n, o = posix.parse(s).root || ".";
	if (Buffer.byteLength(i) < 100) n = [
		i,
		r,
		!1
	];
	else {
		r = posix.dirname(i), i = posix.basename(i);
		do
			Buffer.byteLength(i) <= 100 && Buffer.byteLength(r) <= t ? n = [
				i,
				r,
				!1
			] : Buffer.byteLength(i) > 100 && Buffer.byteLength(r) <= t ? n = [
				i.slice(0, 99),
				r,
				!0
			] : (i = posix.join(posix.basename(r), i), r = posix.dirname(r));
		while (r !== o && n === void 0);
		n || (n = [
			s.slice(0, 99),
			"",
			!0
		]);
	}
	return n;
}, xt = (s, t, e) => s.subarray(t, t + e).toString("utf8").replace(/\0.*/, ""), Wi = (s, t, e) => pn(lt(s, t, e)), pn = (s) => s === void 0 ? void 0 : /* @__PURE__ */ new Date(s * 1e3), lt = (s, t, e) => Number(s[t]) & 128 ? Hs(s.subarray(t, t + e)) : wn(s, t, e), En = (s) => isNaN(s) ? void 0 : s, wn = (s, t, e) => En(parseInt(s.subarray(t, t + e).toString("utf8").replace(/\0.*$/, "").trim(), 8)), Sn = {
	12: 8589934591,
	8: 2097151
}, ct = (s, t, e, i) => i === void 0 ? !1 : i > Sn[e] || i < 0 ? (Us(i, s.subarray(t, t + e)), !0) : (yn(s, t, e, i), !1), yn = (s, t, e, i) => s.write(Rn(i, e), t, e, "ascii"), Rn = (s, t) => gn(Math.floor(s).toString(8), t), gn = (s, t) => (s.length === t - 1 ? s : new Array(t - s.length - 1).join("0") + s + " ") + "\0", Gi = (s, t, e, i) => i === void 0 ? !1 : ct(s, t, e, i.getTime() / 1e3), bn = new Array(156).join("\0"), Lt = (s, t, e, i) => i === void 0 ? !1 : (s.write(i + bn, t, e, "utf8"), i.length !== Buffer.byteLength(i) || i.length > e);
var ft = class s {
	atime;
	mtime;
	ctime;
	charset;
	comment;
	gid;
	uid;
	gname;
	uname;
	linkpath;
	dev;
	ino;
	nlink;
	path;
	size;
	mode;
	global;
	constructor(t, e = !1) {
		this.atime = t.atime, this.charset = t.charset, this.comment = t.comment, this.ctime = t.ctime, this.dev = t.dev, this.gid = t.gid, this.global = e, this.gname = t.gname, this.ino = t.ino, this.linkpath = t.linkpath, this.mtime = t.mtime, this.nlink = t.nlink, this.path = t.path, this.size = t.size, this.uid = t.uid, this.uname = t.uname;
	}
	encode() {
		let t = this.encodeBody();
		if (t === "") return Buffer.allocUnsafe(0);
		let e = Buffer.byteLength(t), i = 512 * Math.ceil(1 + e / 512), r = Buffer.allocUnsafe(i);
		for (let n = 0; n < 512; n++) r[n] = 0;
		new F({
			path: ("PaxHeader/" + basename(this.path ?? "")).slice(0, 99),
			mode: this.mode || 420,
			uid: this.uid,
			gid: this.gid,
			size: e,
			mtime: this.mtime,
			type: this.global ? "GlobalExtendedHeader" : "ExtendedHeader",
			linkpath: "",
			uname: this.uname || "",
			gname: this.gname || "",
			devmaj: 0,
			devmin: 0,
			atime: this.atime,
			ctime: this.ctime
		}).encode(r), r.write(t, 512, e, "utf8");
		for (let n = e + 512; n < r.length; n++) r[n] = 0;
		return r;
	}
	encodeBody() {
		return this.encodeField("path") + this.encodeField("ctime") + this.encodeField("atime") + this.encodeField("dev") + this.encodeField("ino") + this.encodeField("nlink") + this.encodeField("charset") + this.encodeField("comment") + this.encodeField("gid") + this.encodeField("gname") + this.encodeField("linkpath") + this.encodeField("mtime") + this.encodeField("size") + this.encodeField("uid") + this.encodeField("uname");
	}
	encodeField(t) {
		if (this[t] === void 0) return "";
		let e = this[t], i = e instanceof Date ? e.getTime() / 1e3 : e, r = " " + (t === "dev" || t === "ino" || t === "nlink" ? "SCHILY." : "") + t + "=" + i + `
`, n = Buffer.byteLength(r), o = Math.floor(Math.log(n) / Math.log(10)) + 1;
		return n + o >= Math.pow(10, o) && (o += 1), o + n + r;
	}
	static parse(t, e, i = !1) {
		return new s(On(Tn(t), e), i);
	}
}, On = (s, t) => t ? Object.assign({}, t, s) : s, Tn = (s) => s.replace(/\n$/, "").split(`
`).reduce(xn, Object.create(null)), xn = (s, t) => {
	let e = parseInt(t, 10);
	if (e !== Buffer.byteLength(t) + 1) return s;
	t = t.slice((e + " ").length);
	let i = t.split("="), r = i.shift();
	if (!r) return s;
	let n = r.replace(/^SCHILY\.(dev|ino|nlink)/, "$1"), o = i.join("=").replace(/\0.*/, "");
	switch (n) {
		case "path":
		case "linkpath":
		case "type":
		case "charset":
		case "comment":
		case "gname":
		case "uname":
			s[n] = o;
			break;
		case "ctime":
		case "atime":
		case "mtime":
			s[n] = /* @__PURE__ */ new Date(Number(o) * 1e3);
			break;
		case "size":
			let h = +o;
			h >= 0 && (s[n] = h);
			break;
		case "gid":
		case "uid":
		case "dev":
		case "ino":
		case "nlink":
		case "mode":
			s[n] = +o;
			break;
	}
	return s;
};
var f = (process.env.TESTING_TAR_FAKE_PLATFORM || process.platform) !== "win32" ? (s) => String(s) : (s) => String(s).replaceAll(/\\/g, "/");
var $e = class extends A {
	extended;
	globalExtended;
	header;
	startBlockSize;
	blockRemain;
	remain;
	type;
	meta = !1;
	ignore = !1;
	path;
	mode;
	uid;
	gid;
	uname;
	gname;
	size = 0;
	mtime;
	atime;
	ctime;
	linkpath;
	dev;
	ino;
	nlink;
	invalid = !1;
	absolute;
	unsupported = !1;
	constructor(t, e, i) {
		switch (super({}), this.pause(), this.extended = e, this.globalExtended = i, this.header = t, this.remain = t.size ?? 0, this.startBlockSize = 512 * Math.ceil(this.remain / 512), this.blockRemain = this.startBlockSize, this.type = t.type, this.type) {
			case "File":
			case "OldFile":
			case "Link":
			case "SymbolicLink":
			case "CharacterDevice":
			case "BlockDevice":
			case "Directory":
			case "FIFO":
			case "ContiguousFile":
			case "GNUDumpDir": break;
			case "NextFileHasLongLinkpath":
			case "NextFileHasLongPath":
			case "OldGnuLongPath":
			case "GlobalExtendedHeader":
			case "ExtendedHeader":
			case "OldExtendedHeader":
				this.meta = !0;
				break;
			default: this.ignore = !0;
		}
		if (!t.path) throw new Error("no path provided for tar.ReadEntry");
		this.path = f(t.path), this.mode = t.mode, this.mode && (this.mode = this.mode & 4095), this.uid = t.uid, this.gid = t.gid, this.uname = t.uname, this.gname = t.gname, this.size = this.remain, this.mtime = t.mtime, this.atime = t.atime, this.ctime = t.ctime, this.linkpath = t.linkpath ? f(t.linkpath) : void 0, this.uname = t.uname, this.gname = t.gname, e && this.#t(e), i && this.#t(i, !0);
	}
	write(t) {
		let e = t.length;
		if (e > this.blockRemain) throw new Error("writing more to entry than is appropriate");
		let i = this.remain, r = this.blockRemain;
		return this.remain = Math.max(0, i - e), this.blockRemain = Math.max(0, r - e), this.ignore ? !0 : i >= e ? super.write(t) : super.write(t.subarray(0, i));
	}
	#t(t, e = !1) {
		t.path && (t.path = f(t.path)), t.linkpath && (t.linkpath = f(t.linkpath)), Object.assign(this, Object.fromEntries(Object.entries(t).filter(([i, r]) => !(r == null || i === "path" && e))));
	}
};
var Dt = (s, t, e, i = {}) => {
	s.file && (i.file = s.file), s.cwd && (i.cwd = s.cwd), i.code = e instanceof Error && e.code || t, i.tarCode = t, !s.strict && i.recoverable !== !1 ? (e instanceof Error && (i = Object.assign(e, i), e = e.message), s.emit("warn", t, e, i)) : e instanceof Error ? s.emit("error", Object.assign(e, i)) : s.emit("error", Object.assign(/* @__PURE__ */ new Error(`${t}: ${e}`), i));
};
var Nn = 1024 * 1024, Xi = Buffer.from([31, 139]), qi = Buffer.from([
	40,
	181,
	47,
	253
]), An = Math.max(Xi.length, qi.length), B = Symbol("state"), Nt = Symbol("writeEntry"), it = Symbol("readEntry"), Zi = Symbol("nextEntry"), Zs = Symbol("processEntry"), V = Symbol("extendedHeader"), he = Symbol("globalExtendedHeader"), dt = Symbol("meta"), Ys = Symbol("emitMeta"), p = Symbol("buffer"), st = Symbol("queue"), ut = Symbol("ended"), Yi = Symbol("emittedEnd"), At = Symbol("emit"), w = Symbol("unzip"), Xe = Symbol("consumeChunk"), qe = Symbol("consumeChunkSub"), Ki = Symbol("consumeBody"), Ks = Symbol("consumeMeta"), Vs = Symbol("consumeHeader"), ae = Symbol("consuming"), Vi = Symbol("bufferConcat"), Qe = Symbol("maybeEnd"), Yt = Symbol("writing"), $ = Symbol("aborted"), Je = Symbol("onDone"), It = Symbol("sawValidEntry"), je = Symbol("sawNullBlock"), ti = Symbol("sawEOF"), $s = Symbol("closeStream"), In = 1e3, le = Symbol("compressedBytesRead"), $i = Symbol("decompressedBytesRead"), Xs = Symbol("checkDecompressionRatio"), Cn = () => !0, rt = class extends EventEmitter {
	file;
	strict;
	maxMetaEntrySize;
	filter;
	brotli;
	zstd;
	maxDecompressionRatio;
	writable = !0;
	readable = !1;
	[st] = [];
	[p];
	[it];
	[Nt];
	[B] = "begin";
	[dt] = "";
	[V];
	[he];
	[ut] = !1;
	[w];
	[$] = !1;
	[It];
	[je] = !1;
	[ti] = !1;
	[Yt] = !1;
	[ae] = !1;
	[Yi] = !1;
	[le] = 0;
	[$i] = 0;
	constructor(t = {}) {
		super(), this.file = t.file || "", this.on(Je, () => {
			(this[B] === "begin" || this[It] === !1) && this.warn("TAR_BAD_ARCHIVE", "Unrecognized archive format");
		}), t.ondone ? this.on(Je, t.ondone) : this.on(Je, () => {
			this.emit("prefinish"), this.emit("finish"), this.emit("end");
		}), this.strict = !!t.strict, this.maxDecompressionRatio = typeof t.maxDecompressionRatio == "number" ? t.maxDecompressionRatio : In, this.maxMetaEntrySize = t.maxMetaEntrySize || Nn, this.filter = typeof t.filter == "function" ? t.filter : Cn;
		let e = t.file && (t.file.endsWith(".tar.br") || t.file.endsWith(".tbr"));
		this.brotli = !(t.gzip || t.zstd) && t.brotli !== void 0 ? t.brotli : e ? void 0 : !1;
		let i = t.file && (t.file.endsWith(".tar.zst") || t.file.endsWith(".tzst"));
		this.zstd = !(t.gzip || t.brotli) && t.zstd !== void 0 ? t.zstd : i ? !0 : void 0, this.on("end", () => this[$s]()), typeof t.onwarn == "function" && this.on("warn", t.onwarn), typeof t.onReadEntry == "function" && this.on("entry", t.onReadEntry);
	}
	warn(t, e, i = {}) {
		Dt(this, t, e, i);
	}
	[Vs](t, e) {
		this[It] === void 0 && (this[It] = !1);
		let i;
		try {
			i = new F(t, e, this[V], this[he]);
		} catch (r) {
			return this.warn("TAR_ENTRY_INVALID", r);
		}
		if (i.nullBlock) this[je] ? (this[ti] = !0, this[B] === "begin" && (this[B] = "header"), this[At]("eof")) : (this[je] = !0, this[At]("nullBlock"));
		else if (this[je] = !1, !i.cksumValid) this.warn("TAR_ENTRY_INVALID", "checksum failure", { header: i });
		else if (!i.path) this.warn("TAR_ENTRY_INVALID", "path is required", { header: i });
		else {
			let r = i.type;
			if (/^(Symbolic)?Link$/.test(r) && !i.linkpath) this.warn("TAR_ENTRY_INVALID", "linkpath required", { header: i });
			else if (!/^(Symbolic)?Link$/.test(r) && !/^(Global)?ExtendedHeader$/.test(r) && i.linkpath) this.warn("TAR_ENTRY_INVALID", "linkpath forbidden", { header: i });
			else {
				let n = this[Nt] = new $e(i, this[V], this[he]);
				if (!this[It]) if (n.remain) {
					let o = () => {
						n.invalid || (this[It] = !0);
					};
					n.on("end", o);
				} else this[It] = !0;
				n.meta ? n.size > this.maxMetaEntrySize ? (n.ignore = !0, this[At]("ignoredEntry", n), this[B] = "ignore", n.resume()) : n.size > 0 && (this[dt] = "", n.on("data", (o) => this[dt] += o), this[B] = "meta") : (this[V] = void 0, n.ignore = n.ignore || !this.filter(n.path, n), n.ignore ? (this[At]("ignoredEntry", n), this[B] = n.remain ? "ignore" : "header", n.resume()) : (n.remain ? this[B] = "body" : (this[B] = "header", n.end()), this[it] ? this[st].push(n) : (this[st].push(n), this[Zi]())));
			}
		}
	}
	[$s]() {
		queueMicrotask(() => this.emit("close"));
	}
	[Zs](t) {
		let e = !0;
		if (!t) this[it] = void 0, e = !1;
		else if (Array.isArray(t)) {
			let [i, ...r] = t;
			this.emit(i, ...r);
		} else this[it] = t, this.emit("entry", t), t.emittedEnd || (t.on("end", () => this[Zi]()), e = !1);
		return e;
	}
	[Zi]() {
		do		;
while (this[Zs](this[st].shift()));
		if (this[st].length === 0) {
			let t = this[it];
			!t || t.flowing || t.size === t.remain ? this[Yt] || this.emit("drain") : t.once("drain", () => this.emit("drain"));
		}
	}
	[Ki](t, e) {
		let i = this[Nt];
		if (!i) throw new Error("attempt to consume body without entry??");
		let r = i.blockRemain ?? 0, n = r >= t.length && e === 0 ? t : t.subarray(e, e + r);
		return i.write(n), i.blockRemain || (this[B] = "header", this[Nt] = void 0, i.end()), n.length;
	}
	[Ks](t, e) {
		let i = this[Nt], r = this[Ki](t, e);
		return !this[Nt] && i && this[Ys](i), r;
	}
	[At](t, e, i) {
		this[st].length === 0 && !this[it] ? this.emit(t, e, i) : this[st].push([
			t,
			e,
			i
		]);
	}
	[Ys](t) {
		switch (this[At]("meta", this[dt]), t.type) {
			case "ExtendedHeader":
			case "OldExtendedHeader":
				this[V] = ft.parse(this[dt], this[V], !1);
				break;
			case "GlobalExtendedHeader":
				this[he] = ft.parse(this[dt], this[he], !0);
				break;
			case "NextFileHasLongPath":
			case "OldGnuLongPath": {
				let e = this[V] ?? Object.create(null);
				this[V] = e, e.path = this[dt].replace(/\0.*/, "");
				break;
			}
			case "NextFileHasLongLinkpath": {
				let e = this[V] || Object.create(null);
				this[V] = e, e.linkpath = this[dt].replace(/\0.*/, "");
				break;
			}
			default: throw new Error("unknown meta: " + t.type);
		}
	}
	abort(t) {
		if (!this[$]) {
			if (this[w]) {
				let e = this[w];
				e.write = () => !0, e.end = () => e, e.emit = () => !1, e.destroy?.();
			}
			this[$] = !0, this.emit("abort", t), this.warn("TAR_ABORT", t, { recoverable: !1 });
		}
	}
	[Xs](t) {
		this[$i] += t.length;
		let e = this[$i] / this[le];
		return e > this.maxDecompressionRatio ? (this.abort(/* @__PURE__ */ new Error(`max decompression ratio exceeded: ${e.toFixed(2)} > ${this.maxDecompressionRatio}`)), !1) : !0;
	}
	write(t, e, i) {
		if (typeof e == "function" && (i = e, e = void 0), typeof t == "string" && (t = Buffer.from(t, typeof e == "string" ? e : "utf8")), this[$]) return i?.(), !1;
		if ((this[w] === void 0 || this.brotli === void 0 && this[w] === !1) && t) {
			if (this[p] && (t = Buffer.concat([this[p], t]), this[p] = void 0), t.length < An) return this[p] = t, i?.(), !0;
			for (let a = 0; this[w] === void 0 && a < Xi.length; a++) t[a] !== Xi[a] && (this[w] = !1);
			let o = !1;
			if (this[w] === !1 && this.zstd !== !1) {
				o = !0;
				for (let a = 0; a < qi.length; a++) if (t[a] !== qi[a]) {
					o = !1;
					break;
				}
			}
			let h = this.brotli === void 0 && !o;
			if (this[w] === !1 && h) if (t.length < 512) if (this[ut]) this.brotli = !0;
			else return this[p] = t, i?.(), !0;
			else try {
				new F(t.subarray(0, 512)), this.brotli = !1;
			} catch {
				this.brotli = !0;
			}
			if (this[w] === void 0 || this[w] === !1 && (this.brotli || o)) {
				let a = this[ut];
				this[ut] = !1, this[w] = this[w] === void 0 ? new Ue({}) : o ? new Ke({}) : new Ge({}), this[w].on("data", (c) => {
					this[Xs](c) && this[Xe](c);
				}), this[w].on("error", (c) => {
					this[$] || this.abort(c);
				}), this[w].on("end", () => {
					this[ut] = !0, this[Xe]();
				}), this[Yt] = !0, this[le] += t.length;
				let l = !!this[w][a ? "end" : "write"](t);
				return this[Yt] = !1, i?.(), l;
			}
		}
		this[Yt] = !0, this[w] ? (this[le] += t.length, this[w].write(t)) : this[Xe](t), this[Yt] = !1;
		let n = this[st].length > 0 ? !1 : this[it] ? this[it].flowing : !0;
		return !n && this[st].length === 0 && this[it]?.once("drain", () => this.emit("drain")), i?.(), n;
	}
	[Vi](t) {
		t && !this[$] && (this[p] = this[p] ? Buffer.concat([this[p], t]) : t);
	}
	[Qe]() {
		if (this[ut] && !this[Yi] && !this[$] && !this[ae]) {
			this[Yi] = !0;
			let t = this[Nt];
			if (t?.blockRemain) {
				let e = this[p] ? this[p].length : 0;
				this.warn("TAR_BAD_ARCHIVE", `Truncated input (needed ${t.blockRemain} more bytes, only ${e} available)`, { entry: t }), this[p] && t.write(this[p]), t.end();
			}
			this[At](Je);
		}
	}
	[Xe](t) {
		if (this[ae] && t) this[Vi](t);
		else if (!t && !this[p]) this[Qe]();
		else if (t) {
			if (this[ae] = !0, this[p]) {
				this[Vi](t);
				let e = this[p];
				this[p] = void 0, this[qe](e);
			} else this[qe](t);
			for (; this[p] && this[p]?.length >= 512 && !this[$] && !this[ti];) {
				let e = this[p];
				this[p] = void 0, this[qe](e);
			}
			this[ae] = !1;
		}
		(!this[p] || this[ut]) && this[Qe]();
	}
	[qe](t) {
		let e = 0, i = t.length;
		for (; e + 512 <= i && !this[$] && !this[ti];) switch (this[B]) {
			case "begin":
			case "header":
				this[Vs](t, e), e += 512;
				break;
			case "ignore":
			case "body":
				e += this[Ki](t, e);
				break;
			case "meta":
				e += this[Ks](t, e);
				break;
			default: throw new Error("invalid state: " + this[B]);
		}
		e < i && (this[p] = this[p] ? Buffer.concat([t.subarray(e), this[p]]) : t.subarray(e));
	}
	end(t, e, i) {
		return typeof t == "function" && (i = t, e = void 0, t = void 0), typeof e == "function" && (i = e, e = void 0), typeof t == "string" && (t = Buffer.from(t, e)), i && this.once("finish", i), this[$] || (this[w] ? (t && (this[le] += t.length, this[w].write(t)), this[w].end()) : (this[ut] = !0, (this.brotli === void 0 || this.zstd === void 0) && (t = t || Buffer.alloc(0)), t && this.write(t), this[Qe]())), this;
	}
};
var mt = (s) => {
	let t = s.length - 1, e = -1;
	for (; t > -1 && s.charAt(t) === "/";) e = t, t--;
	return e === -1 ? s : s.slice(0, e);
};
var vn = (s) => {
	let t = s.onReadEntry;
	s.onReadEntry = t ? (e) => {
		t(e), e.resume();
	} : (e) => e.resume();
}, Qi = (s, t) => {
	let e = new Map(t.map((o) => [mt(o), !0])), i = s.filter, r = 100, n = (o, h = "", a = 0) => {
		if (a >= r) return e.set(o, !1), !1;
		let l = h || parse(o).root || ".", c;
		if (o === l) c = !1;
		else {
			let d = e.get(o);
			c = d !== void 0 ? d : n(dirname$1(o), l, a + 1);
		}
		return e.set(o, c), c;
	};
	s.filter = i ? (o, h) => i(o, h) && n(mt(o)) : (o) => n(mt(o));
}, Mn = (s) => {
	let t = new rt(s), e = s.file, i;
	try {
		i = Kt.openSync(e, "r");
		let r = Kt.fstatSync(i), n = s.maxReadSize || 16 * 1024 * 1024;
		if (r.size < n) {
			let o = Buffer.allocUnsafe(r.size), h = Kt.readSync(i, o, 0, r.size, 0);
			t.end(h === o.byteLength ? o : o.subarray(0, h));
		} else {
			let o = 0, h = Buffer.allocUnsafe(n);
			for (; o < r.size;) {
				let a = Kt.readSync(i, h, 0, n, o);
				if (a === 0) break;
				o += a, t.write(h.subarray(0, a));
			}
			t.end();
		}
	} finally {
		if (typeof i == "number") try {
			Kt.closeSync(i);
		} catch {}
	}
}, Bn = (s, t) => {
	let e = new rt(s), i = s.maxReadSize || 16 * 1024 * 1024, r = s.file;
	return new Promise((o, h) => {
		e.on("error", h), e.on("end", o), Kt.stat(r, (a, l) => {
			if (a) h(a);
			else {
				let c = new _t(r, {
					readSize: i,
					size: l.size
				});
				c.on("error", h), c.pipe(e);
			}
		});
	});
}, Ct = K(Mn, Bn, (s) => new rt(s), (s) => new rt(s), (s, t) => {
	t?.length && Qi(s, t), s.noResume || vn(s);
});
var Ji = (s, t, e) => (s &= 4095, e && (s = (s | 384) & -19), t && (s & 256 && (s |= 64), s & 32 && (s |= 8), s & 4 && (s |= 1)), s);
var { isAbsolute: zn, parse: qs } = win32, ce = (s) => {
	let t = "", e = qs(s);
	for (; zn(s) || e.root;) {
		let i = s.charAt(0) === "/" && s.slice(0, 4) !== "//?/" ? "/" : e.root;
		s = s.slice(i.length), t += i, e = qs(s);
	}
	return [t, s];
};
var ei = [
	"|",
	"<",
	">",
	"?",
	":"
], ji = ei.map((s) => String.fromCodePoint(61440 + Number(s.codePointAt(0)))), Un = new Map(ei.map((s, t) => [s, ji[t]])), Hn = new Map(ji.map((s, t) => [s, ei[t]])), ts = (s) => ei.reduce((t, e) => t.split(e).join(Un.get(e)), s), Qs = (s) => ji.reduce((t, e) => t.split(e).join(Hn.get(e)), s);
var rr = (s, t) => t ? (s = f(s).replace(/^\.(\/|$)/, ""), mt(t) + "/" + s) : f(s), Wn = 16 * 1024 * 1024, tr = Symbol("process"), er = Symbol("file"), ir = Symbol("directory"), is = Symbol("symlink"), sr = Symbol("hardlink"), fe = Symbol("header"), ii = Symbol("read"), ss = Symbol("lstat"), si = Symbol("onlstat"), rs = Symbol("onread"), ns = Symbol("onreadlink"), os = Symbol("openfile"), hs = Symbol("onopenfile"), pt = Symbol("close"), ri = Symbol("mode"), as = Symbol("awaitDrain"), es = Symbol("ondrain"), q = Symbol("prefix"), de = class extends A {
	path;
	portable;
	myuid = process.getuid && process.getuid() || 0;
	myuser = process.env.USER || "";
	maxReadSize;
	linkCache;
	statCache;
	preservePaths;
	cwd;
	strict;
	mtime;
	noPax;
	noMtime;
	prefix;
	fd;
	blockLen = 0;
	blockRemain = 0;
	buf;
	pos = 0;
	remain = 0;
	length = 0;
	offset = 0;
	win32;
	absolute;
	header;
	type;
	linkpath;
	stat;
	onWriteEntry;
	#t = !1;
	constructor(t, e = {}) {
		let i = se(e);
		super(), this.path = f(t), this.portable = !!i.portable, this.maxReadSize = i.maxReadSize || Wn, this.linkCache = i.linkCache || /* @__PURE__ */ new Map(), this.statCache = i.statCache || /* @__PURE__ */ new Map(), this.preservePaths = !!i.preservePaths, this.cwd = f(i.cwd || process.cwd()), this.strict = !!i.strict, this.noPax = !!i.noPax, this.noMtime = !!i.noMtime, this.mtime = i.mtime, this.prefix = i.prefix ? f(i.prefix) : void 0, this.onWriteEntry = i.onWriteEntry, typeof i.onwarn == "function" && this.on("warn", i.onwarn);
		let r = !1;
		if (!this.preservePaths) {
			let [o, h] = ce(this.path);
			o && typeof h == "string" && (this.path = h, r = o);
		}
		this.win32 = !!i.win32 || process.platform === "win32", this.win32 && (this.path = Qs(this.path.replaceAll(/\\/g, "/")), t = t.replaceAll(/\\/g, "/")), this.absolute = f(i.absolute || js.resolve(this.cwd, t)), this.path === "" && (this.path = "./"), r && this.warn("TAR_ENTRY_INFO", `stripping ${r} from absolute path`, {
			entry: this,
			path: r + this.path
		});
		let n = this.statCache.get(this.absolute);
		n ? this[si](n) : this[ss]();
	}
	warn(t, e, i = {}) {
		return Dt(this, t, e, i);
	}
	emit(t, ...e) {
		return t === "error" && (this.#t = !0), super.emit(t, ...e);
	}
	[ss]() {
		I.lstat(this.absolute, (t, e) => {
			if (t) return this.emit("error", t);
			this[si](e);
		});
	}
	[si](t) {
		this.statCache.set(this.absolute, t), this.stat = t, t.isFile() || (t.size = 0), this.type = Gn(t), this.emit("stat", t), this[tr]();
	}
	[tr]() {
		switch (this.type) {
			case "File": return this[er]();
			case "Directory": return this[ir]();
			case "SymbolicLink": return this[is]();
			default: return this.end();
		}
	}
	[ri](t) {
		return Ji(t, this.type === "Directory", this.portable);
	}
	[q](t) {
		return rr(t, this.prefix);
	}
	[fe]() {
		if (!this.stat) throw new Error("cannot write header before stat");
		this.type === "Directory" && this.portable && (this.noMtime = !0), this.onWriteEntry?.(this), this.header = new F({
			path: this[q](this.path),
			linkpath: this.type === "Link" && this.linkpath !== void 0 ? this[q](this.linkpath) : this.linkpath,
			mode: this[ri](this.stat.mode),
			uid: this.portable ? void 0 : this.stat.uid,
			gid: this.portable ? void 0 : this.stat.gid,
			size: this.stat.size,
			mtime: this.noMtime ? void 0 : this.mtime || this.stat.mtime,
			type: this.type === "Unsupported" ? void 0 : this.type,
			uname: this.portable ? void 0 : this.stat.uid === this.myuid ? this.myuser : "",
			atime: this.portable ? void 0 : this.stat.atime,
			ctime: this.portable ? void 0 : this.stat.ctime
		}), this.header.encode() && !this.noPax && super.write(new ft({
			atime: this.portable ? void 0 : this.header.atime,
			ctime: this.portable ? void 0 : this.header.ctime,
			gid: this.portable ? void 0 : this.header.gid,
			mtime: this.noMtime ? void 0 : this.mtime || this.header.mtime,
			path: this[q](this.path),
			linkpath: this.type === "Link" && this.linkpath !== void 0 ? this[q](this.linkpath) : this.linkpath,
			size: this.header.size,
			uid: this.portable ? void 0 : this.header.uid,
			uname: this.portable ? void 0 : this.header.uname,
			dev: this.portable ? void 0 : this.stat.dev,
			ino: this.portable ? void 0 : this.stat.ino,
			nlink: this.portable ? void 0 : this.stat.nlink
		}).encode());
		let t = this.header?.block;
		if (!t) throw new Error("failed to encode header");
		super.write(t);
	}
	[ir]() {
		if (!this.stat) throw new Error("cannot create directory entry without stat");
		this.path.slice(-1) !== "/" && (this.path += "/"), this.stat.size = 0, this[fe](), this.end();
	}
	[is]() {
		I.readlink(this.absolute, (t, e) => {
			if (t) return this.emit("error", t);
			this[ns](e);
		});
	}
	[ns](t) {
		this.linkpath = f(t), this[fe](), this.end();
	}
	[sr](t) {
		if (!this.stat) throw new Error("cannot create link entry without stat");
		this.type = "Link", this.linkpath = f(js.relative(this.cwd, t)), this.stat.size = 0, this[fe](), this.end();
	}
	[er]() {
		if (!this.stat) throw new Error("cannot create file entry without stat");
		if (this.stat.nlink > 1) {
			let t = `${this.stat.dev}:${this.stat.ino}`, e = this.linkCache.get(t);
			if (e?.indexOf(this.cwd) === 0) return this[sr](e);
			this.linkCache.set(t, this.absolute);
		}
		if (this[fe](), this.stat.size === 0) return this.end();
		this[os]();
	}
	[os]() {
		I.open(this.absolute, "r", (t, e) => {
			if (t) return this.emit("error", t);
			this[hs](e);
		});
	}
	[hs](t) {
		if (this.fd = t, this.#t) return this[pt]();
		if (!this.stat) throw new Error("should stat before calling onopenfile");
		this.blockLen = 512 * Math.ceil(this.stat.size / 512), this.blockRemain = this.blockLen;
		let e = Math.min(this.blockLen, this.maxReadSize);
		this.buf = Buffer.allocUnsafe(e), this.offset = 0, this.pos = 0, this.remain = this.stat.size, this.length = this.buf.length, this[ii]();
	}
	[ii]() {
		let { fd: t, buf: e, offset: i, length: r, pos: n } = this;
		if (t === void 0 || e === void 0) throw new Error("cannot read file without first opening");
		I.read(t, e, i, r, n, (o, h) => {
			if (o) return this[pt](() => this.emit("error", o));
			this[rs](h);
		});
	}
	[pt](t = () => {}) {
		this.fd !== void 0 && I.close(this.fd, t);
	}
	[rs](t) {
		if (t <= 0 && this.remain > 0) {
			let r = Object.assign(/* @__PURE__ */ new Error("encountered unexpected EOF"), {
				path: this.absolute,
				syscall: "read",
				code: "EOF"
			});
			return this[pt](() => this.emit("error", r));
		}
		if (t > this.remain) {
			let r = Object.assign(/* @__PURE__ */ new Error("did not encounter expected EOF"), {
				path: this.absolute,
				syscall: "read",
				code: "EOF"
			});
			return this[pt](() => this.emit("error", r));
		}
		if (!this.buf) throw new Error("should have created buffer prior to reading");
		if (t === this.remain) for (let r = t; r < this.length && t < this.blockRemain; r++) this.buf[r + this.offset] = 0, t++, this.remain++;
		let e = this.offset === 0 && t === this.buf.length ? this.buf : this.buf.subarray(this.offset, this.offset + t);
		this.write(e) ? this[es]() : this[as](() => this[es]());
	}
	[as](t) {
		this.once("drain", t);
	}
	write(t, e, i) {
		if (typeof e == "function" && (i = e, e = void 0), typeof t == "string" && (t = Buffer.from(t, typeof e == "string" ? e : "utf8")), this.blockRemain < t.length) {
			let r = Object.assign(/* @__PURE__ */ new Error("writing more data than expected"), { path: this.absolute });
			return this.emit("error", r);
		}
		return this.remain -= t.length, this.blockRemain -= t.length, this.pos += t.length, this.offset += t.length, super.write(t, null, i);
	}
	[es]() {
		if (!this.remain) return this.blockRemain && super.write(Buffer.alloc(this.blockRemain)), this[pt]((t) => t ? this.emit("error", t) : this.end());
		if (!this.buf) throw new Error("buffer lost somehow in ONDRAIN");
		this.offset >= this.length && (this.buf = Buffer.allocUnsafe(Math.min(this.blockRemain, this.buf.length)), this.offset = 0), this.length = this.buf.length - this.offset, this[ii]();
	}
}, ni = class extends de {
	sync = !0;
	[ss]() {
		this[si](I.lstatSync(this.absolute));
	}
	[is]() {
		this[ns](I.readlinkSync(this.absolute));
	}
	[os]() {
		this[hs](I.openSync(this.absolute, "r"));
	}
	[ii]() {
		let t = !0;
		try {
			let { fd: e, buf: i, offset: r, length: n, pos: o } = this;
			if (e === void 0 || i === void 0) throw new Error("fd and buf must be set in READ method");
			let h = I.readSync(e, i, r, n, o);
			this[rs](h), t = !1;
		} finally {
			if (t) try {
				this[pt](() => {});
			} catch {}
		}
	}
	[as](t) {
		t();
	}
	[pt](t = () => {}) {
		this.fd !== void 0 && I.closeSync(this.fd), t();
	}
}, oi = class extends A {
	blockLen = 0;
	blockRemain = 0;
	buf = 0;
	pos = 0;
	remain = 0;
	length = 0;
	preservePaths;
	portable;
	strict;
	noPax;
	noMtime;
	readEntry;
	type;
	prefix;
	path;
	mode;
	uid;
	gid;
	uname;
	gname;
	header;
	mtime;
	atime;
	ctime;
	linkpath;
	size;
	onWriteEntry;
	warn(t, e, i = {}) {
		return Dt(this, t, e, i);
	}
	constructor(t, e = {}) {
		let i = se(e);
		super(), this.preservePaths = !!i.preservePaths, this.portable = !!i.portable, this.strict = !!i.strict, this.noPax = !!i.noPax, this.noMtime = !!i.noMtime, this.onWriteEntry = i.onWriteEntry, this.readEntry = t;
		let { type: r } = t;
		if (r === "Unsupported") throw new Error("writing entry that should be ignored");
		this.type = r, this.type === "Directory" && this.portable && (this.noMtime = !0), this.prefix = i.prefix, this.path = f(t.path), this.mode = t.mode !== void 0 ? this[ri](t.mode) : void 0, this.uid = this.portable ? void 0 : t.uid, this.gid = this.portable ? void 0 : t.gid, this.uname = this.portable ? void 0 : t.uname, this.gname = this.portable ? void 0 : t.gname, this.size = t.size, this.mtime = this.noMtime ? void 0 : i.mtime || t.mtime, this.atime = this.portable ? void 0 : t.atime, this.ctime = this.portable ? void 0 : t.ctime, this.linkpath = t.linkpath !== void 0 ? f(t.linkpath) : void 0, typeof i.onwarn == "function" && this.on("warn", i.onwarn);
		let n = !1;
		if (!this.preservePaths) {
			let [h, a] = ce(this.path);
			h && typeof a == "string" && (this.path = a, n = h);
		}
		this.remain = t.size, this.blockRemain = t.startBlockSize, this.onWriteEntry?.(this), this.header = new F({
			path: this[q](this.path),
			linkpath: this.type === "Link" && this.linkpath !== void 0 ? this[q](this.linkpath) : this.linkpath,
			mode: this.mode,
			uid: this.portable ? void 0 : this.uid,
			gid: this.portable ? void 0 : this.gid,
			size: this.size,
			mtime: this.noMtime ? void 0 : this.mtime,
			type: this.type,
			uname: this.portable ? void 0 : this.uname,
			atime: this.portable ? void 0 : this.atime,
			ctime: this.portable ? void 0 : this.ctime
		}), n && this.warn("TAR_ENTRY_INFO", `stripping ${n} from absolute path`, {
			entry: this,
			path: n + this.path
		}), this.header.encode() && !this.noPax && super.write(new ft({
			atime: this.portable ? void 0 : this.atime,
			ctime: this.portable ? void 0 : this.ctime,
			gid: this.portable ? void 0 : this.gid,
			mtime: this.noMtime ? void 0 : this.mtime,
			path: this[q](this.path),
			linkpath: this.type === "Link" && this.linkpath !== void 0 ? this[q](this.linkpath) : this.linkpath,
			size: this.size,
			uid: this.portable ? void 0 : this.uid,
			uname: this.portable ? void 0 : this.uname,
			dev: this.portable ? void 0 : this.readEntry.dev,
			ino: this.portable ? void 0 : this.readEntry.ino,
			nlink: this.portable ? void 0 : this.readEntry.nlink
		}).encode());
		let o = this.header?.block;
		if (!o) throw new Error("failed to encode header");
		super.write(o), t.pipe(this);
	}
	[q](t) {
		return rr(t, this.prefix);
	}
	[ri](t) {
		return Ji(t, this.type === "Directory", this.portable);
	}
	write(t, e, i) {
		typeof e == "function" && (i = e, e = void 0), typeof t == "string" && (t = Buffer.from(t, typeof e == "string" ? e : "utf8"));
		let r = t.length;
		if (r > this.blockRemain) throw new Error("writing more to entry than is appropriate");
		return this.blockRemain -= r, super.write(t, i);
	}
	end(t, e, i) {
		return this.blockRemain && super.write(Buffer.alloc(this.blockRemain)), typeof t == "function" && (i = t, e = void 0, t = void 0), typeof e == "function" && (i = e, e = void 0), typeof t == "string" && (t = Buffer.from(t, e ?? "utf8")), i && this.once("finish", i), t ? super.end(t, i) : super.end(i), this;
	}
}, Gn = (s) => s.isFile() ? "File" : s.isDirectory() ? "Directory" : s.isSymbolicLink() ? "SymbolicLink" : "Unsupported";
var hi = class s {
	tail;
	head;
	length = 0;
	static create(t = []) {
		return new s(t);
	}
	constructor(t = []) {
		for (let e of t) this.push(e);
	}
	*[Symbol.iterator]() {
		for (let t = this.head; t; t = t.next) yield t.value;
	}
	removeNode(t) {
		if (t.list !== this) throw new Error("removing node which does not belong to this list");
		let e = t.next, i = t.prev;
		return e && (e.prev = i), i && (i.next = e), t === this.head && (this.head = e), t === this.tail && (this.tail = i), this.length--, t.next = void 0, t.prev = void 0, t.list = void 0, e;
	}
	unshiftNode(t) {
		if (t === this.head) return;
		t.list && t.list.removeNode(t);
		let e = this.head;
		t.list = this, t.next = e, e && (e.prev = t), this.head = t, this.tail || (this.tail = t), this.length++;
	}
	pushNode(t) {
		if (t === this.tail) return;
		t.list && t.list.removeNode(t);
		let e = this.tail;
		t.list = this, t.prev = e, e && (e.next = t), this.tail = t, this.head || (this.head = t), this.length++;
	}
	push(...t) {
		for (let e = 0, i = t.length; e < i; e++) Yn(this, t[e]);
		return this.length;
	}
	unshift(...t) {
		for (var e = 0, i = t.length; e < i; e++) Kn(this, t[e]);
		return this.length;
	}
	pop() {
		if (!this.tail) return;
		let t = this.tail.value, e = this.tail;
		return this.tail = this.tail.prev, this.tail ? this.tail.next = void 0 : this.head = void 0, e.list = void 0, this.length--, t;
	}
	shift() {
		if (!this.head) return;
		let t = this.head.value, e = this.head;
		return this.head = this.head.next, this.head ? this.head.prev = void 0 : this.tail = void 0, e.list = void 0, this.length--, t;
	}
	forEach(t, e) {
		e = e || this;
		for (let i = this.head, r = 0; i; r++) t.call(e, i.value, r, this), i = i.next;
	}
	forEachReverse(t, e) {
		e = e || this;
		for (let i = this.tail, r = this.length - 1; i; r--) t.call(e, i.value, r, this), i = i.prev;
	}
	get(t) {
		let e = 0, i = this.head;
		for (; i && e < t; e++) i = i.next;
		if (e === t && i) return i.value;
	}
	getReverse(t) {
		let e = 0, i = this.tail;
		for (; i && e < t; e++) i = i.prev;
		if (e === t && i) return i.value;
	}
	map(t, e) {
		e = e || this;
		let i = new s();
		for (let r = this.head; r;) i.push(t.call(e, r.value, this)), r = r.next;
		return i;
	}
	mapReverse(t, e) {
		e = e || this;
		var i = new s();
		for (let r = this.tail; r;) i.push(t.call(e, r.value, this)), r = r.prev;
		return i;
	}
	reduce(t, e) {
		let i, r = this.head;
		if (arguments.length > 1) i = e;
		else if (this.head) r = this.head.next, i = this.head.value;
		else throw new TypeError("Reduce of empty list with no initial value");
		for (var n = 0; r; n++) i = t(i, r.value, n), r = r.next;
		return i;
	}
	reduceReverse(t, e) {
		let i, r = this.tail;
		if (arguments.length > 1) i = e;
		else if (this.tail) r = this.tail.prev, i = this.tail.value;
		else throw new TypeError("Reduce of empty list with no initial value");
		for (let n = this.length - 1; r; n--) i = t(i, r.value, n), r = r.prev;
		return i;
	}
	toArray() {
		let t = new Array(this.length);
		for (let e = 0, i = this.head; i; e++) t[e] = i.value, i = i.next;
		return t;
	}
	toArrayReverse() {
		let t = new Array(this.length);
		for (let e = 0, i = this.tail; i; e++) t[e] = i.value, i = i.prev;
		return t;
	}
	slice(t = 0, e = this.length) {
		e < 0 && (e += this.length), t < 0 && (t += this.length);
		let i = new s();
		if (e < t || e < 0) return i;
		t < 0 && (t = 0), e > this.length && (e = this.length);
		let r = this.head, n = 0;
		for (n = 0; r && n < t; n++) r = r.next;
		for (; r && n < e; n++, r = r.next) i.push(r.value);
		return i;
	}
	sliceReverse(t = 0, e = this.length) {
		e < 0 && (e += this.length), t < 0 && (t += this.length);
		let i = new s();
		if (e < t || e < 0) return i;
		t < 0 && (t = 0), e > this.length && (e = this.length);
		let r = this.length, n = this.tail;
		for (; n && r > e; r--) n = n.prev;
		for (; n && r > t; r--, n = n.prev) i.push(n.value);
		return i;
	}
	splice(t, e = 0, ...i) {
		t > this.length && (t = this.length - 1), t < 0 && (t = this.length + t);
		let r = this.head;
		for (let o = 0; r && o < t; o++) r = r.next;
		let n = [];
		for (let o = 0; r && o < e; o++) n.push(r.value), r = this.removeNode(r);
		r ? r !== this.tail && (r = r.prev) : r = this.tail;
		for (let o of i) r = Zn(this, r, o);
		return n;
	}
	reverse() {
		let t = this.head, e = this.tail;
		for (let i = t; i; i = i.prev) {
			let r = i.prev;
			i.prev = i.next, i.next = r;
		}
		return this.head = e, this.tail = t, this;
	}
};
function Zn(s, t, e) {
	let n = new ue(e, t, t ? t.next : s.head, s);
	return n.next === void 0 && (s.tail = n), n.prev === void 0 && (s.head = n), s.length++, n;
}
function Yn(s, t) {
	s.tail = new ue(t, s.tail, void 0, s), s.head || (s.head = s.tail), s.length++;
}
function Kn(s, t) {
	s.head = new ue(t, void 0, s.head, s), s.tail || (s.tail = s.head), s.length++;
}
var ue = class {
	list;
	next;
	prev;
	value;
	constructor(t, e, i, r) {
		this.list = r, this.value = t, e ? (e.next = this, this.prev = e) : this.prev = void 0, i ? (i.prev = this, this.next = i) : this.next = void 0;
	}
};
var pi = class {
	path;
	absolute;
	entry;
	stat;
	readdir;
	pending = !1;
	pendingLink = !1;
	ignore = !1;
	piped = !1;
	constructor(t, e) {
		this.path = t || "./", this.absolute = e;
	}
}, nr = Buffer.alloc(1024), li = Symbol("onStat"), me = Symbol("ended"), W = Symbol("queue"), pe = Symbol("pendingLinks"), Et = Symbol("current"), Ft = Symbol("process"), Ee = Symbol("processing"), ai = Symbol("processJob"), G = Symbol("jobs"), ls = Symbol("jobDone"), ci = Symbol("addFSEntry"), or = Symbol("addTarEntry"), ds = Symbol("stat"), us = Symbol("readdir"), fi = Symbol("onreaddir"), di = Symbol("pipe"), hr = Symbol("entry"), cs = Symbol("entryOpt"), ui = Symbol("writeEntryClass"), lr = Symbol("write"), fs = Symbol("ondrain"), wt = class extends A {
	sync = !1;
	opt;
	cwd;
	maxReadSize;
	preservePaths;
	strict;
	noPax;
	prefix;
	linkCache;
	statCache;
	file;
	portable;
	zip;
	readdirCache;
	noDirRecurse;
	follow;
	noMtime;
	mtime;
	filter;
	jobs;
	[ui];
	onWriteEntry;
	[W];
	[pe] = /* @__PURE__ */ new Map();
	[G] = 0;
	[Ee] = !1;
	[me] = !1;
	constructor(t = {}) {
		if (super(), this.opt = t, this.file = t.file || "", this.cwd = t.cwd || process.cwd(), this.maxReadSize = t.maxReadSize, this.preservePaths = !!t.preservePaths, this.strict = !!t.strict, this.noPax = !!t.noPax, this.prefix = f(t.prefix || ""), this.linkCache = t.linkCache || /* @__PURE__ */ new Map(), this.statCache = t.statCache || /* @__PURE__ */ new Map(), this.readdirCache = t.readdirCache || /* @__PURE__ */ new Map(), this.onWriteEntry = t.onWriteEntry, this[ui] = de, typeof t.onwarn == "function" && this.on("warn", t.onwarn), this.portable = !!t.portable, t.gzip || t.brotli || t.zstd) {
			if ((t.gzip ? 1 : 0) + (t.brotli ? 1 : 0) + (t.zstd ? 1 : 0) > 1) throw new TypeError("gzip, brotli, zstd are mutually exclusive");
			if (t.gzip && (typeof t.gzip != "object" && (t.gzip = {}), this.portable && (t.gzip.portable = !0), this.zip = new ze(t.gzip)), t.brotli && (typeof t.brotli != "object" && (t.brotli = {}), this.zip = new We(t.brotli)), t.zstd && (typeof t.zstd != "object" && (t.zstd = {}), this.zip = new Ye(t.zstd)), !this.zip) throw new Error("impossible");
			let e = this.zip;
			e.on("data", (i) => super.write(i)), e.on("end", () => super.end()), e.on("drain", () => this[fs]()), this.on("resume", () => e.resume());
		} else this.on("drain", this[fs]);
		this.noDirRecurse = !!t.noDirRecurse, this.follow = !!t.follow, this.noMtime = !!t.noMtime, t.mtime && (this.mtime = t.mtime), this.filter = typeof t.filter == "function" ? t.filter : () => !0, this[W] = new hi(), this[G] = 0, this.jobs = Number(t.jobs) || 4, this[Ee] = !1, this[me] = !1;
	}
	[lr](t) {
		return super.write(t);
	}
	add(t) {
		return this.write(t), this;
	}
	end(t, e, i) {
		return typeof t == "function" && (i = t, t = void 0), typeof e == "function" && (i = e, e = void 0), t && this.add(t), this[me] = !0, this[Ft](), i && i(), this;
	}
	write(t) {
		if (this[me]) throw new Error("write after end");
		return typeof t == "string" ? this[ci](t) : this[or](t), this.flowing;
	}
	[or](t) {
		let e = f(js.resolve(this.cwd, t.path));
		if (!this.filter(t.path, t)) t.resume();
		else {
			let i = new pi(t.path, e);
			i.entry = new oi(t, this[cs](i)), i.entry.on("end", () => this[ls](i)), this[G] += 1, this[W].push(i);
		}
		this[Ft]();
	}
	[ci](t) {
		let e = f(js.resolve(this.cwd, t));
		this[W].push(new pi(t, e)), this[Ft]();
	}
	[ds](t) {
		t.pending = !0, this[G] += 1;
		I[this.follow ? "stat" : "lstat"](t.absolute, (i, r) => {
			t.pending = !1, this[G] -= 1, i ? this.emit("error", i) : this[li](t, r);
		});
	}
	[li](t, e) {
		if (this.statCache.set(t.absolute, e), t.stat = e, !this.filter(t.path, e)) t.ignore = !0;
		else if (e.isFile() && e.nlink > 1 && !this.linkCache.get(`${e.dev}:${e.ino}`) && !this.sync) if (t === this[Et]) this[ai](t);
		else {
			let i = `${e.dev}:${e.ino}`, r = this[pe].get(i);
			r ? r.push(t) : this[pe].set(i, [t]), t.pendingLink = !0, t.pending = !0;
		}
		this[Ft]();
	}
	[us](t) {
		t.pending = !0, this[G] += 1, I.readdir(t.absolute, (e, i) => {
			if (t.pending = !1, this[G] -= 1, e) return this.emit("error", e);
			this[fi](t, i);
		});
	}
	[fi](t, e) {
		this.readdirCache.set(t.absolute, e), t.readdir = e, this[Ft]();
	}
	[Ft]() {
		if (!this[Ee]) {
			this[Ee] = !0;
			for (let t = this[W].head; t && this[G] < this.jobs; t = t.next) if (this[ai](t.value), t.value.ignore) {
				let e = t.next;
				this[W].removeNode(t), t.next = e;
			}
			this[Ee] = !1, this[me] && this[W].length === 0 && this[G] === 0 && (this.zip ? this.zip.end(nr) : (super.write(nr), super.end()));
		}
	}
	get [Et]() {
		return this[W] && this[W].head && this[W].head.value;
	}
	[ls](t) {
		this[W].shift(), this[G] -= 1;
		let { stat: e } = t;
		if (e && e.isFile() && e.nlink > 1) {
			let i = `${e.dev}:${e.ino}`, r = this[pe].get(i);
			if (r) {
				this[pe].delete(i);
				for (let n of r) n.pending = !1, this[ai](n);
			}
		}
		this[Ft]();
	}
	[ai](t) {
		if (t.pending && t.pendingLink && t === this[Et] && (t.pending = !1, t.pendingLink = !1), !t.pending) {
			if (t.entry) {
				t === this[Et] && !t.piped && this[di](t);
				return;
			}
			if (!t.stat) {
				let e = this.statCache.get(t.absolute);
				e ? this[li](t, e) : this[ds](t);
			}
			if (t.stat && !t.ignore) {
				if (!this.noDirRecurse && t.stat.isDirectory() && !t.readdir) {
					let e = this.readdirCache.get(t.absolute);
					if (e ? this[fi](t, e) : this[us](t), !t.readdir) return;
				}
				if (t.entry = this[hr](t), !t.entry) {
					t.ignore = !0;
					return;
				}
				t === this[Et] && !t.piped && this[di](t);
			}
		}
	}
	[cs](t) {
		return {
			onwarn: (e, i, r) => this.warn(e, i, r),
			noPax: this.noPax,
			cwd: this.cwd,
			absolute: t.absolute,
			preservePaths: this.preservePaths,
			maxReadSize: this.maxReadSize,
			strict: this.strict,
			portable: this.portable,
			linkCache: this.linkCache,
			statCache: this.statCache,
			noMtime: this.noMtime,
			mtime: this.mtime,
			prefix: this.prefix,
			onWriteEntry: this.onWriteEntry
		};
	}
	[hr](t) {
		this[G] += 1;
		try {
			return new this[ui](t.path, this[cs](t)).on("end", () => this[ls](t)).on("error", (i) => this.emit("error", i));
		} catch (e) {
			this.emit("error", e);
		}
	}
	[fs]() {
		this[Et] && this[Et].entry && this[Et].entry.resume();
	}
	[di](t) {
		t.piped = !0, t.readdir && t.readdir.forEach((r) => {
			let n = t.path, o = n === "./" ? "" : n.replace(/\/*$/, "/");
			this[ci](o + r);
		});
		let e = t.entry, i = this.zip;
		if (!e) throw new Error("cannot pipe without source");
		i ? e.on("data", (r) => {
			i.write(r) || e.pause();
		}) : e.on("data", (r) => {
			super.write(r) || e.pause();
		});
	}
	pause() {
		return this.zip && this.zip.pause(), super.pause();
	}
	warn(t, e, i = {}) {
		Dt(this, t, e, i);
	}
}, kt = class extends wt {
	sync = !0;
	constructor(t) {
		super(t), this[ui] = ni;
	}
	pause() {}
	resume() {}
	[ds](t) {
		let e = this.follow ? "statSync" : "lstatSync";
		this[li](t, I[e](t.absolute));
	}
	[us](t) {
		this[fi](t, I.readdirSync(t.absolute));
	}
	[di](t) {
		let e = t.entry, i = this.zip;
		if (t.readdir && t.readdir.forEach((r) => {
			let n = t.path, o = n === "./" ? "" : n.replace(/\/*$/, "/");
			this[ci](o + r);
		}), !e) throw new Error("Cannot pipe without source");
		i ? e.on("data", (r) => {
			i.write(r);
		}) : e.on("data", (r) => {
			super[lr](r);
		});
	}
}, Vn = (s, t) => {
	let e = new kt(s), i = new Wt(s.file, { mode: s.mode || 438 });
	e.pipe(i), fr(e, t);
}, $n = (s, t) => {
	let e = new wt(s), i = new et(s.file, { mode: s.mode || 438 });
	e.pipe(i);
	let r = new Promise((n, o) => {
		i.on("error", o), i.on("close", n), e.on("error", o);
	});
	return dr(e, t).catch((n) => e.emit("error", n)), r;
}, fr = (s, t) => {
	t.forEach((e) => {
		e.charAt(0) === "@" ? Ct({
			file: cr.resolve(s.cwd, e.slice(1)),
			sync: !0,
			noResume: !0,
			onReadEntry: (i) => s.add(i)
		}) : s.add(e);
	}), s.end();
}, dr = async (s, t) => {
	for (let e of t) e.charAt(0) === "@" ? await Ct({
		file: cr.resolve(String(s.cwd), e.slice(1)),
		noResume: !0,
		onReadEntry: (i) => {
			s.add(i);
		}
	}) : s.add(e);
	s.end();
}, Xn = (s, t) => {
	let e = new kt(s);
	return fr(e, t), e;
}, qn = (s, t) => {
	let e = new wt(s);
	return dr(e, t).catch((i) => e.emit("error", i)), e;
};
K(Vn, $n, Xn, qn, (s, t) => {
	if (!t?.length) throw new TypeError("no paths specified to add to archive");
});
var Er = (process.env.__FAKE_PLATFORM__ || process.platform) === "win32", { O_CREAT: wr, O_NOFOLLOW: ur, O_TRUNC: Sr, O_WRONLY: yr } = I.constants, Rr = Number(process.env.__FAKE_FS_O_FILENAME__) || I.constants.UV_FS_O_FILEMAP || 0, jn = Er && !!Rr, to = 512 * 1024, eo = Rr | Sr | wr | yr, mr = !Er && typeof ur == "number" ? ur | Sr | wr | yr : null, ms = mr !== null ? () => mr : jn ? (s) => s < to ? eo : "w" : () => "w";
var ps = (s, t, e) => {
	try {
		return Kt.lchownSync(s, t, e);
	} catch (i) {
		if (i?.code !== "ENOENT") throw i;
	}
}, Ei = (s, t, e, i) => {
	Kt.lchown(s, t, e, (r) => {
		i(r && r?.code !== "ENOENT" ? r : null);
	});
}, io = (s, t, e, i, r) => {
	if (t.isDirectory()) Es(cr.resolve(s, t.name), e, i, (n) => {
		if (n) return r(n);
		Ei(cr.resolve(s, t.name), e, i, r);
	});
	else Ei(cr.resolve(s, t.name), e, i, r);
}, Es = (s, t, e, i) => {
	Kt.readdir(s, { withFileTypes: !0 }, (r, n) => {
		if (r) {
			if (r.code === "ENOENT") return i();
			if (r.code !== "ENOTDIR" && r.code !== "ENOTSUP") return i(r);
		}
		if (r || !n.length) return Ei(s, t, e, i);
		let o = n.length, h = null, a = (l) => {
			if (!h) {
				if (l) return i(h = l);
				if (--o === 0) return Ei(s, t, e, i);
			}
		};
		for (let l of n) io(s, l, t, e, a);
	});
}, so = (s, t, e, i) => {
	t.isDirectory() && ws(cr.resolve(s, t.name), e, i), ps(cr.resolve(s, t.name), e, i);
}, ws = (s, t, e) => {
	let i;
	try {
		i = Kt.readdirSync(s, { withFileTypes: !0 });
	} catch (r) {
		let n = r;
		if (n?.code === "ENOENT") return;
		if (n?.code === "ENOTDIR" || n?.code === "ENOTSUP") return ps(s, t, e);
		throw n;
	}
	for (let r of i) so(s, r, t, e);
	return ps(s, t, e);
};
var Se = class extends Error {
	path;
	code;
	syscall = "chdir";
	constructor(t, e) {
		super(`${e}: Cannot cd into '${t}'`), this.path = t, this.code = e;
	}
	get name() {
		return "CwdError";
	}
};
var St = class extends Error {
	path;
	symlink;
	syscall = "symlink";
	code = "TAR_SYMLINK_ERROR";
	constructor(t, e) {
		super("TAR_SYMLINK_ERROR: Cannot extract through symbolic link"), this.symlink = t, this.path = e;
	}
	get name() {
		return "SymlinkError";
	}
};
var no = (s, t) => {
	Kt.stat(s, (e, i) => {
		(e || !i.isDirectory()) && (e = new Se(s, e?.code || "ENOTDIR")), t(e);
	});
}, gr = (s, t, e) => {
	s = f(s);
	let i = t.umask ?? 18, r = t.mode | 448, n = (r & i) !== 0, o = t.uid, h = t.gid, a = typeof o == "number" && typeof h == "number" && (o !== t.processUid || h !== t.processGid), l = t.preserve, c = t.unlink, d = f(t.cwd), y = (E, x) => {
		E ? e(E) : x && a ? Es(x, o, h, (Le) => y(Le)) : n ? Kt.chmod(s, r, e) : e();
	};
	if (s === d) return no(s, y);
	if (l) return ro.mkdir(s, {
		mode: r,
		recursive: !0
	}).then((E) => y(null, E ?? void 0), y);
	Ss(d, f(cr.relative(d, s)).split("/"), r, c, d, void 0, y);
}, Ss = (s, t, e, i, r, n, o) => {
	if (t.length === 0) return o(null, n);
	let h = t.shift(), a = f(cr.resolve(s + "/" + h));
	Kt.mkdir(a, e, br(a, t, e, i, r, n, o));
}, br = (s, t, e, i, r, n, o) => (h) => {
	h ? Kt.lstat(s, (a, l) => {
		if (a) a.path = a.path && f(a.path), o(a);
		else if (l.isDirectory()) Ss(s, t, e, i, r, n, o);
		else if (i) Kt.unlink(s, (c) => {
			if (c) return o(c);
			Kt.mkdir(s, e, br(s, t, e, i, r, n, o));
		});
		else {
			if (l.isSymbolicLink()) return o(new St(s, s + "/" + t.join("/")));
			o(h);
		}
	}) : (n = n || s, Ss(s, t, e, i, r, n, o));
}, oo = (s) => {
	let t = !1, e;
	try {
		t = Kt.statSync(s).isDirectory();
	} catch (i) {
		e = i?.code;
	} finally {
		if (!t) throw new Se(s, e ?? "ENOTDIR");
	}
}, _r = (s, t) => {
	s = f(s);
	let e = t.umask ?? 18, i = t.mode | 448, r = (i & e) !== 0, n = t.uid, o = t.gid, h = typeof n == "number" && typeof o == "number" && (n !== t.processUid || o !== t.processGid), a = t.preserve, l = t.unlink, c = f(t.cwd), d = (E) => {
		E && h && ws(E, n, o), r && Kt.chmodSync(s, i);
	};
	if (s === c) return oo(c), d();
	if (a) return d(Kt.mkdirSync(s, {
		mode: i,
		recursive: !0
	}) ?? void 0);
	let T = f(cr.relative(c, s)).split("/"), D;
	for (let E = T.shift(), x = c; E && (x += "/" + E); E = T.shift()) {
		x = f(cr.resolve(x));
		try {
			Kt.mkdirSync(x, i), D = D || x;
		} catch {
			let Le = Kt.lstatSync(x);
			if (Le.isDirectory()) continue;
			if (l) {
				Kt.unlinkSync(x), Kt.mkdirSync(x, i), D = D || x;
				continue;
			} else if (Le.isSymbolicLink()) return new St(x, x + "/" + T.join("/"));
		}
	}
	return d(D);
};
var ys = Object.create(null), Or = 1e4, Vt = /* @__PURE__ */ new Set(), Tr = (s) => {
	Vt.has(s) ? Vt.delete(s) : ys[s] = s.normalize("NFD").toLocaleLowerCase("en").toLocaleUpperCase("en"), Vt.add(s);
	let t = ys[s], e = Vt.size - Or;
	if (e > Or / 10) {
		for (let i of Vt) if (Vt.delete(i), delete ys[i], --e <= 0) break;
	}
	return t;
};
var ao = (process.env.TESTING_TAR_FAKE_PLATFORM || process.platform) === "win32", lo = (s) => s.split("/").slice(0, -1).reduce((e, i) => {
	let r = e.at(-1);
	return r !== void 0 && (i = join(r, i)), e.push(i || "/"), e;
}, []), yi = class {
	#t = /* @__PURE__ */ new Map();
	#i = /* @__PURE__ */ new Map();
	#s = /* @__PURE__ */ new Set();
	reserve(t, e) {
		t = ao ? ["win32 parallelization disabled"] : t.map((r) => mt(join(Tr(r))));
		let i = new Set(t.map((r) => lo(r)).reduce((r, n) => r.concat(n)));
		this.#i.set(e, {
			dirs: i,
			paths: t
		});
		for (let r of t) {
			let n = this.#t.get(r);
			n ? n.push(e) : this.#t.set(r, [e]);
		}
		for (let r of i) {
			let n = this.#t.get(r);
			if (!n) this.#t.set(r, [new Set([e])]);
			else {
				let o = n.at(-1);
				o instanceof Set ? o.add(e) : n.push(new Set([e]));
			}
		}
		return this.#r(e);
	}
	#n(t) {
		let e = this.#i.get(t);
		if (!e) throw new Error("function does not have any path reservations");
		return {
			paths: e.paths.map((i) => this.#t.get(i)),
			dirs: [...e.dirs].map((i) => this.#t.get(i))
		};
	}
	check(t) {
		let { paths: e, dirs: i } = this.#n(t);
		return e.every((r) => r && r[0] === t) && i.every((r) => r && r[0] instanceof Set && r[0].has(t));
	}
	#r(t) {
		return this.#s.has(t) || !this.check(t) ? !1 : (this.#s.add(t), t(() => this.#e(t)), !0);
	}
	#e(t) {
		if (!this.#s.has(t)) return !1;
		let e = this.#i.get(t);
		if (!e) throw new Error("invalid reservation");
		let { paths: i, dirs: r } = e, n = /* @__PURE__ */ new Set();
		for (let o of i) {
			let h = this.#t.get(o);
			if (!h || h?.[0] !== t) continue;
			let a = h[1];
			if (!a) {
				this.#t.delete(o);
				continue;
			}
			if (h.shift(), typeof a == "function") n.add(a);
			else for (let l of a) n.add(l);
		}
		for (let o of r) {
			let h = this.#t.get(o), a = h?.[0];
			if (!(!h || !(a instanceof Set))) if (a.size === 1 && h.length === 1) {
				this.#t.delete(o);
				continue;
			} else if (a.size === 1) {
				h.shift();
				let l = h[0];
				typeof l == "function" && n.add(l);
			} else a.delete(t);
		}
		return this.#s.delete(t), n.forEach((o) => this.#r(o)), !0;
	}
};
var Lr = () => process.umask();
var Dr = Symbol("onEntry"), _s = Symbol("checkFs"), Nr = Symbol("checkFs2"), Os = Symbol("isReusable"), P = Symbol("makeFs"), Ts = Symbol("file"), xs = Symbol("directory"), gi = Symbol("link"), Ar = Symbol("symlink"), Ir = Symbol("hardlink"), Re = Symbol("ensureNoSymlink"), Cr = Symbol("unsupported"), Fr = Symbol("checkPath"), Rs = Symbol("stripAbsolutePath"), yt = Symbol("mkdir"), O = Symbol("onError"), Ri = Symbol("pending"), kr = Symbol("pend"), $t = Symbol("unpend"), gs = Symbol("ended"), bs = Symbol("maybeClose"), Ls = Symbol("skip"), ge = Symbol("doChown"), be = Symbol("uid"), _e = Symbol("gid"), Oe = Symbol("checkedCwd"), Te = (process.env.TESTING_TAR_FAKE_PLATFORM || process.platform) === "win32", uo = 1024, mo = (s, t) => {
	if (!Te) return Kt.unlink(s, t);
	let e = s + ".DELETE." + randomBytes(16).toString("hex");
	Kt.rename(s, e, (i) => {
		if (i) return t(i);
		Kt.unlink(e, t);
	});
}, po = (s) => {
	if (!Te) return Kt.unlinkSync(s);
	let t = s + ".DELETE." + randomBytes(16).toString("hex");
	Kt.renameSync(s, t), Kt.unlinkSync(t);
}, vr = (s, t, e) => s !== void 0 && s === s >>> 0 ? s : t !== void 0 && t === t >>> 0 ? t : e, Xt = class extends rt {
	[gs] = !1;
	[Oe] = !1;
	[Ri] = 0;
	reservations = new yi();
	transform;
	writable = !0;
	readable = !1;
	uid;
	gid;
	setOwner;
	preserveOwner;
	processGid;
	processUid;
	maxDepth;
	forceChown;
	win32;
	newer;
	keep;
	noMtime;
	preservePaths;
	unlink;
	cwd;
	strip;
	processUmask;
	umask;
	dmode;
	fmode;
	chmod;
	constructor(t = {}) {
		if (t.ondone = () => {
			this[gs] = !0, this[bs]();
		}, super(t), this.transform = t.transform, this.chmod = !!t.chmod, typeof t.uid == "number" || typeof t.gid == "number") {
			if (typeof t.uid != "number" || typeof t.gid != "number") throw new TypeError("cannot set owner without number uid and gid");
			if (t.preserveOwner) throw new TypeError("cannot preserve owner in archive and also set owner explicitly");
			this.uid = t.uid, this.gid = t.gid, this.setOwner = !0;
		} else this.uid = void 0, this.gid = void 0, this.setOwner = !1;
		this.preserveOwner = t.preserveOwner === void 0 && typeof t.uid != "number" ? process.getuid?.() === 0 : !!t.preserveOwner, this.processUid = (this.preserveOwner || this.setOwner) && process.getuid ? process.getuid() : void 0, this.processGid = (this.preserveOwner || this.setOwner) && process.getgid ? process.getgid() : void 0, this.maxDepth = typeof t.maxDepth == "number" ? t.maxDepth : uo, this.forceChown = t.forceChown === !0, this.win32 = !!t.win32 || Te, this.newer = !!t.newer, this.keep = !!t.keep, this.noMtime = !!t.noMtime, this.preservePaths = !!t.preservePaths, this.unlink = !!t.unlink, this.cwd = f(cr.resolve(t.cwd || process.cwd())), this.strip = Number(t.strip) || 0, this.processUmask = this.chmod ? typeof t.processUmask == "number" ? t.processUmask : Lr() : 0, this.umask = typeof t.umask == "number" ? t.umask : this.processUmask, this.dmode = t.dmode || 511 & ~this.umask, this.fmode = t.fmode || 438 & ~this.umask, this.on("entry", (e) => this[Dr](e));
	}
	warn(t, e, i = {}) {
		return (t === "TAR_BAD_ARCHIVE" || t === "TAR_ABORT") && (i.recoverable = !1), super.warn(t, e, i);
	}
	[bs]() {
		this[gs] && this[Ri] === 0 && (this.emit("prefinish"), this.emit("finish"), this.emit("end"));
	}
	[Rs](t, e) {
		let i = t[e], { type: r } = t;
		if (!i || this.preservePaths) return !0;
		let [n, o] = ce(i), h = o.replaceAll(/\\/g, "/").split("/");
		if (h.includes("..") || Te && /^[a-z]:\.\.$/i.test(h[0] ?? "")) {
			if (e === "path" || r === "Link") return this.warn("TAR_ENTRY_ERROR", `${e} contains '..'`, {
				entry: t,
				[e]: i
			}), !1;
			let a = cr.posix.dirname(t.path), l = cr.posix.normalize(cr.posix.join(a, h.join("/")));
			if (l.startsWith("../") || l === "..") return this.warn("TAR_ENTRY_ERROR", `${e} escapes extraction directory`, {
				entry: t,
				[e]: i
			}), !1;
		}
		return n && (t[e] = String(o), this.warn("TAR_ENTRY_INFO", `stripping ${n} from absolute ${e}`, {
			entry: t,
			[e]: i
		})), !0;
	}
	[Fr](t) {
		let e = f(t.path), i = e.split("/");
		if (this.strip) {
			if (i.length < this.strip) return !1;
			if (t.type === "Link") {
				let r = f(String(t.linkpath)).split("/");
				if (r.length >= this.strip) t.linkpath = r.slice(this.strip).join("/");
				else return !1;
			}
			i.splice(0, this.strip), t.path = i.join("/");
		}
		if (isFinite(this.maxDepth) && i.length > this.maxDepth) return this.warn("TAR_ENTRY_ERROR", "path excessively deep", {
			entry: t,
			path: e,
			depth: i.length,
			maxDepth: this.maxDepth
		}), !1;
		if (!this[Rs](t, "path") || !this[Rs](t, "linkpath")) return !1;
		if (t.absolute = cr.isAbsolute(t.path) ? f(cr.resolve(t.path)) : f(cr.resolve(this.cwd, t.path)), !this.preservePaths && typeof t.absolute == "string" && t.absolute.indexOf(this.cwd + "/") !== 0 && t.absolute !== this.cwd) return this.warn("TAR_ENTRY_ERROR", "path escaped extraction target", {
			entry: t,
			path: f(t.path),
			resolvedPath: t.absolute,
			cwd: this.cwd
		}), !1;
		if (t.absolute === this.cwd && t.type !== "Directory" && t.type !== "GNUDumpDir") return !1;
		if (this.win32) {
			let { root: r } = cr.win32.parse(String(t.absolute));
			t.absolute = r + ts(String(t.absolute).slice(r.length));
			let { root: n } = cr.win32.parse(t.path);
			t.path = n + ts(t.path.slice(n.length));
		}
		return !0;
	}
	[Dr](t) {
		if (!this[Fr](t)) return t.resume();
		switch (co.equal(typeof t.absolute, "string"), t.type) {
			case "Directory":
			case "GNUDumpDir": t.mode && (t.mode = t.mode | 448);
			case "File":
			case "OldFile":
			case "ContiguousFile":
			case "Link":
			case "SymbolicLink": return this[_s](t);
			default: return this[Cr](t);
		}
	}
	[O](t, e) {
		t.name === "CwdError" ? this.emit("error", t) : (this.warn("TAR_ENTRY_ERROR", t, { entry: e }), this[$t](), e.resume());
	}
	[yt](t, e, i) {
		gr(f(t), {
			uid: this.uid,
			gid: this.gid,
			processUid: this.processUid,
			processGid: this.processGid,
			umask: this.processUmask,
			preserve: this.preservePaths,
			unlink: this.unlink,
			cwd: this.cwd,
			mode: e
		}, i);
	}
	[ge](t) {
		return this.forceChown || this.preserveOwner && (typeof t.uid == "number" && t.uid !== this.processUid || typeof t.gid == "number" && t.gid !== this.processGid) || typeof this.uid == "number" && this.uid !== this.processUid || typeof this.gid == "number" && this.gid !== this.processGid;
	}
	[be](t) {
		return vr(this.uid, t.uid, this.processUid);
	}
	[_e](t) {
		return vr(this.gid, t.gid, this.processGid);
	}
	[Ts](t, e) {
		let i = typeof t.mode == "number" ? t.mode & 4095 : this.fmode, r = new et(String(t.absolute), {
			flags: ms(t.size),
			mode: i,
			autoClose: !1
		});
		r.on("error", (a) => {
			r.fd && Kt.close(r.fd, () => {}), r.write = () => !0, this[O](a, t), e();
		});
		let n = 1, o = (a) => {
			if (a) {
				r.fd && Kt.close(r.fd, () => {}), this[O](a, t), e();
				return;
			}
			--n === 0 && r.fd !== void 0 && Kt.close(r.fd, (l) => {
				l ? this[O](l, t) : this[$t](), e();
			});
		};
		r.on("finish", () => {
			let a = String(t.absolute), l = r.fd;
			if (typeof l == "number" && t.mtime && !this.noMtime) {
				n++;
				let c = t.atime || /* @__PURE__ */ new Date(), d = t.mtime;
				Kt.futimes(l, c, d, (y) => y ? Kt.utimes(a, c, d, (T) => o(T && y)) : o());
			}
			if (typeof l == "number" && this[ge](t)) {
				n++;
				let c = this[be](t), d = this[_e](t);
				typeof c == "number" && typeof d == "number" && Kt.fchown(l, c, d, (y) => y ? Kt.chown(a, c, d, (T) => o(T && y)) : o());
			}
			o();
		});
		let h = this.transform && this.transform(t) || t;
		h !== t && (h.on("error", (a) => {
			this[O](a, t), e();
		}), t.pipe(h)), h.pipe(r);
	}
	[xs](t, e) {
		let i = typeof t.mode == "number" ? t.mode & 4095 : this.dmode;
		this[yt](String(t.absolute), i, (r) => {
			if (r) {
				this[O](r, t), e();
				return;
			}
			let n = 1, o = () => {
				--n === 0 && (e(), this[$t](), t.resume());
			};
			t.mtime && !this.noMtime && (n++, Kt.utimes(String(t.absolute), t.atime || /* @__PURE__ */ new Date(), t.mtime, o)), this[ge](t) && (n++, Kt.chown(String(t.absolute), Number(this[be](t)), Number(this[_e](t)), o)), o();
		});
	}
	[Cr](t) {
		t.unsupported = !0, this.warn("TAR_ENTRY_UNSUPPORTED", `unsupported entry type: ${t.type}`, { entry: t }), t.resume();
	}
	[Ar](t, e) {
		let i = f(cr.relative(this.cwd, cr.resolve(cr.dirname(String(t.absolute)), String(t.linkpath)))).split("/");
		this[Re](t, this.cwd, i, () => this[gi](t, String(t.linkpath), "symlink", e), (r) => {
			this[O](r, t), e();
		});
	}
	[Ir](t, e) {
		let i = f(cr.resolve(this.cwd, String(t.linkpath))), r = f(String(t.linkpath)).split("/");
		this[Re](t, this.cwd, r, () => this[gi](t, i, "link", e), (n) => {
			this[O](n, t), e();
		});
	}
	[Re](t, e, i, r, n) {
		let o = i.shift();
		if (this.preservePaths || o === void 0) return r();
		let h = cr.resolve(e, o);
		Kt.lstat(h, (a, l) => {
			if (a) return r();
			if (l?.isSymbolicLink()) return n(new St(h, cr.resolve(h, i.join("/"))));
			this[Re](t, h, i, r, n);
		});
	}
	[kr]() {
		this[Ri]++;
	}
	[$t]() {
		this[Ri]--, this[bs]();
	}
	[Ls](t) {
		this[$t](), t.resume();
	}
	[Os](t, e) {
		return t.type === "File" && !this.unlink && e.isFile() && e.nlink <= 1 && !Te;
	}
	[_s](t) {
		this[kr]();
		let e = [t.path];
		t.linkpath && e.push(t.linkpath), this.reservations.reserve(e, (i) => this[Nr](t, i));
	}
	[Nr](t, e) {
		let i = (h) => {
			e(h);
		}, r = () => {
			this[yt](this.cwd, this.dmode, (h) => {
				if (h) {
					this[O](h, t), i();
					return;
				}
				this[Oe] = !0, n();
			});
		}, n = () => {
			if (t.absolute !== this.cwd) {
				let h = f(cr.dirname(String(t.absolute)));
				if (h !== this.cwd) return this[yt](h, this.dmode, (a) => {
					if (a) {
						this[O](a, t), i();
						return;
					}
					o();
				});
			}
			o();
		}, o = () => {
			Kt.lstat(String(t.absolute), (h, a) => {
				if (a && (this.keep || this.newer && a.mtime > (t.mtime ?? a.mtime))) {
					this[Ls](t), i();
					return;
				}
				if (h || this[Os](t, a)) return this[P](null, t, i);
				if (a.isDirectory()) {
					if (t.type === "Directory") {
						let l = this.chmod && t.mode && (a.mode & 4095) !== t.mode, c = (d) => this[P](d ?? null, t, i);
						return l ? Kt.chmod(String(t.absolute), Number(t.mode), c) : c();
					}
					if (t.absolute !== this.cwd) return Kt.rmdir(String(t.absolute), (l) => this[P](l ?? null, t, i));
				}
				if (t.absolute === this.cwd) return this[P](null, t, i);
				mo(String(t.absolute), (l) => this[P](l ?? null, t, i));
			});
		};
		this[Oe] ? n() : r();
	}
	[P](t, e, i) {
		if (t) {
			this[O](t, e), i();
			return;
		}
		switch (e.type) {
			case "File":
			case "OldFile":
			case "ContiguousFile": return this[Ts](e, i);
			case "Link": return this[Ir](e, i);
			case "SymbolicLink": return this[Ar](e, i);
			case "Directory":
			case "GNUDumpDir": return this[xs](e, i);
		}
	}
	[gi](t, e, i, r) {
		Kt[i](e, String(t.absolute), (n) => {
			n ? this[O](n, t) : (this[$t](), t.resume()), r();
		});
	}
}, ye = (s) => {
	try {
		return [null, s()];
	} catch (t) {
		return [t, null];
	}
}, xe = class extends Xt {
	sync = !0;
	[P](t, e) {
		return super[P](t, e, () => {});
	}
	[_s](t) {
		if (!this[Oe]) {
			let n = this[yt](this.cwd, this.dmode);
			if (n) return this[O](n, t);
			this[Oe] = !0;
		}
		if (t.absolute !== this.cwd) {
			let n = f(cr.dirname(String(t.absolute)));
			if (n !== this.cwd) {
				let o = this[yt](n, this.dmode);
				if (o) return this[O](o, t);
			}
		}
		let [e, i] = ye(() => Kt.lstatSync(String(t.absolute)));
		if (i && (this.keep || this.newer && i.mtime > (t.mtime ?? i.mtime))) return this[Ls](t);
		if (e || this[Os](t, i)) return this[P](null, t);
		if (i.isDirectory()) {
			if (t.type === "Directory") {
				let [h] = this.chmod && t.mode && (i.mode & 4095) !== t.mode ? ye(() => {
					Kt.chmodSync(String(t.absolute), Number(t.mode));
				}) : [];
				return this[P](h, t);
			}
			let [n] = ye(() => Kt.rmdirSync(String(t.absolute)));
			this[P](n, t);
		}
		let [r] = t.absolute === this.cwd ? [] : ye(() => po(String(t.absolute)));
		this[P](r, t);
	}
	[Ts](t, e) {
		let i = typeof t.mode == "number" ? t.mode & 4095 : this.fmode, r = (h) => {
			let a;
			try {
				Kt.closeSync(n);
			} catch (l) {
				a = l;
			}
			(h || a) && this[O](h || a, t), e();
		}, n;
		try {
			n = Kt.openSync(String(t.absolute), ms(t.size), i);
		} catch (h) {
			return r(h);
		}
		let o = this.transform && this.transform(t) || t;
		o !== t && (o.on("error", (h) => this[O](h, t)), t.pipe(o)), o.on("data", (h) => {
			try {
				Kt.writeSync(n, h, 0, h.length);
			} catch (a) {
				r(a);
			}
		}), o.on("end", () => {
			let h = null;
			if (t.mtime && !this.noMtime) {
				let a = t.atime || /* @__PURE__ */ new Date(), l = t.mtime;
				try {
					Kt.futimesSync(n, a, l);
				} catch (c) {
					try {
						Kt.utimesSync(String(t.absolute), a, l);
					} catch {
						h = c;
					}
				}
			}
			if (this[ge](t)) {
				let a = this[be](t), l = this[_e](t);
				try {
					Kt.fchownSync(n, Number(a), Number(l));
				} catch (c) {
					try {
						Kt.chownSync(String(t.absolute), Number(a), Number(l));
					} catch {
						h = h || c;
					}
				}
			}
			r(h);
		});
	}
	[xs](t, e) {
		let i = typeof t.mode == "number" ? t.mode & 4095 : this.dmode, r = this[yt](String(t.absolute), i);
		if (r) {
			this[O](r, t), e();
			return;
		}
		if (t.mtime && !this.noMtime) try {
			Kt.utimesSync(String(t.absolute), t.atime || /* @__PURE__ */ new Date(), t.mtime);
		} catch {}
		if (this[ge](t)) try {
			Kt.chownSync(String(t.absolute), Number(this[be](t)), Number(this[_e](t)));
		} catch {}
		e(), t.resume();
	}
	[yt](t, e) {
		try {
			return _r(f(t), {
				uid: this.uid,
				gid: this.gid,
				processUid: this.processUid,
				processGid: this.processGid,
				umask: this.processUmask,
				preserve: this.preservePaths,
				unlink: this.unlink,
				cwd: this.cwd,
				mode: e
			});
		} catch (i) {
			return i;
		}
	}
	[Re](t, e, i, r, n) {
		if (this.preservePaths || i.length === 0) return r();
		let o = e;
		for (let h of i) {
			o = cr.resolve(o, h);
			let [a, l] = ye(() => Kt.lstatSync(o));
			if (a) return r();
			if (l.isSymbolicLink()) return n(new St(o, cr.resolve(e, i.join("/"))));
		}
		r();
	}
	[gi](t, e, i, r) {
		let n = `${i}Sync`;
		try {
			Kt[n](e, String(t.absolute)), r(), t.resume();
		} catch (o) {
			return this[O](o, t);
		}
	}
};
var Eo = (s) => {
	let t = new xe(s), e = s.file, i = Kt.statSync(e);
	new Be(e, {
		readSize: s.maxReadSize || 16 * 1024 * 1024,
		size: i.size
	}).pipe(t);
}, wo = (s, t) => {
	let e = new Xt(s), i = s.maxReadSize || 16 * 1024 * 1024, r = s.file;
	return new Promise((o, h) => {
		e.on("error", h), e.on("close", o), Kt.stat(r, (a, l) => {
			if (a) h(a);
			else {
				let c = new _t(r, {
					readSize: i,
					size: l.size
				});
				c.on("error", h), c.pipe(e);
			}
		});
	});
}, So = K(Eo, wo, (s) => new xe(s), (s) => new Xt(s), (s, t) => {
	t?.length && Qi(s, t);
});
var yo = (s, t) => {
	let e = new kt(s), i = !0, r, n;
	try {
		try {
			r = Kt.openSync(s.file, "r+");
		} catch (a) {
			if (a?.code === "ENOENT") r = Kt.openSync(s.file, "w+");
			else throw a;
		}
		let o = Kt.fstatSync(r), h = Buffer.alloc(512);
		t: for (n = 0; n < o.size; n += 512) {
			for (let c = 0, d = 0; c < 512; c += d) {
				if (d = Kt.readSync(r, h, c, h.length - c, n + c), n === 0 && h[0] === 31 && h[1] === 139) throw new Error("cannot append to compressed archives");
				if (!d) break t;
			}
			let a = new F(h);
			if (!a.cksumValid) break;
			let l = 512 * Math.ceil((a.size || 0) / 512);
			if (n + l + 512 > o.size) break;
			n += l, s.mtimeCache && a.mtime && s.mtimeCache.set(String(a.path), a.mtime);
		}
		i = !1, Ro(s, e, n, r, t);
	} finally {
		if (i) try {
			Kt.closeSync(r);
		} catch {}
	}
}, Ro = (s, t, e, i, r) => {
	let n = new Wt(s.file, {
		fd: i,
		start: e
	});
	t.pipe(n), bo(t, r);
}, go = (s, t) => {
	t = Array.from(t);
	let e = new wt(s), i = (n, o, h) => {
		let a = (T, D) => {
			T ? Kt.close(n, (E) => h(T)) : h(null, D);
		}, l = 0;
		if (o === 0) return a(null, 0);
		let c = 0, d = Buffer.alloc(512), y = (T, D) => {
			if (T || D === void 0) return a(T);
			if (c += D, c < 512 && D) return Kt.read(n, d, c, d.length - c, l + c, y);
			if (l === 0 && d[0] === 31 && d[1] === 139) return a(/* @__PURE__ */ new Error("cannot append to compressed archives"));
			if (c < 512) return a(null, l);
			let E = new F(d);
			if (!E.cksumValid) return a(null, l);
			let x = 512 * Math.ceil((E.size ?? 0) / 512);
			if (l + x + 512 > o || (l += x + 512, l >= o)) return a(null, l);
			s.mtimeCache && E.mtime && s.mtimeCache.set(String(E.path), E.mtime), c = 0, Kt.read(n, d, 0, 512, l, y);
		};
		Kt.read(n, d, 0, 512, l, y);
	};
	return new Promise((n, o) => {
		e.on("error", o);
		let h = "r+", a = (l, c) => {
			if (l && l.code === "ENOENT" && h === "r+") return h = "w+", Kt.open(s.file, h, a);
			if (l || !c) return o(l);
			Kt.fstat(c, (d, y) => {
				if (d) return Kt.close(c, () => o(d));
				i(c, y.size, (T, D) => {
					if (T) return o(T);
					let E = new et(s.file, {
						fd: c,
						start: D
					});
					e.pipe(E), E.on("error", o), E.on("close", n), _o(e, t);
				});
			});
		};
		Kt.open(s.file, h, a);
	});
}, bo = (s, t) => {
	t.forEach((e) => {
		e.charAt(0) === "@" ? Ct({
			file: cr.resolve(s.cwd, e.slice(1)),
			sync: !0,
			noResume: !0,
			onReadEntry: (i) => s.add(i)
		}) : s.add(e);
	}), s.end();
}, _o = async (s, t) => {
	for (let e of t) e.charAt(0) === "@" ? await Ct({
		file: cr.resolve(String(s.cwd), e.slice(1)),
		noResume: !0,
		onReadEntry: (i) => s.add(i)
	}) : s.add(e);
	s.end();
}, vt = K(yo, go, () => {
	throw new TypeError("file is required");
}, () => {
	throw new TypeError("file is required");
}, (s, t) => {
	if (!Bs(s)) throw new TypeError("file is required");
	if (s.gzip || s.brotli || s.zstd || s.file.endsWith(".br") || s.file.endsWith(".tbr")) throw new TypeError("cannot append to compressed archives");
	if (!t?.length) throw new TypeError("no paths specified to add/replace");
});
K(vt.syncFile, vt.asyncFile, vt.syncNoFile, vt.asyncNoFile, (s, t = []) => {
	vt.validate?.(s, t), To(s);
});
var To = (s) => {
	let t = s.filter;
	s.mtimeCache || (s.mtimeCache = /* @__PURE__ */ new Map()), s.filter = t ? (e, i) => t(e, i) && !((s.mtimeCache?.get(e) ?? i.mtime ?? 0) > (i.mtime ?? 0)) : (e, i) => !((s.mtimeCache?.get(e) ?? i.mtime ?? 0) > (i.mtime ?? 0));
};
//#endregion
//#region lib/types/seed-store.js
/** Deterministic archive transport for the desktop seed's pnpm store. */
/** Directory containing the seed's uncompressed pnpm store archives. */
const SEED_STORE_ARCHIVE_DIR = "store-archives";
/** Manifest describing the deterministic pnpm store archive set. */
const SEED_STORE_ARCHIVE_MANIFEST = "store-archives.json";
const ARCHIVE_NAME_PATTERN = /^store-[0-9a-f]{2}\.tar$/u;
const STORE_VERSION_PATTERN = /^v\d+$/u;
function shardFor(path, shardCount) {
	return createHash("sha256").update(path).digest().readUInt32BE(0) % shardCount;
}
function readArchiveManifest(seedRoot) {
	const path = join(seedRoot, SEED_STORE_ARCHIVE_MANIFEST);
	const value = JSON.parse(readFileSync(path, "utf8"));
	if (typeof value !== "object" || value === null) throw new Error(`desktop seed: invalid pnpm store archive manifest ${path}`);
	const candidate = value;
	if (candidate.schemaVersion !== 1 || !Number.isSafeInteger(candidate.shardCount) || candidate.shardCount < 1 || candidate.shardCount > 256 || !Array.isArray(candidate.archives) || candidate.archives.length === 0) throw new Error(`desktop seed: invalid pnpm store archive manifest ${path}`);
	const names = /* @__PURE__ */ new Set();
	const archives = candidate.archives.map((entry) => {
		if (typeof entry !== "object" || entry === null) throw new Error(`desktop seed: invalid pnpm store archive record in ${path}`);
		const record = entry;
		if (typeof record.file !== "string" || !ARCHIVE_NAME_PATTERN.test(record.file) || names.has(record.file) || !Number.isSafeInteger(record.entries) || record.entries < 1) throw new Error(`desktop seed: invalid pnpm store archive record in ${path}`);
		if (Number.parseInt(record.file.slice(6, -4), 16) >= candidate.shardCount) throw new Error(`desktop seed: pnpm store archive shard is outside the manifest range in ${path}`);
		names.add(record.file);
		return {
			file: record.file,
			entries: record.entries
		};
	});
	return {
		schemaVersion: 1,
		shardCount: candidate.shardCount,
		archives
	};
}
function assertArchivePath(path) {
	if (path === "" || path.startsWith("/") || path.includes("\\") || path.includes("\0") || path.split("/").some((part) => part === "" || part === "." || part === "..")) throw new Error(`desktop seed: unsafe pnpm store archive path ${JSON.stringify(path)}`);
}
function mergeStoreIndex(source, destination) {
	if (!existsSync(destination)) {
		copyFileSync(source, destination);
		return;
	}
	const database = new DatabaseSync(destination);
	let attached = false;
	try {
		database.exec("PRAGMA busy_timeout=5000");
		database.prepare("ATTACH DATABASE ? AS seed").run(source);
		attached = true;
		database.exec("BEGIN IMMEDIATE");
		let committed = false;
		try {
			database.exec("INSERT OR REPLACE INTO package_index (key, data) SELECT key, data FROM seed.package_index");
			database.exec("COMMIT");
			committed = true;
		} finally {
			if (!committed) database.exec("ROLLBACK");
		}
	} finally {
		if (attached) database.exec("DETACH DATABASE seed");
		database.close();
	}
}
/**
* Merge a completely extracted seed store into Desktop's persistent pnpm store.
* @param source - Verified temporary store extraction.
* @param destination - Desktop-owned persistent pnpm store.
*/
function mergePnpmStore(source, destination) {
	mkdirSync(destination, {
		recursive: true,
		mode: 448
	});
	const indexPaths = readdirSync(source, { withFileTypes: true }).filter((entry) => entry.isDirectory() && STORE_VERSION_PATTERN.test(entry.name) && existsSync(join(source, entry.name, "index.db"))).map((entry) => `${entry.name}/index.db`);
	const indexes = new Set(indexPaths);
	cpSync(source, destination, {
		recursive: true,
		force: true,
		filter: (path) => !indexes.has(relative(source, path).split(sep).join("/"))
	});
	for (const path of indexPaths) mergeStoreIndex(join(source, ...path.split("/")), join(destination, ...path.split("/")));
}
/**
* Validate and extract a packaged pnpm store archive set into an empty directory.
* @param seedRoot - verified packaged seed directory.
* @param destination - empty Desktop-owned temporary extraction directory.
*/
function extractPnpmStoreArchives(seedRoot, destination) {
	const manifest = readArchiveManifest(seedRoot);
	const archiveRoot = join(seedRoot, SEED_STORE_ARCHIVE_DIR);
	const actualFiles = readdirSync(archiveRoot, { withFileTypes: true }).map((entry) => {
		if (!entry.isFile() || entry.isSymbolicLink()) throw new Error(`desktop seed: invalid pnpm store archive entry ${entry.name}`);
		return entry.name;
	}).sort();
	const expectedFiles = manifest.archives.map((archive) => archive.file).sort();
	if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) throw new Error("desktop seed: pnpm store archive set does not match its manifest");
	if (existsSync(destination) && readdirSync(destination).length !== 0) throw new Error(`desktop seed: pnpm store extraction directory is not empty: ${destination}`);
	mkdirSync(destination, {
		recursive: true,
		mode: 448
	});
	const paths = /* @__PURE__ */ new Set();
	for (const archive of manifest.archives) {
		const archivePath = join(archiveRoot, archive.file);
		const archiveShard = Number.parseInt(archive.file.slice(6, -4), 16);
		let entries = 0;
		Ct({
			file: archivePath,
			onReadEntry: (entry) => {
				if (entry.type !== "File" && entry.type !== "OldFile") throw new Error(`desktop seed: unsupported pnpm store archive entry type ${entry.type}`);
				assertArchivePath(entry.path);
				if (shardFor(entry.path, manifest.shardCount) !== archiveShard) throw new Error(`desktop seed: pnpm store path is assigned to the wrong archive shard: ${entry.path}`);
				if (paths.has(entry.path)) throw new Error(`desktop seed: duplicate pnpm store archive path ${entry.path}`);
				paths.add(entry.path);
				entries += 1;
			},
			strict: true,
			sync: true
		});
		if (entries !== archive.entries) throw new Error(`desktop seed: pnpm store archive ${archive.file} has an unexpected entry count`);
	}
	for (const archive of manifest.archives) So({
		chmod: true,
		cwd: destination,
		file: join(archiveRoot, archive.file),
		noMtime: true,
		preservePaths: false,
		processUmask: 0,
		strict: true,
		sync: true
	});
}
//#endregion
//#region lib/types/project-manager.js
/** Transactional owner of the reserved desktop profile and its private pnpm state. */
/** Files the package transaction copies between active and staging projects. */
const DESKTOP_PROJECT_FILES = [
	"package.json",
	"pnpm-lock.yaml",
	"pnpm-workspace.yaml",
	"desktop-release.json",
	DESKTOP_PACKAGE_SET_FILE
];
const PROJECT_NAME = "@deepseek-ai/dsh-desktop-runtime";
const DSH_PACKAGE = "@deepseek-ai/dsh";
const CORE_BUILD_PACKAGE = "@deepseek-ai/dsh-subprocess-local";
const DESKTOP_PROFILE_BUNDLES = ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"];
const WORKSPACE_SETTINGS = "nodeLinker: hoisted\nautoInstallPeers: false\nstrictDepBuilds: true\n";
const PACKAGE_NAME_PATTERN = /^(?:@[a-z0-9][a-z0-9._~-]*\/[a-z0-9][a-z0-9._~-]*|[a-z0-9][a-z0-9._~-]*)$/u;
const VERSION_PATTERN = /^[0-9A-Za-z][0-9A-Za-z.+_-]*$/u;
const DESKTOP_REGISTRY = "https://registry.npmjs.org/";
function errorOf$2(reason, fallback) {
	return reason instanceof Error ? reason : new Error(fallback);
}
function writeJson(path, value) {
	writeFileSync(path, `${JSON.stringify(value, void 0, 2)}\n`, { mode: 384 });
}
function readJson(path) {
	return JSON.parse(readFileSync(path, "utf8"));
}
function workspaceFile(overrides = {}) {
	const entries = Object.entries(overrides).sort(([left], [right]) => left.localeCompare(right));
	const overrideSection = entries.length === 0 ? "" : `overrides:\n${entries.map(([name, spec]) => `  ${JSON.stringify(name)}: ${JSON.stringify(spec)}`).join("\n")}\n`;
	const coreBuildSpec = overrides[CORE_BUILD_PACKAGE];
	const coreBuildKey = coreBuildSpec === void 0 ? CORE_BUILD_PACKAGE : `${CORE_BUILD_PACKAGE}@${coreBuildSpec.replace("file:./", "file:")}`;
	return `packages:\n  - .\n\n${overrideSection}${WORKSPACE_SETTINGS}allowBuilds:\n  node-pty: true\n  koffi: true\n  fs-ext: true\n  ${JSON.stringify(coreBuildKey)}: true\n  '@google/genai': false\n  protobufjs: false\n  node-addon-require-builtin: false\n`;
}
function releaseFile(projectDir) {
	return parseDesktopRelease(readJson(join(projectDir, "desktop-release.json")));
}
function isRecord(value) {
	return typeof value === "object" && value !== null;
}
function isDescendant(root, target) {
	const child = relative(root, target);
	return child !== "" && child !== ".." && !child.startsWith(`..${sep}`) && !isAbsolute(child);
}
function assertPackageName(name) {
	if (!PACKAGE_NAME_PATTERN.test(name)) throw new Error(`desktop project: invalid npm package name ${JSON.stringify(name)}`);
}
function assertVersion(version) {
	if (!VERSION_PATTERN.test(version)) throw new Error(`desktop project: invalid exact version ${JSON.stringify(version)}`);
}
/**
* Validate one registry package spec and return its requested package name when explicit.
* @param spec - npm registry name with an optional version or tag.
* @returns package name, or undefined when the spec's final name is registry-resolved.
*/
function packageNameFromSpec(spec) {
	if (spec === "" || spec.startsWith("-") || /[\s\\]/u.test(spec) || spec.includes("://") || spec.startsWith("file:")) throw new Error(`desktop project: unsupported npm package spec ${JSON.stringify(spec)}`);
	if (spec.startsWith("@")) {
		const slash = spec.indexOf("/");
		if (slash === -1) throw new Error(`desktop project: invalid scoped package spec ${JSON.stringify(spec)}`);
		const versionAt = spec.indexOf("@", slash);
		const name = versionAt === -1 ? spec : spec.slice(0, versionAt);
		assertPackageName(name);
		if (versionAt !== -1) assertVersion(spec.slice(versionAt + 1));
		return name;
	}
	const versionAt = spec.indexOf("@");
	const name = versionAt === -1 ? spec : spec.slice(0, versionAt);
	assertPackageName(name);
	if (versionAt !== -1) assertVersion(spec.slice(versionAt + 1));
	return name;
}
function removeOwnedDirectory(path) {
	if (!existsSync(path)) return;
	const stat = lstatSync(path);
	if (stat.isSymbolicLink()) {
		unlinkSync(path);
		return;
	}
	if (!stat.isDirectory()) throw new Error(`desktop project: owned directory path is not a directory: ${path}`);
	rmSync(path, { recursive: true });
}
function copyMetadata(source, target) {
	mkdirSync(target, {
		recursive: true,
		mode: 448
	});
	for (const filename of DESKTOP_PROJECT_FILES) {
		const from = join(source, filename);
		if (existsSync(from)) copyFileSync(from, join(target, filename), constants.COPYFILE_EXCL);
	}
	cpSync(join(source, DESKTOP_PACKAGES_DIR), join(target, DESKTOP_PACKAGES_DIR), {
		recursive: true,
		force: false,
		errorOnExist: true
	});
}
function seedFiles(root) {
	const files = [];
	const visit = (directory) => {
		for (const entry of readdirSync(directory, { withFileTypes: true })) {
			const path = join(directory, entry.name);
			const relativePath = path.slice(root.length + 1).split(sep).join("/");
			if (relativePath === "integrity.json") continue;
			if (entry.isSymbolicLink()) throw new Error(`desktop seed: symbolic link is not allowed: ${relativePath}`);
			if (entry.isDirectory()) {
				visit(path);
				continue;
			}
			if (!entry.isFile()) throw new Error(`desktop seed: unsupported file type: ${relativePath}`);
			const body = readFileSync(path);
			files.push({
				path: relativePath,
				bytes: body.byteLength,
				sha256: createHash("sha256").update(body).digest("hex")
			});
		}
	};
	visit(root);
	return files.sort((left, right) => left.path.localeCompare(right.path));
}
/** Verify the packaged offline seed before any content enters writable desktop state. */
function verifySeedIntegrity(seedDir) {
	const integrityPath = join(seedDir, "integrity.json");
	const integrity = readJson(integrityPath);
	if (!isRecord(integrity) || integrity.schemaVersion !== 2 || !Array.isArray(integrity.files)) throw new Error(`desktop seed: invalid integrity inventory ${integrityPath}`);
	const expected = integrity.files.map((record) => {
		if (!isRecord(record) || typeof record.path !== "string" || record.path === "" || record.path.startsWith("/") || record.path.split("/").includes("..") || typeof record.bytes !== "number" || !Number.isSafeInteger(record.bytes) || record.bytes < 0 || typeof record.sha256 !== "string" || !/^[a-f0-9]{64}$/u.test(record.sha256)) throw new Error(`desktop seed: invalid integrity record in ${integrityPath}`);
		return {
			path: record.path,
			bytes: record.bytes,
			sha256: record.sha256
		};
	}).sort((left, right) => left.path.localeCompare(right.path));
	const actual = seedFiles(seedDir);
	if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error("desktop seed: integrity verification failed");
}
function projectManifest(projectDir) {
	const path = join(projectDir, "package.json");
	const value = readJson(path);
	const dsh = isRecord(value) && isRecord(value.dsh) ? value.dsh : void 0;
	const profile = isRecord(dsh?.profile) ? dsh.profile : void 0;
	if (!isRecord(value) || value.name !== PROJECT_NAME || value.private !== true || typeof value.version !== "string" || !isRecord(value.dependencies) || !Array.isArray(profile?.bundles) || !profile.bundles.every((bundle) => typeof bundle === "string")) throw new Error(`desktop project: invalid desktop profile manifest ${path}`);
	const manifest = value;
	const packageSet = readDesktopCorePackageSet(projectDir, releaseFile(projectDir).version);
	const expectedOverrides = desktopCorePackageOverrides(packageSet);
	if (manifest.dependencies[DSH_PACKAGE] !== desktopDshPackageSpec(packageSet) || Object.entries(expectedOverrides).some(([name, spec]) => manifest.dependencies[name] !== spec) || readFileSync(join(projectDir, "pnpm-workspace.yaml"), "utf8") !== workspaceFile(expectedOverrides)) throw new Error(`desktop project: core package mapping does not match ${DESKTOP_PACKAGE_SET_FILE}`);
	return manifest;
}
function profilePluginNames(projectDir) {
	const bundles = projectManifest(projectDir).dsh.profile.bundles;
	if (!DESKTOP_PROFILE_BUNDLES.every((bundle, index) => bundles[index] === bundle)) throw new Error("desktop project: profile must begin with the built-in desktop bundle list");
	const plugins = bundles.slice(DESKTOP_PROFILE_BUNDLES.length);
	if (new Set(bundles).size !== bundles.length) throw new Error("desktop project: profile bundle list contains a duplicate package");
	for (const plugin of plugins) assertPackageName(plugin);
	return plugins;
}
function pluginRecords(projectDir) {
	return profilePluginNames(projectDir).map((name) => inspectPlugin(projectDir, name));
}
function writeProfilePlugins(projectDir, plugins) {
	const manifest = projectManifest(projectDir);
	writeJson(join(projectDir, "package.json"), {
		...manifest,
		dsh: {
			...manifest.dsh,
			profile: {
				...manifest.dsh.profile,
				bundles: [...DESKTOP_PROFILE_BUNDLES, ...plugins.map((plugin) => plugin.name)]
			}
		}
	});
}
function inspectPlugin(projectDir, requestedName) {
	const manifestPath = join(projectDir, "node_modules", ...requestedName.split("/"), "package.json");
	if (!existsSync(manifestPath)) throw new Error(`desktop project: installed package ${JSON.stringify(requestedName)} has no manifest`);
	const manifest = readJson(manifestPath);
	if (!isRecord(manifest) || manifest.name !== requestedName || typeof manifest.version !== "string") throw new Error(`desktop project: installed package ${JSON.stringify(requestedName)} has inconsistent name or version`);
	const dsh = manifest.dsh;
	const bundle = isRecord(dsh) ? dsh.bundle : void 0;
	const patch = isRecord(bundle) ? bundle.patch : void 0;
	if (typeof patch !== "string" || patch === "") throw new Error(`desktop project: ${requestedName}@${manifest.version} does not declare dsh.bundle.patch`);
	const packageDir = dirname(manifestPath);
	const patchPath = resolve(packageDir, patch);
	if (patchPath !== packageDir && !patchPath.startsWith(packageDir + sep) || !existsSync(patchPath)) throw new Error(`desktop project: ${requestedName}@${manifest.version} declares an invalid bundle patch`);
	return {
		name: requestedName,
		version: manifest.version
	};
}
/** Transactional desktop npm project manager. */
var DesktopProjectManager = class {
	paths;
	runtime;
	lockDescriptor;
	/**
	* @param paths - Electron-owned package state and reserved desktop profile paths.
	* @param runtime - absolute bundled Node.js and pnpm entry paths.
	*/
	constructor(paths, runtime) {
		this.paths = paths;
		this.runtime = runtime;
	}
	/** Recover an interrupted directory replacement before reading the active project. */
	recover() {
		if (!existsSync(this.paths.pending)) return;
		const value = readJson(this.paths.pending);
		if (!isRecord(value) || value.schemaVersion !== 1 || typeof value.id !== "string" || typeof value.stagingProfile !== "string" || !isDescendant(this.paths.staging, value.stagingProfile) || value.step !== "prepared" && value.step !== "active-moved" && value.step !== "staging-activated") throw new Error(`desktop project: invalid activation journal ${this.paths.pending}`);
		const pending = {
			schemaVersion: 1,
			id: value.id,
			stagingProfile: value.stagingProfile,
			step: value.step
		};
		if (!existsSync(this.paths.profile) && existsSync(this.paths.rollback)) {
			mkdirSync(dirname(this.paths.profile), { recursive: true });
			renameSync(this.paths.rollback, this.paths.profile);
		}
		removeOwnedDirectory(pending.stagingProfile);
		unlinkSync(this.paths.pending);
	}
	/** Read the active desktop plugin inventory. */
	listPlugins() {
		if (!existsSync(this.paths.profile)) return [];
		return pluginRecords(this.paths.profile);
	}
	/** Read the exact dsh version installed in the active desktop project. */
	dshVersion() {
		if (!existsSync(this.paths.profile)) throw new Error("desktop project: active profile is not installed");
		return this.installedPackageVersion(DSH_PACKAGE);
	}
	installedPackageVersion(packageName) {
		const manifest = readJson(join(this.paths.profile, "node_modules", ...packageName.split("/"), "package.json"));
		if (!isRecord(manifest) || typeof manifest.version !== "string") throw new Error(`desktop project: installed ${packageName} package has no version`);
		assertVersion(manifest.version);
		return manifest.version;
	}
	/** Read the release version applied to the active desktop project. */
	releaseVersion() {
		if (!existsSync(this.paths.profile)) throw new Error("desktop project: active profile is not installed");
		return releaseFile(this.paths.profile).version;
	}
	/** Install or reconcile the active project to the Electron package's exact release. */
	async applyRelease(seedDir, electronVersion, hooks) {
		return this.withLock(async () => {
			this.recover();
			verifySeedIntegrity(seedDir);
			const target = releaseFile(seedDir);
			verifyDesktopCorePackageSet(seedDir, target.version);
			if (target.version !== electronVersion) throw new Error(`desktop project: seed ${target.version} does not match Electron ${electronVersion}`);
			if (existsSync(this.paths.profile) && this.releaseVersion() === target.version && this.dshVersion() === target.version && this.installedPackageVersion("@deepseek-ai/dsh-desktop-host") === target.version) {
				verifyDesktopCorePackageSet(this.paths.profile, target.version);
				return false;
			}
			this.mergeSeedPnpmState(seedDir);
			const stagingProfile = this.newStagingProfile();
			try {
				if (existsSync(this.paths.profile)) {
					const plugins = pluginRecords(this.paths.profile);
					copyMetadata(seedDir, stagingProfile);
					await this.runPnpm(stagingProfile, [
						"install",
						"--offline",
						"--frozen-lockfile",
						"--trust-lockfile"
					]);
					if (plugins.length > 0) {
						await this.runPnpm(stagingProfile, [
							"add",
							...plugins.map((plugin) => `${plugin.name}@${plugin.version}`),
							"--save-exact",
							"--offline"
						]);
						writeProfilePlugins(stagingProfile, plugins);
					}
				} else {
					copyMetadata(seedDir, stagingProfile);
					await this.runPnpm(stagingProfile, [
						"install",
						"--offline",
						"--frozen-lockfile",
						"--trust-lockfile"
					]);
				}
				await hooks.healthCheck(stagingProfile);
				await this.activate(stagingProfile, hooks);
				return true;
			} catch (error) {
				removeOwnedDirectory(stagingProfile);
				throw error;
			}
		});
	}
	/** Apply one exact dependency mutation through a staging project. */
	async mutate(mutation, hooks) {
		await this.withLock(async () => {
			this.recover();
			if (!existsSync(this.paths.profile)) throw new Error("desktop project: active profile is not installed");
			verifyDesktopCorePackageSet(this.paths.profile, this.releaseVersion());
			const stagingProfile = this.newStagingProfile();
			try {
				copyMetadata(this.paths.profile, stagingProfile);
				await this.applyMutation(stagingProfile, mutation);
				await hooks.healthCheck(stagingProfile);
				await this.activate(stagingProfile, hooks);
			} catch (error) {
				removeOwnedDirectory(stagingProfile);
				throw error;
			}
		});
	}
	newStagingProfile() {
		const path = join(this.paths.staging, randomUUID(), "profile");
		mkdirSync(path, {
			recursive: true,
			mode: 448
		});
		return path;
	}
	async applyMutation(projectDir, mutation) {
		switch (mutation.type) {
			case "plugin-add": {
				const requestedName = packageNameFromSpec(mutation.spec);
				if (requestedName === void 0) throw new Error("desktop project: plugin package name is required");
				await this.runPnpm(projectDir, [
					"add",
					mutation.spec,
					"--save-exact"
				]);
				const installed = inspectPlugin(projectDir, requestedName);
				writeProfilePlugins(projectDir, [...pluginRecords(projectDir).filter((plugin) => plugin.name !== installed.name), installed].sort((left, right) => left.name.localeCompare(right.name)));
				return;
			}
			case "plugin-remove": {
				assertPackageName(mutation.name);
				if (!profilePluginNames(projectDir).includes(mutation.name)) throw new Error(`desktop project: plugin ${JSON.stringify(mutation.name)} is not installed`);
				const remaining = pluginRecords(projectDir).filter((plugin) => plugin.name !== mutation.name);
				await this.runPnpm(projectDir, ["remove", mutation.name]);
				writeProfilePlugins(projectDir, remaining);
				return;
			}
			case "plugin-update":
				assertPackageName(mutation.name);
				assertVersion(mutation.version);
				if (!profilePluginNames(projectDir).includes(mutation.name)) throw new Error(`desktop project: plugin ${JSON.stringify(mutation.name)} is not installed`);
				await this.runPnpm(projectDir, [
					"add",
					`${mutation.name}@${mutation.version}`,
					"--save-exact"
				]);
				{
					const installed = inspectPlugin(projectDir, mutation.name);
					writeProfilePlugins(projectDir, pluginRecords(projectDir).map((plugin) => plugin.name === installed.name ? installed : plugin));
				}
				return;
			default:
		}
	}
	mergeSeedPnpmState(seedDir) {
		const transactionRoot = join(this.paths.staging, randomUUID());
		const extractedStore = join(transactionRoot, "store");
		try {
			extractPnpmStoreArchives(seedDir, extractedStore);
			mergePnpmStore(extractedStore, this.paths.pnpm.store);
		} finally {
			removeOwnedDirectory(transactionRoot);
		}
	}
	async activate(stagingProfile, hooks) {
		const pending = {
			schemaVersion: 1,
			id: basename(dirname(stagingProfile)),
			stagingProfile,
			step: "prepared"
		};
		writeJson(this.paths.pending, pending);
		await hooks.beforeActivate();
		let activeMoved = false;
		try {
			removeOwnedDirectory(this.paths.rollback);
			mkdirSync(dirname(this.paths.rollback), {
				recursive: true,
				mode: 448
			});
			writeJson(this.paths.pending, {
				...pending,
				step: "active-moved"
			});
			if (existsSync(this.paths.profile)) {
				renameSync(this.paths.profile, this.paths.rollback);
				activeMoved = true;
			}
			mkdirSync(dirname(this.paths.profile), {
				recursive: true,
				mode: 448
			});
			writeJson(this.paths.pending, {
				...pending,
				step: "staging-activated"
			});
			renameSync(stagingProfile, this.paths.profile);
			await hooks.afterActivate();
			unlinkSync(this.paths.pending);
		} catch (error) {
			if (existsSync(this.paths.profile)) removeOwnedDirectory(this.paths.profile);
			if (activeMoved && existsSync(this.paths.rollback)) renameSync(this.paths.rollback, this.paths.profile);
			if (existsSync(this.paths.pending)) unlinkSync(this.paths.pending);
			await hooks.afterActivate().catch(() => void 0);
			throw error;
		}
	}
	async runPnpm(projectDir, args) {
		const [command, ...commandArgs] = args;
		if (command === void 0) throw new Error("desktop project: pnpm command is required");
		for (const path of [
			this.paths.root,
			this.paths.pnpm.store,
			this.paths.pnpm.cache,
			this.paths.pnpm.state,
			this.paths.pnpm.config,
			this.paths.pnpm.home
		]) mkdirSync(path, {
			recursive: true,
			mode: 448
		});
		const npmrc = join(this.paths.pnpm.config, "npmrc");
		if (!existsSync(npmrc)) writeFileSync(npmrc, "", { mode: 384 });
		const inherited = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^DSH_DESKTOP_/u.test(name) && !/^(?:npm|pnpm|corepack)_/iu.test(name)));
		await new Promise((settle, reject) => {
			const child = spawn(this.runtime.node, [
				this.runtime.pnpm,
				`--config.registry=${DESKTOP_REGISTRY}`,
				`--config.store-dir=${this.paths.pnpm.store}`,
				"--config.enable-global-virtual-store=false",
				`--config.userconfig=${npmrc}`,
				command,
				...commandArgs
			], {
				cwd: projectDir,
				env: {
					...inherited,
					COREPACK_HOME: this.paths.pnpm.home,
					NPM_CONFIG_REGISTRY: DESKTOP_REGISTRY,
					NPM_CONFIG_STORE_DIR: this.paths.pnpm.store,
					NPM_CONFIG_USERCONFIG: npmrc,
					PATH: `${dirname(this.runtime.node)}${delimiter}${process.env.PATH ?? ""}`,
					PNPM_HOME: this.paths.pnpm.home,
					XDG_CACHE_HOME: this.paths.pnpm.cache,
					XDG_CONFIG_HOME: this.paths.pnpm.config,
					XDG_STATE_HOME: this.paths.pnpm.state
				},
				stdio: [
					"ignore",
					"pipe",
					"pipe"
				]
			});
			const childPid = child.pid;
			if (childPid === void 0) {
				child.kill("SIGKILL");
				reject(/* @__PURE__ */ new Error("desktop project: pnpm did not report a process id"));
				return;
			}
			try {
				this.writeLockOwner(childPid);
			} catch (error) {
				child.kill("SIGKILL");
				reject(errorOf$2(error, "desktop project: failed to assign the package transaction lock to pnpm"));
				return;
			}
			let diagnostics = "";
			let completed = false;
			const appendDiagnostics = (chunk) => {
				diagnostics = (diagnostics + chunk).slice(-65536);
			};
			child.stdout.setEncoding("utf8");
			child.stdout.on("data", appendDiagnostics);
			child.stderr.setEncoding("utf8");
			child.stderr.on("data", appendDiagnostics);
			const complete = (settleChild) => {
				if (completed) return;
				completed = true;
				try {
					this.writeLockOwner(process.pid);
				} catch (error) {
					reject(errorOf$2(error, "desktop project: failed to return the package transaction lock to Electron"));
					return;
				}
				settleChild();
			};
			child.once("error", (error) => {
				complete(() => {
					reject(error);
				});
			});
			child.once("close", (code, signal) => {
				complete(() => {
					if (code === 0) {
						settle();
						return;
					}
					reject(/* @__PURE__ */ new Error(`desktop project: pnpm exited with ${String(code ?? signal)}${diagnostics.trim() === "" ? "" : `: ${diagnostics.trim()}`}`));
				});
			});
		});
	}
	writeLockOwner(pid) {
		const descriptor = this.lockDescriptor;
		if (descriptor === void 0) throw new Error("desktop project: package transaction lost its lock");
		const content = Buffer.from(`${String(pid)}\n`);
		ftruncateSync(descriptor, 0);
		writeSync(descriptor, content, 0, content.byteLength, 0);
		fsyncSync(descriptor);
	}
	async withLock(operation) {
		mkdirSync(this.paths.root, {
			recursive: true,
			mode: 448
		});
		let descriptor;
		try {
			descriptor = openSync(this.paths.lock, "wx", 384);
		} catch (error) {
			if (error.code === "EEXIST") {
				const lock = lstatSync(this.paths.lock);
				if (lock.isSymbolicLink() || !lock.isFile()) throw new Error("desktop project: package transaction lock is not a regular file");
				const owner = Number.parseInt(readFileSync(this.paths.lock, "utf8").trim(), 10);
				let active = !Number.isSafeInteger(owner) || owner <= 0;
				if (!active) try {
					process.kill(owner, 0);
					active = true;
				} catch (signalError) {
					active = signalError.code !== "ESRCH";
				}
				if (active) throw new Error("desktop project: another package transaction is active");
				unlinkSync(this.paths.lock);
				descriptor = openSync(this.paths.lock, "wx", 384);
			} else throw error;
		}
		try {
			this.lockDescriptor = descriptor;
			this.writeLockOwner(process.pid);
			return await operation();
		} finally {
			this.lockDescriptor = void 0;
			closeSync(descriptor);
			unlinkSync(this.paths.lock);
		}
	}
};
//#endregion
//#region lib/types/host-process.js
/** Upstream-Node child lifecycle and streaming custom-protocol carrier. */
function isDesktopHostEvent(message) {
	if (typeof message !== "object" || message === null || !("type" in message)) return false;
	const candidate = message;
	switch (candidate.type) {
		case "ready": return candidate.protocolVersion === 3 && typeof candidate.dshVersion === "string";
		case "fatal": return typeof candidate.message === "string";
		default: return false;
	}
}
function errorOf$1(reason, fallback) {
	return reason instanceof Error ? reason : new Error(fallback);
}
async function exitsWithin(exit, milliseconds) {
	let timer;
	const timeout = new Promise((resolve) => {
		timer = setTimeout(() => {
			resolve(false);
		}, milliseconds);
		timer.unref();
	});
	try {
		return await Promise.race([exit.then(() => true), timeout]);
	} finally {
		if (timer !== void 0) clearTimeout(timer);
	}
}
/** One dsh backend running under the bundled upstream Node.js executable. */
var DesktopHostProcess = class {
	node;
	projectDir;
	inspectPort;
	child;
	requestPipe;
	responsePipe;
	responseDecoder = new DesktopHostResponseDecoder();
	requestWriteTail = Promise.resolve();
	nextStreamId = 1;
	pending = /* @__PURE__ */ new Map();
	blockedResponses = /* @__PURE__ */ new Set();
	readyResolve;
	readyReject;
	readyPromise = new Promise((resolve, reject) => {
		this.readyResolve = resolve;
		this.readyReject = reject;
	});
	exitPromise;
	stderr = "";
	/**
	* @param node - absolute bundled upstream Node.js executable.
	* @param projectDir - active or staged desktop npm project.
	* @param inspectPort - optional loopback inspector port for workspace development.
	*/
	constructor(node, projectDir, inspectPort) {
		this.node = node;
		this.projectDir = projectDir;
		this.inspectPort = inspectPort;
	}
	/** Start the child once and resolve only after its complete composition is active. */
	async start() {
		if (this.child !== void 0) return this.readyPromise;
		const entry = join(this.projectDir, "node_modules", "@deepseek-ai", "dsh-desktop-host", "lib", "index.js");
		const child = spawn(this.node, [
			...this.inspectPort === void 0 ? [] : [`--inspect=127.0.0.1:${String(this.inspectPort)}`],
			entry,
			this.projectDir,
			...this.inspectPort === void 0 ? [] : ["--allow-linked-profile"]
		], {
			cwd: this.projectDir,
			env: Object.fromEntries(Object.entries(process.env).filter(([name]) => name !== "NODE_OPTIONS" && !/^DSH_DESKTOP_/u.test(name) && !/^(?:npm|pnpm|corepack)_/iu.test(name))),
			stdio: [
				"ignore",
				"pipe",
				"pipe",
				"pipe",
				"pipe",
				"ipc"
			]
		});
		const requestPipe = child.stdio[3];
		const responsePipe = child.stdio[4];
		if (!(requestPipe instanceof Writable) || !(responsePipe instanceof Readable)) {
			child.kill("SIGTERM");
			throw new Error("dsh desktop host did not expose the required byte pipes and IPC channel");
		}
		this.child = child;
		this.requestPipe = requestPipe;
		this.responsePipe = responsePipe;
		child.stderr?.setEncoding("utf8");
		child.stderr?.on("data", (chunk) => {
			this.stderr += chunk;
		});
		child.stdout?.pipe(process.stdout);
		responsePipe.on("data", (chunk) => {
			this.acceptResponseBytes(chunk);
		});
		responsePipe.once("end", () => {
			try {
				this.responseDecoder.finish();
				this.fail(/* @__PURE__ */ new Error("dsh desktop host response pipe ended"));
			} catch (error) {
				this.fail(errorOf$1(error, "dsh desktop host response pipe failed"));
			}
		});
		requestPipe.once("error", (error) => {
			this.fail(error);
		});
		responsePipe.once("error", (error) => {
			this.fail(error);
		});
		child.on("message", (message) => {
			if (!isDesktopHostEvent(message)) {
				this.fail(/* @__PURE__ */ new Error("dsh desktop host sent an invalid IPC event"));
				child.kill("SIGTERM");
				return;
			}
			this.handleMessage(message);
		});
		child.once("error", (error) => {
			this.fail(error);
		});
		this.exitPromise = new Promise((resolve) => {
			child.once("exit", (code) => {
				const suffix = this.stderr.trim() === "" ? "" : `: ${this.stderr.trim()}`;
				if (code !== 0 && code !== null) this.fail(/* @__PURE__ */ new Error(`dsh desktop host exited with ${String(code)}${suffix}`));
				else this.fail(/* @__PURE__ */ new Error(`dsh desktop host stopped${suffix}`));
				resolve();
			});
		});
		return this.readyPromise;
	}
	/** Forward one `dsh-app://app` request to the child without buffering its body. */
	async fetch(request) {
		await this.start();
		const child = this.child;
		if (child === void 0 || !child.connected || this.requestPipe === void 0) throw new Error("dsh desktop host is unavailable");
		if (this.nextStreamId > 4294967295) throw new Error("dsh desktop host exhausted its request stream ids");
		const streamId = this.nextStreamId++;
		const method = request.method.toUpperCase();
		const hasBody = method !== "GET" && method !== "HEAD" && request.body !== null;
		return new Promise((resolve, reject) => {
			const pending = {
				resolve,
				reject,
				responseStarted: false,
				uploadOpen: hasBody
			};
			const abort = () => {
				if (!this.pending.has(streamId)) return;
				const error = errorOf$1(request.signal.reason, "request aborted");
				pending.uploadOpen = false;
				pending.requestReader?.cancel(error).catch(() => void 0);
				this.enqueueRequestFrame(encodeDesktopRequestCancel(streamId)).catch((pipeError) => {
					this.fail(errorOf$1(pipeError, "dsh desktop request pipe failed"));
				});
				if (pending.controller === void 0) pending.reject(error);
				else pending.controller.error(error);
				this.finishPending(streamId, false);
			};
			if (request.signal.aborted) {
				reject(errorOf$1(request.signal.reason, "request aborted"));
				return;
			}
			request.signal.addEventListener("abort", abort, { once: true });
			pending.removeAbort = () => {
				request.signal.removeEventListener("abort", abort);
			};
			this.pending.set(streamId, pending);
			this.pumpRequest(streamId, request, hasBody).catch((error) => {
				this.failPending(streamId, errorOf$1(error, "dsh desktop request upload failed"));
			});
		});
	}
	/** Request graceful teardown, then wait for child exit. */
	async stop() {
		const child = this.child;
		if (child === void 0) return;
		this.blockedResponses.clear();
		this.responsePipe?.resume();
		if (child.connected) this.send({ type: "shutdown" });
		this.requestPipe?.destroy();
		const exited = this.exitPromise ?? Promise.resolve();
		if (!await exitsWithin(exited, 1e4)) child.kill("SIGTERM");
		if (!await exitsWithin(exited, 5e3)) {
			child.kill("SIGKILL");
			if (!await exitsWithin(exited, 5e3)) throw new Error("dsh desktop host did not exit after SIGKILL");
		}
		this.child = void 0;
		this.requestPipe = void 0;
		this.responsePipe = void 0;
	}
	async pumpRequest(streamId, request, hasBody) {
		await this.enqueueRequestFrame(encodeDesktopRequestStart(streamId, {
			url: request.url,
			method: request.method.toUpperCase(),
			headers: [...request.headers.entries()],
			hasBody
		}));
		if (!hasBody) return;
		const body = request.body;
		if (body === null) throw new Error("dsh desktop request body disappeared before upload");
		const reader = body.getReader();
		const pending = this.pending.get(streamId);
		if (pending === void 0) {
			await reader.cancel();
			return;
		}
		pending.requestReader = reader;
		try {
			for (;;) {
				const next = await reader.read();
				if (next.done) break;
				for (let offset = 0; offset < next.value.byteLength; offset += DESKTOP_PIPE_CHUNK_BYTES) {
					if (!this.pending.has(streamId)) return;
					await this.enqueueRequestFrame(encodeDesktopRequestData(streamId, next.value.subarray(offset, offset + DESKTOP_PIPE_CHUNK_BYTES)));
				}
			}
			const live = this.pending.get(streamId);
			if (live !== void 0) {
				await this.enqueueRequestFrame(encodeDesktopRequestEnd(streamId));
				live.uploadOpen = false;
			}
		} finally {
			reader.releaseLock();
			const live = this.pending.get(streamId);
			if (live?.requestReader === reader) delete live.requestReader;
		}
	}
	enqueueRequestFrame(frame) {
		const write = this.requestWriteTail.then(async () => {
			const pipe = this.requestPipe;
			if (pipe === void 0 || pipe.destroyed) throw new Error("dsh desktop host request pipe is unavailable");
			if (!pipe.write(frame)) await once(pipe, "drain");
		});
		this.requestWriteTail = write.catch(() => void 0);
		return write;
	}
	send(message) {
		const child = this.child;
		if (child === void 0 || !child.connected) throw new Error("dsh desktop host IPC is unavailable");
		child.send(message);
	}
	acceptResponseBytes(chunk) {
		try {
			for (const frame of this.responseDecoder.push(chunk)) this.handleResponseFrame(frame);
		} catch (error) {
			this.fail(errorOf$1(error, "dsh desktop host response pipe failed"));
			this.child?.kill("SIGTERM");
		}
	}
	handleResponseFrame(frame) {
		const pending = this.pending.get(frame.streamId);
		if (pending === void 0) {
			if (frame.streamId >= this.nextStreamId) throw new Error(`dsh desktop host responded for unknown stream ${String(frame.streamId)}`);
			return;
		}
		switch (frame.type) {
			case "start": {
				if (pending.responseStarted) throw new Error(`dsh desktop host started stream ${String(frame.streamId)} twice`);
				pending.responseStarted = true;
				let body = null;
				if (frame.hasBody) body = new ReadableStream({
					start: (controller) => {
						pending.controller = controller;
					},
					pull: () => {
						this.blockedResponses.delete(frame.streamId);
						this.resumeResponsePipe();
					},
					cancel: (reason) => {
						this.cancelResponse(frame.streamId, reason);
					}
				});
				pending.resolve(new Response(body, {
					status: frame.status,
					headers: new Headers(frame.headers.map(([name, value]) => [name, value]))
				}));
				return;
			}
			case "data": {
				const controller = pending.controller;
				if (!pending.responseStarted || controller === void 0) throw new Error(`dsh desktop host sent body data before a body start for stream ${String(frame.streamId)}`);
				controller.enqueue(frame.data);
				if ((controller.desiredSize ?? 0) <= 0) {
					this.blockedResponses.add(frame.streamId);
					this.responsePipe?.pause();
				}
				return;
			}
			case "end":
				if (!pending.responseStarted) throw new Error(`dsh desktop host ended stream ${String(frame.streamId)} before its response start`);
				pending.controller?.close();
				this.finishPending(frame.streamId, true);
				return;
			case "error":
				this.failPending(frame.streamId, new Error(frame.message));
				return;
			default:
		}
	}
	cancelResponse(streamId, reason) {
		const pending = this.pending.get(streamId);
		if (pending === void 0) return;
		pending.uploadOpen = false;
		pending.requestReader?.cancel(reason).catch(() => void 0);
		this.enqueueRequestFrame(encodeDesktopRequestCancel(streamId)).catch((error) => {
			this.fail(errorOf$1(error, "dsh desktop request pipe failed"));
		});
		this.finishPending(streamId, false);
	}
	failPending(streamId, error) {
		const pending = this.pending.get(streamId);
		if (pending === void 0) return;
		pending.uploadOpen = false;
		pending.requestReader?.cancel(error).catch(() => void 0);
		if (pending.controller === void 0) pending.reject(error);
		else pending.controller.error(error);
		this.enqueueRequestFrame(encodeDesktopRequestCancel(streamId)).catch((pipeError) => {
			this.fail(errorOf$1(pipeError, "dsh desktop request pipe failed"));
		});
		this.finishPending(streamId, false);
	}
	finishPending(streamId, cancelOpenUpload) {
		const pending = this.pending.get(streamId);
		if (pending === void 0) return;
		if (cancelOpenUpload && pending.uploadOpen) {
			pending.uploadOpen = false;
			pending.requestReader?.cancel().catch(() => void 0);
			this.enqueueRequestFrame(encodeDesktopRequestCancel(streamId)).catch((error) => {
				this.fail(errorOf$1(error, "dsh desktop request pipe failed"));
			});
		}
		pending.removeAbort?.();
		this.pending.delete(streamId);
		this.blockedResponses.delete(streamId);
		this.resumeResponsePipe();
	}
	resumeResponsePipe() {
		if (this.blockedResponses.size === 0) this.responsePipe?.resume();
	}
	handleMessage(message) {
		switch (message.type) {
			case "ready":
				this.readyResolve(message);
				return;
			case "fatal":
				this.fail(new Error(message.message));
				return;
			default:
		}
	}
	fail(error) {
		this.readyReject(error);
		for (const pending of this.pending.values()) {
			pending.requestReader?.cancel(error).catch(() => void 0);
			if (pending.controller === void 0) pending.reject(error);
			else pending.controller.error(error);
			pending.removeAbort?.();
		}
		this.pending.clear();
		this.blockedResponses.clear();
		this.responsePipe?.resume();
	}
};
//#endregion
//#region lib/types/ipc.js
/** Typed preload operations exposed only by the Electron shell. */
/** IPC channel names kept private to the desktop application bundle. */
const DESKTOP_IPC = {
	localeGet: "dsh-desktop:locale-get",
	pluginsList: "dsh-desktop:plugins-list",
	pluginsAdd: "dsh-desktop:plugins-add",
	pluginsRemove: "dsh-desktop:plugins-remove",
	pluginsUpdate: "dsh-desktop:plugins-update",
	updatesCheck: "dsh-desktop:updates-check",
	updatesInstall: "dsh-desktop:updates-install",
	updatesState: "dsh-desktop:updates-state"
};
//#endregion
//#region lib/types/locale.js
/** Typed English and Chinese copy owned by the Electron shell. */
const en$1 = {
	application: "Application",
	startupFailed: "DeepSeek Harness could not start",
	pluginsMenu: "Desktop Plugins…",
	pluginsMenuPackagedOnly: "Desktop Plugins… (available in packaged applications)",
	checkUpdatesMenu: "Check for Updates…",
	updateCheckFailedTitle: "Update Check Failed",
	unknownError: "Unknown error",
	updateCheckTitle: "Check for Updates",
	updateCurrent: "You already have the latest version.",
	updateTitle: "DeepSeek Harness Update",
	updateAvailable: "An update is available",
	updateDetail: "DeepSeek Harness {version}\n\nThis release includes its matching dsh version. The application will restart after installation.",
	installAndRestart: "Install and Restart",
	later: "Later",
	updateFailedTitle: "Update Failed",
	pluginManagerTitle: "Desktop Plugins",
	pluginWindowTitle: "DeepSeek Harness — Desktop Plugins",
	pluginManagerDescription: "Plugins are installed only in the Desktop node_modules and are managed by the bundled pnpm.",
	refresh: "Refresh",
	npmPackage: "npm package",
	install: "Install",
	installed: "Installed",
	noPlugins: "No Desktop plugins are installed.",
	remove: "Remove",
	update: "Update",
	targetVersion: "Enter the target version for {name}",
	removing: "Removing {name}…",
	updating: "Updating {name}…",
	installing: "Installing {spec}…",
	operationComplete: "Done. The Desktop backend has restarted.",
	refreshing: "Refreshing…",
	refreshed: "Plugin list refreshed.",
	loadingPlugins: "Reading Desktop plugins…"
};
const zh = {
	application: "应用",
	startupFailed: "DeepSeek Harness 无法启动",
	pluginsMenu: "桌面插件…",
	pluginsMenuPackagedOnly: "桌面插件…（打包应用中可用）",
	checkUpdatesMenu: "检查更新…",
	updateCheckFailedTitle: "更新检查失败",
	unknownError: "未知错误",
	updateCheckTitle: "检查更新",
	updateCurrent: "当前已是最新版本。",
	updateTitle: "DeepSeek Harness 更新",
	updateAvailable: "发现可用更新",
	updateDetail: "DeepSeek Harness {version}\n\n新版本绑定匹配的 dsh，安装后将重新启动。",
	installAndRestart: "安装并重启",
	later: "稍后",
	updateFailedTitle: "更新失败",
	pluginManagerTitle: "桌面插件",
	pluginWindowTitle: "DeepSeek Harness — 桌面插件",
	pluginManagerDescription: "插件只安装到桌面端自己的 node_modules，并由内置 pnpm 管理。",
	refresh: "刷新",
	npmPackage: "npm 包",
	install: "安装",
	installed: "已安装",
	noPlugins: "还没有安装桌面插件。",
	remove: "移除",
	update: "更新",
	targetVersion: "输入 {name} 的目标版本",
	removing: "正在移除 {name}…",
	updating: "正在更新 {name}…",
	installing: "正在安装 {spec}…",
	operationComplete: "操作完成，桌面后端已重新启动。",
	refreshing: "正在刷新…",
	refreshed: "插件列表已刷新。",
	loadingPlugins: "正在读取桌面插件…"
};
/** Resolve Electron's locale to one shipped Desktop dictionary. */
function resolveDesktopLocale(locale) {
	return locale.toLowerCase().startsWith("zh") ? {
		id: "zh-CN",
		messages: zh
	} : {
		id: "en",
		messages: en$1
	};
}
/** Replace named placeholders in one locale-owned message. */
function formatDesktopMessage(message, values) {
	return message.replaceAll(/\{([^{}]+)\}/gu, (placeholder, key) => values[key] ?? placeholder);
}
//#endregion
//#region lib/types/single-instance.js
/** Electron single-instance ownership before any Desktop profile lifecycle begins. */
/**
* Claim the process-lifetime Desktop lock and route later launches to the owner.
* @param application - Electron application singleton.
* @param focusOwner - focus or recreate the primary window after a later launch.
* @returns true only in the process that may access the Desktop profile.
*/
function claimDesktopSingleInstance(application, focusOwner) {
	if (!application.requestSingleInstanceLock()) {
		application.quit();
		return false;
	}
	application.on("second-instance", focusOwner);
	return true;
}
//#endregion
//#region lib/types/update-coordinator.js
/** One Electron release stream for the version-bound shell and dsh seed. */
const { autoUpdater } = electronUpdater;
/** Checks, downloads, and installs one complete Desktop release. */
var DesktopUpdateCoordinator = class {
	publish;
	beforeRestart;
	updater;
	enabled;
	availableVersion;
	checkOperation;
	installOperation;
	/**
	* @param publish - state sink for every desktop window.
	* @param beforeRestart - stop application-owned processes before replacement.
	* @param updater - Electron artifact updater; replaceable for tests.
	* @param enabled - whether this packaged process carries updater configuration.
	*/
	constructor(publish, beforeRestart = async () => {}, updater = autoUpdater, enabled = () => app.isPackaged && existsSync(join(process.resourcesPath, "app-update.yml"))) {
		this.publish = publish;
		this.beforeRestart = beforeRestart;
		this.updater = updater;
		this.enabled = enabled;
		this.updater.autoDownload = false;
		this.updater.autoInstallOnAppQuit = false;
	}
	/** Check the configured Desktop release stream and retain an available version. */
	async check() {
		if (this.installOperation !== void 0) return this.installOperation;
		if (this.checkOperation !== void 0) return this.checkOperation;
		this.checkOperation = this.doCheck().finally(() => {
			this.checkOperation = void 0;
		});
		return this.checkOperation;
	}
	/** Wait for an in-flight check, then download and install its retained release. */
	async install() {
		if (this.installOperation !== void 0) return this.installOperation;
		this.installOperation = (async () => {
			await this.checkOperation;
			return this.doInstall();
		})().finally(() => {
			this.installOperation = void 0;
		});
		return this.installOperation;
	}
	async doCheck() {
		this.publish({ phase: "checking" });
		try {
			if (!this.enabled()) {
				this.availableVersion = void 0;
				return this.publish({ phase: "idle" });
			}
			const result = await this.updater.checkForUpdates();
			const version = result?.isUpdateAvailable === true ? result.updateInfo.version : void 0;
			this.availableVersion = version;
			return version === void 0 ? this.publish({ phase: "idle" }) : this.publish({
				phase: "available",
				version
			});
		} catch (error) {
			this.availableVersion = void 0;
			return this.publish({
				phase: "error",
				message: error instanceof Error ? error.message : String(error)
			});
		}
	}
	async doInstall() {
		const version = this.availableVersion;
		if (version === void 0) throw new Error("desktop update: no verified update is available");
		this.publish({
			phase: "installing",
			version
		});
		try {
			await this.updater.downloadUpdate();
			this.availableVersion = void 0;
			const ready = this.publish({
				phase: "ready",
				version
			});
			await this.beforeRestart();
			this.updater.quitAndInstall(false, true);
			return ready;
		} catch (error) {
			return this.publish({
				phase: "error",
				version,
				message: error instanceof Error ? error.message : String(error)
			});
		}
	}
};
//#endregion
//#region lib/types/main.js
/** Electron shell: desktop project ownership, custom protocol, windows, and lifecycle. */
const SCHEME = "dsh-app";
let focusPrimaryWindow = () => {};
function errorOf(reason, fallback) {
	return reason instanceof Error ? reason : new Error(fallback);
}
protocol.registerSchemesAsPrivileged([{
	scheme: SCHEME,
	privileges: {
		standard: true,
		secure: true,
		supportFetchAPI: true,
		corsEnabled: false,
		stream: true,
		codeCache: true
	}
}]);
const MIME = {
	".css": "text/css; charset=utf-8",
	".html": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".svg": "image/svg+xml"
};
function runtimeResources() {
	const development = !app.isPackaged;
	return {
		node: (development ? process.env.DSH_DESKTOP_NODE_BINARY : void 0) ?? join(process.resourcesPath, "runtime", "node", process.platform === "win32" ? "node.exe" : "node"),
		pnpm: (development ? process.env.DSH_DESKTOP_PNPM_ENTRY : void 0) ?? join(process.resourcesPath, "runtime", "pnpm", "bin", "pnpm.mjs"),
		seed: (development ? process.env.DSH_DESKTOP_SEED_DIR : void 0) ?? join(process.resourcesPath, "seed")
	};
}
function developmentProject() {
	const configured = process.env.DSH_DESKTOP_DEV_PROJECT_DIR;
	if (configured === void 0 || configured === "") return void 0;
	if (app.isPackaged) throw new Error("dsh desktop: development project override is unavailable in packaged applications");
	return resolve(configured);
}
function developmentHostInspectPort(enabled) {
	const configured = process.env.DSH_DESKTOP_HOST_INSPECT_PORT;
	if (!enabled || configured === void 0 || configured === "") return void 0;
	const port = Number(configured);
	if (!Number.isSafeInteger(port) || port < 1 || port > 65535) throw new Error("dsh desktop: DSH_DESKTOP_HOST_INSPECT_PORT must be an integer from 1 through 65535");
	return port;
}
function createWindow(preload) {
	const window = new BrowserWindow({
		width: 1280,
		height: 840,
		minWidth: 880,
		minHeight: 600,
		show: false,
		webPreferences: {
			preload,
			nodeIntegration: false,
			contextIsolation: true,
			sandbox: true,
			webSecurity: true
		}
	});
	window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
	window.webContents.on("will-navigate", (event, url) => {
		if (new URL(url).protocol !== `${SCHEME}:`) event.preventDefault();
	});
	return window;
}
function assertDesktopSender(event, hostnames) {
	const senderFrame = event.senderFrame;
	if (senderFrame === null) throw new Error("dsh desktop: rejected IPC without a sender frame");
	const url = new URL(senderFrame.url);
	if (url.protocol !== `${SCHEME}:` || !hostnames.includes(url.hostname)) throw new Error("dsh desktop: rejected IPC from an unowned renderer");
}
async function serveShellAsset(request) {
	if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405 });
	const root = resolve(app.getAppPath(), "renderer");
	const url = new URL(request.url);
	let pathname;
	try {
		pathname = decodeURIComponent(url.pathname);
	} catch {
		return new Response(null, { status: 400 });
	}
	const target = resolve(normalize(join(root, pathname)));
	if (target !== root && !target.startsWith(root + sep)) return new Response(null, { status: 403 });
	try {
		const body = request.method === "HEAD" ? null : await readFile(target);
		return new Response(body, { headers: { "content-type": MIME[extname(target)] ?? "application/octet-stream" } });
	} catch {
		return new Response(null, { status: 404 });
	}
}
async function main() {
	const resources = runtimeResources();
	const paths = resolveDesktopPaths();
	const development = developmentProject();
	const activeProject = development ?? paths.profile;
	const hostInspectPort = developmentHostInspectPort(development !== void 0);
	const manager = new DesktopProjectManager(paths, resources);
	if (development === void 0) manager.recover();
	let host;
	let mainWindow;
	let pluginWindow;
	let shellInstallerOwnsQuit = false;
	let updateState = { phase: "idle" };
	const locale = resolveDesktopLocale(app.getLocale());
	const messages = locale.messages;
	const appPreload = fileURLToPath(new URL("./preload-app.cjs", import.meta.url));
	const managementPreload = fileURLToPath(new URL("./preload.cjs", import.meta.url));
	const publishUpdate = (state) => {
		updateState = state;
		for (const window of BrowserWindow.getAllWindows()) window.webContents.send(DESKTOP_IPC.updatesState, state);
		return state;
	};
	const startHost = async (projectDir = activeProject) => {
		const next = new DesktopHostProcess(resources.node, projectDir, hostInspectPort);
		await next.start();
		return next;
	};
	const hooks = {
		healthCheck: async (projectDir) => {
			const active = host;
			host = void 0;
			await active?.stop();
			let healthFailure;
			let probe;
			try {
				probe = await startHost(projectDir);
				await probe.stop();
			} catch (error) {
				healthFailure = error;
				await probe?.stop().catch(() => void 0);
			}
			let restartFailure;
			if (active !== void 0) try {
				host = await startHost();
			} catch (error) {
				restartFailure = error;
			}
			if (healthFailure !== void 0 && restartFailure !== void 0) throw new AggregateError([errorOf(healthFailure, "desktop project: staged health check failed"), errorOf(restartFailure, "desktop project: active backend restart failed")], "desktop project: staged health check and active backend restart failed");
			if (healthFailure !== void 0) throw errorOf(healthFailure, "desktop project: staged health check failed");
			if (restartFailure !== void 0) throw errorOf(restartFailure, "desktop project: active backend restart failed");
		},
		beforeActivate: async () => {
			const active = host;
			host = void 0;
			await active?.stop();
		},
		afterActivate: async () => {
			host = await startHost();
		}
	};
	if (development === void 0) await manager.applyRelease(resources.seed, app.getVersion(), {
		...hooks,
		beforeActivate: async () => {},
		afterActivate: async () => {}
	});
	host = await startHost();
	const updates = new DesktopUpdateCoordinator(publishUpdate, async () => {
		shellInstallerOwnsQuit = true;
		const active = host;
		host = void 0;
		await active?.stop();
	});
	protocol.handle(SCHEME, (request) => {
		const url = new URL(request.url);
		if (url.hostname === "shell") return serveShellAsset(request);
		if (url.hostname !== "app") return Promise.resolve(new Response(null, { status: 404 }));
		const active = host;
		if (active === void 0) return Promise.resolve(new Response("backend unavailable", { status: 503 }));
		return active.fetch(request);
	});
	const mutate = async (event, mutation) => {
		assertDesktopSender(event, ["shell"]);
		if (development !== void 0) throw new Error("dsh desktop: plugin package changes require a packaged application");
		await manager.mutate(mutation, hooks);
		if (mainWindow !== void 0 && !mainWindow.isDestroyed()) mainWindow.webContents.reload();
	};
	ipcMain.handle(DESKTOP_IPC.localeGet, (event) => {
		assertDesktopSender(event, ["shell"]);
		return locale;
	});
	ipcMain.handle(DESKTOP_IPC.pluginsList, (event) => {
		assertDesktopSender(event, ["shell"]);
		if (development !== void 0) return [];
		return manager.listPlugins();
	});
	ipcMain.handle(DESKTOP_IPC.pluginsAdd, (event, spec) => {
		if (typeof spec !== "string") throw new Error("dsh desktop: plugin spec must be a string");
		return mutate(event, {
			type: "plugin-add",
			spec
		});
	});
	ipcMain.handle(DESKTOP_IPC.pluginsRemove, (event, name) => {
		if (typeof name !== "string") throw new Error("dsh desktop: plugin name must be a string");
		return mutate(event, {
			type: "plugin-remove",
			name
		});
	});
	ipcMain.handle(DESKTOP_IPC.pluginsUpdate, (event, name, version) => {
		if (typeof name !== "string" || typeof version !== "string") throw new Error("dsh desktop: plugin name and version must be strings");
		return mutate(event, {
			type: "plugin-update",
			name,
			version
		});
	});
	ipcMain.handle(DESKTOP_IPC.updatesCheck, async (event) => {
		assertDesktopSender(event, ["shell"]);
		return updates.check();
	});
	ipcMain.handle(DESKTOP_IPC.updatesInstall, async (event) => {
		assertDesktopSender(event, ["shell"]);
		await updates.install();
	});
	const checkAndPrompt = async (manual) => {
		const state = await updates.check();
		if (state.phase === "error") {
			if (manual) await dialog.showMessageBox({
				type: "error",
				title: messages.updateCheckFailedTitle,
				message: state.message ?? messages.unknownError
			});
			return;
		}
		if (state.phase !== "available") {
			if (manual) await dialog.showMessageBox({
				type: "info",
				title: messages.updateCheckTitle,
				message: state.message ?? messages.updateCurrent
			});
			return;
		}
		if ((await dialog.showMessageBox({
			type: "info",
			title: messages.updateTitle,
			message: messages.updateAvailable,
			detail: formatDesktopMessage(messages.updateDetail, { version: state.version ?? "" }),
			buttons: [messages.installAndRestart, messages.later],
			defaultId: 0,
			cancelId: 1
		})).response !== 0) return;
		const installed = await updates.install();
		if (installed.phase === "error") await dialog.showMessageBox({
			type: "error",
			title: messages.updateFailedTitle,
			message: installed.message ?? messages.unknownError
		});
	};
	const openPluginWindow = () => {
		if (pluginWindow !== void 0 && !pluginWindow.isDestroyed()) {
			pluginWindow.focus();
			return;
		}
		pluginWindow = createWindow(managementPreload);
		pluginWindow.setSize(900, 620);
		pluginWindow.setTitle(messages.pluginWindowTitle);
		pluginWindow.once("ready-to-show", () => {
			pluginWindow?.show();
		});
		pluginWindow.once("closed", () => {
			pluginWindow = void 0;
		});
		pluginWindow.loadURL(`${SCHEME}://shell/plugin-manager.html`);
	};
	Menu.setApplicationMenu(Menu.buildFromTemplate([{
		label: process.platform === "darwin" ? app.name : messages.application,
		submenu: [
			{
				label: development === void 0 ? messages.pluginsMenu : messages.pluginsMenuPackagedOnly,
				accelerator: "CmdOrCtrl+,",
				enabled: development === void 0,
				click: openPluginWindow
			},
			{
				label: messages.checkUpdatesMenu,
				click: () => {
					checkAndPrompt(true);
				}
			},
			{ type: "separator" },
			{ role: "quit" }
		]
	}]));
	const createMainWindow = () => {
		const window = createWindow(appPreload);
		mainWindow = window;
		window.once("ready-to-show", () => {
			if (!window.isDestroyed()) window.show();
		});
		window.on("closed", () => {
			if (mainWindow === window) mainWindow = void 0;
		});
		return window;
	};
	focusPrimaryWindow = () => {
		const window = mainWindow;
		if (window === void 0 || window.isDestroyed()) {
			createMainWindow().loadURL(`${SCHEME}://app/index.html`);
			return;
		}
		if (window.isMinimized()) window.restore();
		window.show();
		window.focus();
	};
	mainWindow = createMainWindow();
	await mainWindow.loadURL(`${SCHEME}://app/index.html`);
	if (development !== void 0 && process.env.DSH_DESKTOP_OPEN_DEVTOOLS !== "0") mainWindow.webContents.openDevTools({ mode: "detach" });
	publishUpdate(updateState);
	setTimeout(() => {
		checkAndPrompt(false);
	}, 1e4);
	app.on("activate", () => {
		if (BrowserWindow.getAllWindows().length === 0) focusPrimaryWindow();
	});
	app.on("window-all-closed", () => {
		if (process.platform !== "darwin") app.quit();
	});
	app.on("before-quit", (event) => {
		if (shellInstallerOwnsQuit) return;
		if (host === void 0) return;
		event.preventDefault();
		const active = host;
		host = void 0;
		active.stop().finally(() => {
			app.quit();
		});
	});
}
if (claimDesktopSingleInstance(app, () => {
	focusPrimaryWindow();
})) app.whenReady().then(main).catch(async (error) => {
	const message = error instanceof Error ? error.message : String(error);
	console.error(error);
	const diagnosticFile = process.env.DSH_DESKTOP_DIAGNOSTIC_FILE;
	if (diagnosticFile !== void 0) await writeFile(diagnosticFile, `${error instanceof Error ? error.stack ?? message : message}\n`).catch(() => void 0);
	dialog.showErrorBox(resolveDesktopLocale(app.getLocale()).messages.startupFailed, message);
	app.exit(1);
});
//#endregion
export {};
