/**
 * Browse backend of the directory-picker seam: registers `ctx.directoryPicker`
 * with the `browse` capability — one-level directory listing and child-directory
 * creation over the host filesystem via Node's stdlib (which already carries
 * the per-OS adaptation). Nothing renders on the host display, so this backend
 * serves remote clients the dialog backend cannot. Policy decisions (hidden
 * entries flagged but returned, symlinks followed, whole-filesystem scope) are
 * recorded in the directory-picker seam Agent Note.
 * @module @deepseek-ai/dsh-host-directory-picker-browse
 */

import { mkdir, opendir, open, stat } from 'node:fs/promises'
import type { FileHandle } from 'node:fs/promises'
import { homedir } from 'node:os'
import { basename, dirname, join, posix, resolve, win32 } from 'node:path'
import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import {
  DirectoryPicker, DirectoryPickerError,
} from '@deepseek-ai/dsh-host-directory-picker'
import type {
  DirectoryEntry, DirectoryFilePage, DirectoryListing, DirectoryListOptions, DirectoryPickerCapability, DirectoryReadOptions,
} from '@deepseek-ai/dsh-host-directory-picker'

/**
 * Ancestor chain from the filesystem root to `target` inclusive — the
 * breadcrumb rows of a listing, every one a jump target.
 */
function ancestryCrumbs(target: string): DirectoryEntry[] {
  const crumbs: DirectoryEntry[] = []
  let current = target
  for (;;) {
    const parent = dirname(current)
    // basename of a root is '' — label the root crumb by its full path ('/', 'C:\').
    crumbs.unshift({ name: parent === current ? current : basename(current), path: current, hidden: false, kind: 'directory' })
    if (parent === current) return crumbs
    current = parent
  }
}

/**
 * True when the path names one fixed filesystem location regardless of
 * process state: POSIX-absolute on POSIX; on Windows only drive-qualified
 * (`C:\…`) or complete UNC (`\\server\share…`) forms. Rooted drive-less
 * forms (`\foo`, `/foo`) and incomplete UNC prefixes (`\\`, `\\server`)
 * pass `isAbsolute` yet still resolve against the process's current drive.
 * @param path - candidate path.
 * @param platform - replaces `process.platform` for deterministic tests.
 * @returns whether the path is fully qualified on the platform.
 */
export function fullyQualified(path: string, platform: NodeJS.Platform = process.platform): boolean {
  return platform === 'win32'
    ? win32.isAbsolute(path) && /^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/]+[^\\/]+)/.test(path)
    : posix.isAbsolute(path)
}

/** One streamed listing candidate: the dirent facts a row needs, nothing else retained. */
export interface ListingCandidate {
  /** Base name within the streamed level. */
  name: string
  /** Dirent says directory (no probe needed). */
  isDirectory: boolean
  /** Dirent says regular file (no probe needed). */
  isFile: boolean
  /** Dirent says symlink (enterability needs a stat probe). */
  isSymbolicLink: boolean
}

/**
 * Insert a streamed candidate into the name-sorted bounded window, evicting
 * the name-largest candidate when the window exceeds `keep`. Memory over an
 * arbitrarily large level therefore stays O(keep) regardless of how many
 * children the directory holds.
 * @param window - the name-ascending window, mutated in place.
 * @param candidate - the streamed candidate to place.
 * @param keep - the window bound.
 * @returns true when an eviction happened (the level has candidates beyond the window).
 */
export function boundedInsert(window: ListingCandidate[], candidate: ListingCandidate, keep: number): boolean {
  // Full window, name at or beyond the tail: one comparison rejects, so an
  // oversized level costs O(1) per candidate past the head instead of a
  // window scan (100k children against a 1,001 window must not approach
  // 10^8 comparisons).
  // oxlint-disable-next-line typescript/no-non-null-assertion -- a full window (length === keep >= 1) has a tail
  if (window.length === keep && candidate.name.localeCompare(window[window.length - 1]!.name) >= 0) return true
  // Binary insertion keeps a retained candidate at O(log keep) comparisons.
  let lo = 0
  let hi = window.length
  while (lo < hi) {
    const mid = (lo + hi) >>> 1
    // oxlint-disable-next-line typescript/no-non-null-assertion -- bounded by the loop condition
    if (candidate.name.localeCompare(window[mid]!.name) < 0) hi = mid
    else lo = mid + 1
  }
  window.splice(lo, 0, candidate)
  if (window.length <= keep) return false
  window.pop()
  return true
}

