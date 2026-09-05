/**
 * Client-safe type surface of the directory-picking seam: what one browse level
 * looks like to a caller. Types only — no runtime code, and nothing here reaches
 * a Host-only symbol, so a Client compilation face reads exactly the signatures
 * the Host emits.
 *
 * @module @deepseek-ai/dsh-host-directory-picker/types
 */

/** One directory row: a listing child or a breadcrumb ancestor. */
export interface DirectoryEntry {
  /** Base name shown in a browser row (a root crumb carries its full path). */
  name: string
  /** Absolute host path — clients never join path segments themselves. */
  path: string
  /** Hidden by the host platform's convention (dot-prefixed on POSIX); the client owns whether to show it. */
  hidden: boolean
  /**
   * Row kind. Always present: backends stamp every row so a file-capable
   * browser can render files without re-probing each path.
   */
  kind: 'directory' | 'file'
}

/** One directory level plus its ancestry, as a browse backend reports it. */
export interface DirectoryListing {
  /** Absolute path of the listed directory. */
  path: string
  /** The host account's home directory (breadcrumb "Home" rooting). */
  home: string
  /**
   * Ancestor chain from the filesystem root to the listed directory
   * inclusive; every crumb is a jump target (crumb `hidden` is always false).
   */
  crumbs: DirectoryEntry[]
  /** Direct child directories, name-sorted; symlinks to directories included. */
  entries: DirectoryEntry[]
  /**
   * True when the backend cut `entries` at its complete-result bound: the
   * level has more child directories than reported, and the missing rows are
   * the name-sorted tail (hidden rows count toward the bound).
   */
  truncated: boolean
}

/** Options selecting what one listing level carries. */
export interface DirectoryListOptions {
  /**
   * Include regular-file rows (`kind: 'file'`) alongside directories.
   * Absent or false lists directories only, exactly as before.
   */
  includeFiles?: boolean
}

/** Options paging one bounded text-file read. */
export interface DirectoryReadOptions {
  /** First line to return, zero-based; defaults to the file start. */
  offset?: number
  /** Lines to return; absent reads to the byte bound. */
  count?: number
  /** Page byte cap; defaults to the backend's configured maximum. */
  maxBytes?: number
}

/** One bounded text page of a file, in line order. */
export interface DirectoryFilePage {
  /** Absolute path the page was read from. */
  path: string
  /** Page text; lines joined by `\n`, without a trailing newline. */
  text: string
  /** True when the file holds more bytes than this page carries. */
  truncated: boolean
  /** Total file bytes at read time; the pager compares against this. */
  totalBytes: number
  /** Total lines, present only when the whole file fit in the page. */
  totalLines?: number
}
