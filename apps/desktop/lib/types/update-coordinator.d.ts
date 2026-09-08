/** One Electron release stream for the version-bound shell and dsh seed. */
import { type AppUpdater } from 'electron-updater';
import type { DesktopUpdateState } from './ipc.ts';
/** Checks, downloads, and installs one complete Desktop release. */
export declare class DesktopUpdateCoordinator {
    private readonly publish;
    private readonly beforeRestart;
    private readonly updater;
    private readonly enabled;
    private availableVersion;
    private checkOperation;
    private installOperation;
    /**
     * @param publish - state sink for every desktop window.
     * @param beforeRestart - stop application-owned processes before replacement.
     * @param updater - Electron artifact updater; replaceable for tests.
     * @param enabled - whether this packaged process carries updater configuration.
     */
    constructor(publish: (state: DesktopUpdateState) => DesktopUpdateState, beforeRestart?: () => Promise<void>, updater?: AppUpdater, enabled?: () => boolean);
    /** Check the configured Desktop release stream and retain an available version. */
    check(): Promise<DesktopUpdateState>;
    /** Wait for an in-flight check, then download and install its retained release. */
    install(): Promise<DesktopUpdateState>;
    private doCheck;
    private doInstall;
}
//# sourceMappingURL=update-coordinator.d.ts.map