/**
 * Await `operation`, but reject with the signal's reason the moment it
 * aborts. Node's filesystem reads are not retractable, so the operation
 * itself keeps running against a handle the caller then closes — its late
 * settlement is swallowed here so an abandoned read cannot surface as an
 * unhandled rejection.
 * @param operation - the in-flight filesystem step.
 * @param signal - caller lifetime; absent means plain awaiting.
 * @returns the operation's value.
 */
export function raceAbort<T>(operation: Promise<T>, signal: AbortSignal | undefined): Promise<T> {
  if (signal === undefined) return operation
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => {
      operation.catch(() => {
        // Abandoned read: its handle is being closed by the aborting caller,
        // and the abort reason already carried the outcome.
      })
      reject(asError(signal.reason))
    }
    if (signal.aborted) {
      onAbort()
      return
    }
    signal.addEventListener('abort', onAbort, { once: true })
    operation.then(
      (value) => {
        signal.removeEventListener('abort', onAbort)
        resolve(value)
      },
      (reason: unknown) => {
        signal.removeEventListener('abort', onAbort)
        reject(asError(reason))
      },
    )
  })
}

/** The thrown value as an Error (wire/abort reasons may be anything). */
function asError(reason: unknown): Error {
  return reason instanceof Error ? reason : new Error(String(reason))
}

/* v8 ignore start -- a close failure of an abandoned handle has no consumer, and forcing one needs a filesystem torn down mid-request. */
/** Swallow the close failure of a handle its caller already departed. */
function swallowCloseFailure(): void {}
/* v8 ignore stop */

/** Message text of an unknown thrown value. */
function messageOf(error: unknown): string {
  /* v8 ignore next -- node:fs rejects with Error instances; the String arm only satisfies the unknown narrowing. */
  return error instanceof Error ? error.message : String(error)
}

/**
 * The row one stat probe decides: a symlink to a directory is a directory
 * row, to a regular file a file row when files are requested, anything else
 * (or a broken link, decided by the caller) is no row. Pure over the probe
 * outcome so every arm pins without a filesystem symlink.
 * @param name - base name within the listed level.
 * @param path - absolute row path.
 * @param hidden - host-platform hidden convention.
 * @param targetIsDirectory - the probe saw a directory.
 * @param targetIsFile - the probe saw a regular file.
 * @param includeFiles - the listing asked for file rows.
 * @returns the row, or null when the browser cannot use the target.
 */
export function probedRow(
  name: string, path: string, hidden: boolean, targetIsDirectory: boolean, targetIsFile: boolean, includeFiles: boolean,
): DirectoryEntry | null {
  if (targetIsDirectory) return { name, path, hidden, kind: 'directory' }
  if (targetIsFile && includeFiles) return { name, path, hidden, kind: 'file' }
  return null
}

/**
 * One listing row for a dirent: directories (following symlinks) when the
 * browser picks a level to enter, plus regular files when it previews one.
 * Null for rows the browser cannot use — broken/cyclic links, non-regular
 * files that are neither directories (fifos, sockets, devices), and
 * non-directories when files are not requested. Exported for unit tests;
 * the level scan pre-filters, so production callers never send a
 * non-directory without the file flag.
 */
