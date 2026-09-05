/** Filesystem-fault paths of the browse backend's file reader. */

import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { DirectoryPickerError } from '@deepseek-ai/dsh-host-directory-picker'
import type { DirectoryPickerBrowseCapability } from '@deepseek-ai/dsh-host-directory-picker'
import BrowseDirectoryPicker from '../src/index.ts'

// An EACCES between a successful stat and the open is a nondeterministic
// input — a real composition hits it through revoked permissions or a
// vanishing file — so the fault is mocked at the filesystem boundary while
// stat, directory reads, and everything else stay real.
vi.mock('node:fs/promises', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:fs/promises')>()
  return {
    ...actual,
    open: async (path: unknown, ...rest: unknown[]) => {
      if (typeof path === 'string' && path.endsWith('locked.txt')) {
        throw Object.assign(new Error(`EACCES: permission denied, open '${path}'`), { code: 'EACCES' })
      }
      return (actual.open as (...args: unknown[]) => Promise<never>)(path, ...rest)
    },
  }
})

let root: string
let capability: DirectoryPickerBrowseCapability
let dispose: () => Promise<void>

beforeAll(async () => {
  root = await mkdtemp(join(tmpdir(), 'dsh-browse-faults-'))
  await writeFile(join(root, 'locked.txt'), 'revoked before open')

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

describe('BrowseDirectoryPicker file-read faults', () => {
  it('maps an open failure after a successful stat onto file-unreadable', async () => {
    const failure = await capability.readFile(join(root, 'locked.txt')).catch((error: unknown) => error)
    expect(failure).toBeInstanceOf(DirectoryPickerError)
    expect(failure).toMatchObject({ code: 'file-unreadable', path: join(root, 'locked.txt') })
  })
})
