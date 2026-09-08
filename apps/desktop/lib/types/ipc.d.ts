/** Typed preload operations exposed only by the Electron shell. */
import type { DesktopPluginRecord } from './project-manager.ts';
import type { DesktopLocale } from './locale.ts';
/** IPC channel names kept private to the desktop application bundle. */
export declare const DESKTOP_IPC: {
    readonly localeGet: "dsh-desktop:locale-get";
    readonly pluginsList: "dsh-desktop:plugins-list";
    readonly pluginsAdd: "dsh-desktop:plugins-add";
    readonly pluginsRemove: "dsh-desktop:plugins-remove";
    readonly pluginsUpdate: "dsh-desktop:plugins-update";
    readonly updatesCheck: "dsh-desktop:updates-check";
    readonly updatesInstall: "dsh-desktop:updates-install";
    readonly updatesState: "dsh-desktop:updates-state";
};
/** Desktop release update state rendered by desktop-owned UI. */
export interface DesktopUpdateState {
    readonly phase: 'idle' | 'checking' | 'available' | 'installing' | 'ready' | 'error';
    readonly version?: string;
    readonly message?: string;
}
/** Narrow bridge exposed through context isolation. */
export interface DshDesktopApi {
    readonly protocolVersion: 1;
    locale(): Promise<DesktopLocale>;
    readonly plugins: {
        list(): Promise<readonly DesktopPluginRecord[]>;
        add(spec: string): Promise<void>;
        remove(name: string): Promise<void>;
        update(name: string, version: string): Promise<void>;
    };
    readonly updates: {
        check(): Promise<DesktopUpdateState>;
        install(): Promise<void>;
        subscribe(listener: (state: DesktopUpdateState) => void): () => void;
    };
}
//# sourceMappingURL=ipc.d.ts.map