export async function directoryRow(
  parent: string,
  name: string,
  isDirectory: boolean,
  isFile: boolean,
  isSymbolicLink: boolean,
  signal: AbortSignal | undefined,
  includeFiles: boolean,
): Promise<DirectoryEntry | null> {
  const path = join(parent, name)
  const hidden = name.startsWith('.')
  if (isSymbolicLink && !isDirectory) {
    // The probe races the caller too: a symlink target on a stalled network
    // filesystem must not keep a departed caller's request alive.
    try {
      const target = await raceAbort(stat(path), signal)
      return probedRow(name, path, hidden, target.isDirectory(), target.isFile(), includeFiles)
    } catch {
      /* v8 ignore next 2 -- an abort landing mid-probe needs a stalled stat; the per-candidate check in list covers the settled path. */
      if (signal?.aborted) throw asError(signal.reason)
      // Broken or cyclic symlink: stat is the probe, failure means "not enterable".
      return null
    }
  }
  if (isDirectory) {
    // POSIX hidden convention; Windows' hidden attribute is not exposed by
    // dirents (Known Limitations). The client owns whether hidden rows show.
    return { name, path, hidden, kind: 'directory' }
  }
  // A non-symlink regular file is a row only when the caller asked for
  // files. No probe — the dirent kind is authoritative here.
  return isFile && includeFiles ? { name, path, hidden, kind: 'file' } : null
}

/** Validated plugin configuration. */
export interface Config {
  /** Complete-result bound of one listing level; see {@link BrowseDirectoryPicker.Config}. */
  maxEntries: number
  /** Page byte cap for one `readFile` call; see {@link BrowseDirectoryPicker.Config}. */
  maxReadBytes: number
}

/** The `ctx.directoryPicker` browse implementation (stable capability object per service life). */
export default class BrowseDirectoryPicker extends DirectoryPicker {
  /**
   * `maxEntries` bounds the complete listing level a single `list` call may
   * materialize and put on the wire: at most this many rows (hidden rows
   * included), with `truncated` flagging a cut level. The default follows
   * GitHub's web UI, which truncates directory listings at 1,000 entries.
   *
   * `maxReadBytes` bounds one `readFile` page: at most this many file bytes
   * are materialized for a page, with `truncated` flagging a longer file. A
   * wire `maxBytes` below this still shrinks the page, but never grows it
   * past the deployment bound.
   */
  static Config: z<Config> = z.object({
    maxEntries: z.natural().min(1).default(1000),
    maxReadBytes: z.natural().min(64).default(262144),
  })

  private readonly browseCapability: DirectoryPickerCapability = {
    kind: 'browse',
    list: (path, signal, options) => this.list(path, signal, options),
    createDirectory: (path, name) => this.createDirectory(path, name),
    readFile: (path, options, signal) => this.readFile(path, options, signal),
  }

  constructor(ctx: Context, private readonly config: Config) {
    super(ctx)
  }

  /**
   * The browse interaction capability.
   * @returns the stable `browse` capability object.
   */
  capability(): DirectoryPickerCapability {
    return this.browseCapability
  }

