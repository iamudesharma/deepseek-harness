/** Transactional owner of the reserved desktop profile and its private pnpm state. */
import type { DesktopPaths } from './paths.ts';
import { type DesktopRelease } from './release.ts';
/** Desktop plugin record derived from the installed profile. */
export interface DesktopPluginRecord {
    readonly name: string;
    readonly version: string;
}
/** Exact executables the desktop shell bundles. */
export interface DesktopRuntimeExecutables {
    readonly node: string;
    readonly pnpm: string;
}
/** Hooks that bind project replacement to backend lifecycle and health. */
export interface DesktopProjectHooks {
    /** Prove the staged dependency graph while the active backend is stopped. */
    healthCheck(projectDir: string): Promise<void>;
    /** Stop the active backend and await process exit before directory moves. */
    beforeActivate(): Promise<void>;
    /** Start the selected active project after commit or rollback. */
    afterActivate(): Promise<void>;
}
/** Supported dependency mutation. */
export type DesktopProjectMutation = {
    readonly type: 'plugin-add';
    readonly spec: string;
} | {
    readonly type: 'plugin-remove';
    readonly name: string;
} | {
    readonly type: 'plugin-update';
    readonly name: string;
    readonly version: string;
};
/**
 * Validate one registry package spec and return its requested package name when explicit.
 * @param spec - npm registry name with an optional version or tag.
 * @returns package name, or undefined when the spec's final name is registry-resolved.
 */
export declare function packageNameFromSpec(spec: string): string | undefined;
/** Verify the packaged offline seed before any content enters writable desktop state. */
export declare function verifySeedIntegrity(seedDir: string): void;
/** Transactional desktop npm project manager. */
export declare class DesktopProjectManager {
    readonly paths: DesktopPaths;
    readonly runtime: DesktopRuntimeExecutables;
    private lockDescriptor;
    /**
     * @param paths - Electron-owned package state and reserved desktop profile paths.
     * @param runtime - absolute bundled Node.js and pnpm entry paths.
     */
    constructor(paths: DesktopPaths, runtime: DesktopRuntimeExecutables);
    /** Recover an interrupted directory replacement before reading the active project. */
    recover(): void;
    /** Read the active desktop plugin inventory. */
    listPlugins(): readonly DesktopPluginRecord[];
    /** Read the exact dsh version installed in the active desktop project. */
    dshVersion(): string;
    private installedPackageVersion;
    /** Read the release version applied to the active desktop project. */
    releaseVersion(): string;
    /** Install or reconcile the active project to the Electron package's exact release. */
    applyRelease(seedDir: string, electronVersion: string, hooks: DesktopProjectHooks): Promise<boolean>;
    /** Apply one exact dependency mutation through a staging project. */
    mutate(mutation: DesktopProjectMutation, hooks: DesktopProjectHooks): Promise<void>;
    private newStagingProfile;
    private applyMutation;
    private mergeSeedPnpmState;
    private activate;
    private runPnpm;
    private writeLockOwner;
    private withLock;
}
/** Create seed metadata for one exact Electron and dsh release. */
export declare function createSeedMetadata(seedDir: string, release: DesktopRelease): void;
/**
 * Create metadata for the unpackaged development project that links the current workspace.
 * @param projectDir - Disposable development profile directory.
 * @param release - Release identity shared by the linked CLI package and Electron shell.
 */
export declare function createDevelopmentProjectMetadata(projectDir: string, release: DesktopRelease): void;
//# sourceMappingURL=project-manager.d.ts.map