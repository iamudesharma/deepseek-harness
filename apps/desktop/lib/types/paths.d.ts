/** Filesystem ownership for the Electron-managed desktop installation. */
/** Stable desktop installation paths under the shared Harness home. */
export interface DesktopPaths {
    readonly root: string;
    readonly profile: string;
    readonly staging: string;
    readonly rollback: string;
    readonly pending: string;
    readonly lock: string;
    readonly pnpm: {
        readonly root: string;
        readonly store: string;
        readonly cache: string;
        readonly state: string;
        readonly config: string;
        readonly home: string;
    };
}
/**
 * Resolve every Electron-owned path without changing the shared data roots.
 * @param dshHome - Harness home shared with npm-installed dsh.
 * @returns immutable desktop path set.
 */
export declare function resolveDesktopPaths(dshHome?: string): DesktopPaths;
//# sourceMappingURL=paths.d.ts.map