  private async list(path?: string, signal?: AbortSignal, options?: DirectoryListOptions): Promise<DirectoryListing> {
    const home = homedir()
    // The seam contract takes fully qualified paths only; resolve() would
    // silently rebase a relative or empty wire value under the host process
    // cwd (or, for rooted drive-less Windows forms, its current drive).
    if (path !== undefined && !fullyQualified(path)) {
      throw new DirectoryPickerError('directory-unreadable', path, `cannot list "${path}": not a fully qualified path`)
    }
    const target = resolve(path ?? home)
    // Stream the level (opendir, one dirent at a time) into a name-sorted
    // window of maxEntries + 1 candidates: memory stays bounded no matter how
    // many children the directory holds, the window keeps the name-sorted
    // head, and the +1 slot lets an in-window extra row prove the cut. A
    // window candidate that turns out non-enterable (broken symlink) is not
    // backfilled from beyond the window — an eviction already marks the
    // level truncated, which stays the honest answer.
    const keep = this.config.maxEntries + 1
    const window: ListingCandidate[] = []
    let evicted = false
    try {
      // Every filesystem await races the caller's signal: a stalled
      // opendir/read on a network filesystem must not keep a departed
      // caller's scan alive, and an already-aborted request rejects even
      // when the level is empty.
      const opening = opendir(target)
      const level = await raceAbort(opening, signal).catch((error: unknown) => {
        // The abandoned open can still mint a handle after the abort won;
        // close it so a departed caller cannot leak a descriptor. (A lost
        // race against opendir's own rejection has nothing to close, and
        // the close's own failure is swallowed — the request already
        // returned, so a cleanup error has no consumer.)
        void opening.then(dir => dir.close().catch(swallowCloseFailure), () => {
          // Already rejected: raceAbort surfaced or swallowed it.
        })
        throw error
      })
      try {
        for (;;) {
          const dirent = await raceAbort(level.read(), signal)
          if (dirent === null) break
          // Directories always contend for the window; regular files only
          // when the caller asked for them (a symlink needs the later probe
          // to decide which it is, so every symlink contends).
          const includeFiles = options?.includeFiles === true
          if (!dirent.isDirectory() && !dirent.isSymbolicLink() && (!includeFiles || !dirent.isFile())) continue
          const candidate = {
            name: dirent.name,
            isDirectory: dirent.isDirectory(),
            isFile: dirent.isFile(),
            isSymbolicLink: dirent.isSymbolicLink(),
          }
          if (boundedInsert(window, candidate, keep)) evicted = true
        }
      } finally {
        // Manual read() never auto-closes; close on every exit. The aborted
        // exit must not await it — Node queues close behind any in-flight
        // read, so awaiting would chain the departed caller back onto the
        // very stall the abort escaped (the abandoned read's settlement is
        // already swallowed by raceAbort).
        const closing = level.close()
        /* v8 ignore next 3 -- an abort between open and close needs a stalled read; the abandoned-close arm has no observable outcome. */
        if (signal?.aborted) {
          closing.catch(swallowCloseFailure)
        } else {
          await closing
        }
      }
    } catch (error: unknown) {
      // An abort is the caller's own reason, not an unreadable directory.
      signal?.throwIfAborted()
      throw new DirectoryPickerError('directory-unreadable', target, `cannot list ${target}: ${messageOf(error)}`)
    }
    const entries: DirectoryEntry[] = []
    let truncated = evicted
    const includeFiles = options?.includeFiles === true
    for (const candidate of window) {
      // A caller that departed between reads and probes stops before the
      // next probe (each probe's own await is raced inside directoryRow).
      signal?.throwIfAborted()
      const row = await directoryRow(
        target,
        candidate.name,
        candidate.isDirectory,
        candidate.isFile,
        candidate.isSymbolicLink,
        signal,
        includeFiles,
      )
      if (row === null) continue
      if (entries.length === this.config.maxEntries) {
        truncated = true
        break
      }
      entries.push(row)
    }
    return { path: target, home, crumbs: ancestryCrumbs(target), entries, truncated }
  }

