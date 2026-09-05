/** Behavior of the browse backend over a real temporary directory tree. */

import { mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises'
import { homedir, tmpdir } from 'node:os'
import { basename, join } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { DirectoryPickerError } from '@deepseek-ai/dsh-host-directory-picker'
import type { DirectoryPickerBrowseCapability } from '@deepseek-ai/dsh-host-directory-picker'
import BrowseDirectoryPicker, { boundedInsert, directoryRow, fullyQualified, probedRow, raceAbort } from '../src/index.ts'
import type { ListingCandidate } from '../src/index.ts'

let root: string
let capability: DirectoryPickerBrowseCapability
let dispose: () => Promise<void>

beforeAll(async () => {
  root = await mkdtemp(join(tmpdir(), 'dsh-browse-'))
  await mkdir(join(root, 'projects'))
  await mkdir(join(root, 'projects', 'harness'))
  await mkdir(join(root, '.hidden-dir'))
  await writeFile(join(root, 'notes.txt'), 'not a directory')
  await symlink(join(root, 'projects'), join(root, 'linked'), 'junction')
  await symlink(join(root, 'gone'), join(root, 'broken'), 'junction')
  try {
    await symlink(join(root, 'notes.txt'), join(root, 'file-link'))
  } catch {
    // Windows denies unprivileged file symlinks; the file-link row only
    // feeds the POSIX lanes' coverage of the symlink-to-file arm, and every
    // assertion below expects it to be filtered out anyway.
  }

  const ctx = new Context()
  const fiber = ctx.plugin(BrowseDirectoryPicker)
  await fiber.await()
  const picked = ctx.get('directoryPicker')!.capability()
  if (picked.kind !== 'browse') throw new Error('browse backend must advertise the browse capability')
  capability = picked
  dispose = () => fiber.dispose()
})

afterAll(async () => {
  await dispose()
  await rm(root, { recursive: true, force: true })
})

describe('BrowseDirectoryPicker', () => {
  it('lists directories only, flags hidden rows, follows symlinks, skips broken links, sorts by name', async () => {
    const listing = await capability.list(root)
    expect(listing.path).toBe(root)
    expect(listing.home).toBe(homedir())
    expect(listing.entries.map(entry => entry.name)).toEqual(['.hidden-dir', 'linked', 'projects'])
    expect(listing.entries.map(entry => entry.hidden)).toEqual([true, false, false])
    // Every row carries its kind; a plain listing holds directories only.
    expect(listing.entries.map(entry => entry.kind)).toEqual(['directory', 'directory', 'directory'])
    // Every entry path is absolute and host-joined — clients never join segments.
    expect(listing.entries.every(entry => entry.path === join(root, entry.name))).toBe(true)
    // Well under the default bound: the complete level, not a cut one.
    expect(listing.truncated).toBe(false)
  })

  it('cuts a level at maxEntries keeping the name-sorted head, and flags the cut', async () => {
    const ctx = new Context()
    const fiber = ctx.plugin(BrowseDirectoryPicker, { maxEntries: 1, maxReadBytes: 262144 })
    await fiber.await()
    const bounded = ctx.get('directoryPicker')!.capability()
    if (bounded.kind !== 'browse') throw new Error('browse backend must advertise the browse capability')
    try {
      const cut = await bounded.list(root)
      expect(cut.entries.map(entry => entry.name)).toEqual(['.hidden-dir'])
      expect(cut.truncated).toBe(true)
      // Exactly at the bound is complete, not truncated.
      const exact = await bounded.list(join(root, 'projects'))
      expect(exact.entries.map(entry => entry.name)).toEqual(['harness'])
      expect(exact.truncated).toBe(false)
      // A level that fits the window but exceeds the bound (two rows, bound
      // one): the in-window extra row proves the cut without any eviction.
      await mkdir(join(root, 'projects', 'harness', 'a'))
      await mkdir(join(root, 'projects', 'harness', 'b'))
      const inWindow = await bounded.list(join(root, 'projects', 'harness'))
      expect(inWindow.entries.map(entry => entry.name)).toEqual(['a'])
      expect(inWindow.truncated).toBe(true)
    } finally {
      await fiber.dispose()
    }
  })

  it('stops the scan with the caller: an aborted signal rejects with its own reason', async () => {
    const gone = new AbortController()
    gone.abort(new Error('caller left'))
    // The abort surfaces as-is, not dressed as an unreadable directory —
    // and rejects even before any level row is read.
    await expect(capability.list(root, gone.signal)).rejects.toThrow('caller left')
    // The abandoned open that still succeeds is closed, not leaked.
    await new Promise(resolve => setTimeout(resolve, 10))
    // Aborted against a missing target: the abandoned open rejects on its
    // own and there is nothing to close.
    await expect(capability.list(join(root, 'no-such-dir'), gone.signal)).rejects.toThrow('caller left')
    await new Promise(resolve => setTimeout(resolve, 10))
    // A live signal leaves a normal listing untouched — the reads and the
    // symlink probes race it without ever losing.
    const live = new AbortController()
    const complete = await capability.list(root, live.signal)
    expect(complete.truncated).toBe(false)
    expect(complete.entries.map(entry => entry.name)).toContain('linked')
    // A live signal changes nothing about ordinary failures.
    const missing = join(root, 'no-such-dir')
    const failure = await capability.list(missing, live.signal).catch((error: unknown) => error)
    expect(failure).toBeInstanceOf(DirectoryPickerError)
    expect((failure as DirectoryPickerError).code).toBe('directory-unreadable')
  })

  it('raceAbort follows the operation until the signal wins, and swallows the abandoned settlement', async () => {
    // No signal / settled operations: plain passthrough, listener removed.
    await expect(raceAbort(Promise.resolve('ok'), undefined)).resolves.toBe('ok')
    const live = new AbortController()
    await expect(raceAbort(Promise.resolve('ok'), live.signal)).resolves.toBe('ok')
    // Failure passthrough keeps the operation's own error.
    await expect(raceAbort(Promise.reject(new Error('raw failure')), live.signal)).rejects.toThrow('raw failure')
    // The abort wins over a pending operation and carries its own reason;
    // the operation's late rejection is swallowed, never unhandled.
    const rejections: unknown[] = []
    const onUnhandled = (reason: unknown): void => { rejections.push(reason) }
    process.on('unhandledRejection', onUnhandled)
    try {
      let rejectLate!: (reason: unknown) => void
      const pending = new Promise<never>((_resolve, reject) => { rejectLate = reject })
      const controller = new AbortController()
      const raced = raceAbort(pending, controller.signal)
      // A bare-string abort reason exercises the Error wrap.
      controller.abort('caller left')
      await expect(raced).rejects.toThrow('caller left')
      rejectLate(new Error('late read failure'))
      await new Promise(resolve => setTimeout(resolve, 10))
      expect(rejections).toEqual([])
    } finally {
      process.off('unhandledRejection', onUnhandled)
    }
  })

  it('boundedInsert keeps the window name-sorted and bounded, reporting evictions', () => {
    const candidate = (name: string): ListingCandidate => ({ name, isDirectory: true, isFile: false, isSymbolicLink: false })
    const window: ListingCandidate[] = []
    expect(boundedInsert(window, candidate('m'), 2)).toBe(false)
    expect(boundedInsert(window, candidate('z'), 2)).toBe(false)
    // A smaller name lands in place and pushes the current largest out.
    expect(boundedInsert(window, candidate('a'), 2)).toBe(true)
    expect(window.map(entry => entry.name)).toEqual(['a', 'm'])
    // A name at or beyond the full window's tail rejects on one comparison.
    expect(boundedInsert(window, candidate('t'), 2)).toBe(true)
    expect(window.map(entry => entry.name)).toEqual(['a', 'm'])
    expect(boundedInsert(window, candidate('m'), 2)).toBe(true)
    expect(window.map(entry => entry.name)).toEqual(['a', 'm'])
  })

  it('reports the ancestry as jump-target crumbs ending at the listed directory', async () => {
    const listing = await capability.list(join(root, 'projects'))
    const tail = listing.crumbs.at(-1)!
    expect(tail).toMatchObject({ name: 'projects', path: join(root, 'projects'), hidden: false, kind: 'directory' })
    expect(listing.crumbs.at(-2)!.path).toBe(root)
    expect(listing.crumbs.at(-2)!.name).toBe(basename(root))
    // The chain starts at the filesystem root, whose crumb is labeled by its full path.
    expect(listing.crumbs[0]!.name).toBe(listing.crumbs[0]!.path)
  })

  it('lists the home directory when no path is given', async () => {
    const listing = await capability.list()
    expect(listing.path).toBe(homedir())
  })

  it('throws directory-unreadable for a missing target', async () => {
    const missing = join(root, 'no-such-dir')
    const failure = await capability.list(missing).catch((error: unknown) => error)
    expect(failure).toBeInstanceOf(DirectoryPickerError)
    expect((failure as DirectoryPickerError).code).toBe('directory-unreadable')
    expect((failure as DirectoryPickerError).path).toBe(missing)
  })

  it('classifies fully qualified paths per platform (drive-less rooted Windows forms rejected)', () => {
    expect(fullyQualified('/home/x', 'linux')).toBe(true)
    expect(fullyQualified('x/y', 'darwin')).toBe(false)
    expect(fullyQualified('C:\\projects', 'win32')).toBe(true)
    expect(fullyQualified('C:/projects', 'win32')).toBe(true)
    expect(fullyQualified('\\\\server\\share', 'win32')).toBe(true)
    expect(fullyQualified('//server/share/deep', 'win32')).toBe(true)
    // Rooted but drive-less: isAbsolute accepts these, yet resolve() would
    // inject the process's current drive.
    expect(fullyQualified('\\foo', 'win32')).toBe(false)
    expect(fullyQualified('/foo', 'win32')).toBe(false)
    expect(fullyQualified('C:relative', 'win32')).toBe(false)
    // Incomplete UNC prefixes collapse to drive-relative roots under resolve().
    expect(fullyQualified('\\\\', 'win32')).toBe(false)
    expect(fullyQualified('\\\\server', 'win32')).toBe(false)
    expect(fullyQualified('\\\\server\\', 'win32')).toBe(false)
  })

  it('rejects non-absolute paths instead of rebasing them under the process cwd', async () => {
    for (const relative of ['', 'projects', './projects', '..']) {
      const listFailure = await capability.list(relative).catch((error: unknown) => error)
      expect(listFailure).toBeInstanceOf(DirectoryPickerError)
      expect((listFailure as DirectoryPickerError).code).toBe('directory-unreadable')
      expect((listFailure as DirectoryPickerError).path).toBe(relative)
      const createFailure = await capability.createDirectory(relative, 'child').catch((error: unknown) => error)
      expect(createFailure).toBeInstanceOf(DirectoryPickerError)
      expect((createFailure as DirectoryPickerError).code).toBe('directory-create-failed')
      expect((createFailure as DirectoryPickerError).path).toBe(relative)
    }
  })

  it('creates one child directory and surfaces it in the next listing', async () => {
    const created = await capability.createDirectory(root, 'fresh')
    expect(created).toBe(join(root, 'fresh'))
    const listing = await capability.list(root)
    expect(listing.entries.map(entry => entry.name)).toContain('fresh')
  })

  it('refuses an existing child with directory-exists', async () => {
    const failure = await capability.createDirectory(root, 'projects').catch((error: unknown) => error)
    expect(failure).toBeInstanceOf(DirectoryPickerError)
    expect((failure as DirectoryPickerError).code).toBe('directory-exists')
  })

  it('refuses non-segment names and other filesystem failures with directory-create-failed', async () => {
    for (const name of ['', '  ', '.', '..', 'a/b', 'a\\b']) {
      const failure = await capability.createDirectory(root, name).catch((error: unknown) => error)
      expect(failure).toBeInstanceOf(DirectoryPickerError)
      expect((failure as DirectoryPickerError).code).toBe('directory-create-failed')
    }
    // Missing parent is a real failure, not a level to invent.
    const missingParent = await capability.createDirectory(join(root, 'no-such-dir'), 'child').catch((error: unknown) => error)
    expect((missingParent as DirectoryPickerError).code).toBe('directory-create-failed')
  })

  it('lists file rows only when asked, name-sorted beside directories', async () => {
    const withFiles = await capability.list(root, undefined, { includeFiles: true })
    const byName = new Map(withFiles.entries.map(entry => [entry.name, entry.kind]))
    expect(byName.get('notes.txt')).toBe('file')
    expect(byName.get('projects')).toBe('directory')
    expect(byName.get('linked')).toBe('directory')
    // The file symlink only exists where the platform allows creating one.
    if (process.platform !== 'win32') expect(byName.get('file-link')).toBe('file')
    expect(withFiles.truncated).toBe(false)
  })

  it('reads a whole text file with its byte facts', async () => {
    const page = await capability.readFile(join(root, 'notes.txt'))
    expect(page).toMatchObject({ path: join(root, 'notes.txt'), text: 'not a directory', truncated: false })
    expect(page.totalBytes).toBe('not a directory'.length)
    expect(page.totalLines).toBe(1)
  })

  it('reads an empty file as one empty complete page', async () => {
    await writeFile(join(root, 'empty.txt'), '')
    const page = await capability.readFile(join(root, 'empty.txt'))
    expect(page).toMatchObject({ text: '', truncated: false, totalBytes: 0, totalLines: 0 })
  })

  it('pages a multi-line file by line window and flags the cut', async () => {
    await writeFile(join(root, 'lines.txt'), 'one\ntwo\nthree\nfour\n')
    const first = await capability.readFile(join(root, 'lines.txt'), { offset: 1, count: 2 })
    expect(first.text).toBe('two\nthree')
    expect(first.truncated).toBe(true)
    expect(first.totalLines).toBeUndefined()
    const tail = await capability.readFile(join(root, 'lines.txt'), { offset: 3 })
    expect(tail.text).toBe('four')
    expect(tail.truncated).toBe(true)
  })

  it('caps a page at the byte bound and drops the cut line whole', async () => {
    await writeFile(join(root, 'rows.txt'), Array.from({ length: 10 }, (_, i) => `row-0${i}`).join('\n') + '\n')
    const ctx = new Context()
    const fiber = ctx.plugin(BrowseDirectoryPicker, { maxEntries: 1000, maxReadBytes: 64 })
    await fiber.await()
    const bounded = ctx.get('directoryPicker')!.capability()
    if (bounded.kind !== 'browse') throw new Error('browse backend must advertise the browse capability')
    try {
      const page = await bounded.readFile(join(root, 'rows.txt'))
      // Ten 7-byte rows are 70 bytes: 64 bytes hold nine rows plus a cut
      // tenth, which is dropped whole.
      expect(page.text).toBe(Array.from({ length: 9 }, (_, i) => `row-0${i}`).join('\n'))
      expect(page.truncated).toBe(true)
      expect(page.totalBytes).toBe(70)
      expect(page.totalLines).toBeUndefined()
      // A wire maxBytes below the deployment bound shrinks the page.
      const smaller = await bounded.readFile(join(root, 'rows.txt'), { maxBytes: 10 })
      expect(smaller.text).toBe('row-00')
      expect(smaller.truncated).toBe(true)
      // A cut exactly on a line boundary drops nothing.
      const exact = await bounded.readFile(join(root, 'rows.txt'), { maxBytes: 63 })
      expect(exact.text).toBe(Array.from({ length: 9 }, (_, i) => `row-0${i}`).join('\n'))
      expect(exact.truncated).toBe(true)
    } finally {
      await fiber.dispose()
    }
  })

  it('reads under a live signal and decides probed rows without the filesystem', async () => {
    const live = new AbortController()
    const page = await capability.readFile(join(root, 'notes.txt'), undefined, live.signal)
    expect(page.truncated).toBe(false)
    expect(probedRow('linked', join(root, 'linked'), false, true, false, false))
      .toMatchObject({ kind: 'directory' })
    expect(probedRow('file-link', join(root, 'file-link'), false, false, true, true))
      .toMatchObject({ kind: 'file' })
    expect(probedRow('file-link', join(root, 'file-link'), false, false, true, false)).toBeNull()
    expect(probedRow('fifo', join(root, 'fifo'), false, false, false, true)).toBeNull()
    // Non-regular, non-directory dirents never become rows, with or
    // without the file flag; the level scan pre-filters them, so this pins
    // the row decision itself without a platform fifo.
    expect(await directoryRow(root, 'fifo', false, false, false, undefined, true)).toBeNull()
    expect(await directoryRow(root, 'fifo', false, false, false, undefined, false)).toBeNull()
  })

  it('refuses binary content, directories, missing paths, and relative paths', async () => {
    await writeFile(join(root, 'binary.bin'), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0x0a]))
    const binary = await capability.readFile(join(root, 'binary.bin')).catch((error: unknown) => error)
    expect(binary).toBeInstanceOf(DirectoryPickerError)
    expect((binary as DirectoryPickerError).code).toBe('file-unreadable')
    const directory = await capability.readFile(root).catch((error: unknown) => error)
    expect((directory as DirectoryPickerError).code).toBe('file-unreadable')
    const missing = await capability.readFile(join(root, 'no-such-file')).catch((error: unknown) => error)
    expect((missing as DirectoryPickerError).code).toBe('file-unreadable')
    expect((missing as DirectoryPickerError).path).toBe(join(root, 'no-such-file'))
    const relative = await capability.readFile('notes.txt').catch((error: unknown) => error)
    expect((relative as DirectoryPickerError).code).toBe('file-unreadable')
    // An aborted read rejects with the caller's reason, not a file failure.
    const gone = new AbortController()
    gone.abort(new Error('caller left'))
    await expect(capability.readFile(join(root, 'notes.txt'), undefined, gone.signal)).rejects.toThrow('caller left')
  })
})
