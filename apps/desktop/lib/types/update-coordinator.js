/** One Electron release stream for the version-bound shell and dsh seed. */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { app } from 'electron';
import electronUpdater from 'electron-updater';
const { autoUpdater } = electronUpdater;
/** Checks, downloads, and installs one complete Desktop release. */
export class DesktopUpdateCoordinator {
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
    constructor(publish, beforeRestart = async () => { }, updater = autoUpdater, enabled = () => (app.isPackaged && existsSync(join(process.resourcesPath, 'app-update.yml')))) {
        this.publish = publish;
        this.beforeRestart = beforeRestart;
        this.updater = updater;
        this.enabled = enabled;
        this.updater.autoDownload = false;
        this.updater.autoInstallOnAppQuit = false;
    }
    /** Check the configured Desktop release stream and retain an available version. */
    async check() {
        if (this.installOperation !== undefined)
            return this.installOperation;
        if (this.checkOperation !== undefined)
            return this.checkOperation;
        this.checkOperation = this.doCheck().finally(() => { this.checkOperation = undefined; });
        return this.checkOperation;
    }
    /** Wait for an in-flight check, then download and install its retained release. */
    async install() {
        if (this.installOperation !== undefined)
            return this.installOperation;
        this.installOperation = (async () => {
            await this.checkOperation;
            return this.doInstall();
        })().finally(() => { this.installOperation = undefined; });
        return this.installOperation;
    }
    async doCheck() {
        this.publish({ phase: 'checking' });
        try {
            if (!this.enabled()) {
                this.availableVersion = undefined;
                return this.publish({ phase: 'idle' });
            }
            const result = await this.updater.checkForUpdates();
            const version = result?.isUpdateAvailable === true ? result.updateInfo.version : undefined;
            this.availableVersion = version;
            return version === undefined
                ? this.publish({ phase: 'idle' })
                : this.publish({ phase: 'available', version });
        }
        catch (error) {
            this.availableVersion = undefined;
            return this.publish({
                phase: 'error',
                message: error instanceof Error ? error.message : String(error),
            });
        }
    }
    async doInstall() {
        const version = this.availableVersion;
        if (version === undefined) {
            throw new Error('desktop update: no verified update is available');
        }
        this.publish({ phase: 'installing', version });
        try {
            await this.updater.downloadUpdate();
            this.availableVersion = undefined;
            const ready = this.publish({ phase: 'ready', version });
            await this.beforeRestart();
            this.updater.quitAndInstall(false, true);
            return ready;
        }
        catch (error) {
            return this.publish({
                phase: 'error',
                version,
                message: error instanceof Error ? error.message : String(error),
            });
        }
    }
}
//# sourceMappingURL=update-coordinator.js.map