  private async readFile(path: string, options?: DirectoryReadOptions, signal?: AbortSignal): Promise<DirectoryFilePage> {
    // Same fully-qualified fence as list: never resolve a wire path against
    // the cwd or the current drive.
    if (!fullyQualified(path)) {
      throw new DirectoryPickerError('file-unreadable', path, `cannot read "${path}": not a fully qualified path`)
    }
    const target = resolve(path)
    const offset = options?.offset ?? 0
    const count = options?.count
    // A wire maxBytes below the deployment bound shrinks the page; it never
    // grows past it. The controller validates non-negative integers, so the
    // seam reads a typed boundary here.
    const budget = Math.min(options?.maxBytes ?? this.config.maxReadBytes, this.config.maxReadBytes)
    let size: number
    try {
      const examined = await raceAbort(stat(target), signal)
      if (!examined.isFile()) {
        throw new DirectoryPickerError('file-unreadable', target, `cannot read "${target}": not a regular file`)
      }
      size = examined.size
    } catch (error: unknown) {
      signal?.throwIfAborted()
      if (error instanceof DirectoryPickerError) throw error
      throw new DirectoryPickerError('file-unreadable', target, `cannot read "${target}": ${messageOf(error)}`)
    }
    let handle: FileHandle | undefined
    try {
      handle = await raceAbort(open(target, 'r'), signal)
      // Binary sniff on the head: a NUL byte means bytes, not text. The
      // head is bounded and independent of the page budget.
      const headLength = Math.min(size, 8192)
      const head = Buffer.alloc(headLength)
      await raceAbort(handle.read(head, 0, headLength, 0), signal)
      if (head.includes(0)) {
        throw new DirectoryPickerError('file-unreadable', target, `cannot read "${target}": not a text file`)
      }
      // Stream whole lines up to the budget: memory stays O(budget) no
      // matter how large the file is. A trailing partial line cut by the
      // budget is dropped — the pager re-reads it whole on the next page.
      const chunks: Buffer[] = []
      let position = 0
      while (position < size && position < budget) {
        const length = Math.min(65536, budget - position, size - position)
        const chunk = Buffer.alloc(length)
        const { bytesRead } = await raceAbort(handle.read(chunk, 0, length, position), signal)
        /* v8 ignore next 3 -- a short read needs concurrent truncation; the loop bound keeps it finite. */
        if (bytesRead === 0) break
        chunks.push(chunk.subarray(0, bytesRead))
        position += bytesRead
      }
      const reachedEnd = position >= size
      const body = Buffer.concat(chunks).toString('utf8')
      const lines = body === '' ? [] : body.split('\n')
      // Complete lines only: drop the trailing empty split of a clean final
      // newline, and the partial line when the budget cut mid-line. A cut
      // exactly on a line boundary drops nothing.
      const complete = reachedEnd || body.endsWith('\n')
        ? (lines.length > 0 && lines[lines.length - 1] === '' ? lines.slice(0, -1) : lines)
        : lines.slice(0, -1)
      const window = count === undefined ? complete.slice(offset) : complete.slice(offset, offset + count)
      const text = window.join('\n')
      const truncated = offset > 0 || window.length < complete.length || !reachedEnd
      return {
        path: target,
        text,
        truncated,
        totalBytes: size,
        ...!truncated ? { totalLines: complete.length } : {},
      }
    } catch (error: unknown) {
      signal?.throwIfAborted()
      if (error instanceof DirectoryPickerError) throw error
      throw new DirectoryPickerError('file-unreadable', target, `cannot read "${target}": ${messageOf(error)}`)
    } finally {
      // Mirror list's close discipline: an aborted exit must not await the
      // close behind a stalled read. No handle exists when the open itself
      // failed.
      if (handle !== undefined) {
        const closing = handle.close()
        /* v8 ignore next 3 -- abort between last read and close needs a stall; no observable outcome. */
        if (signal?.aborted) {
          closing.catch(swallowCloseFailure)
        } else {
          await closing
        }
      }
    }
  }

  private async createDirectory(path: string, name: string): Promise<string> {
    // Same fully-qualified fence as list: never rebase a parent under the
    // cwd or the current drive.
    if (!fullyQualified(path)) {
      throw new DirectoryPickerError('directory-create-failed', path, `cannot create under "${path}": not a fully qualified parent path`)
    }
    const parent = resolve(path)
    // The backend owns segment validation; the Remote controller also refuses
    // invalid wire input, but direct service consumers must hit the same fence.
    if (name.trim() === '' || name === '.' || name === '..' || /[/\\]/.test(name)) {
      throw new DirectoryPickerError('directory-create-failed', join(parent, name), `"${name}" is not a single path segment`)
    }
    const target = join(parent, name)
    try {
      // Non-recursive: the parent is the directory the browser is showing, so
      // a missing parent is a real failure, not a level to invent.
      await mkdir(target)
      return target
    } catch (error: unknown) {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'EEXIST') {
        throw new DirectoryPickerError('directory-exists', target, `${target} already exists`)
      }
      throw new DirectoryPickerError('directory-create-failed', target, `cannot create ${target}: ${messageOf(error)}`)
    }
  }
}
