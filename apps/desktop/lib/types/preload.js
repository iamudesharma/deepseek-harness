/** Context-isolated renderer bridge for desktop package and update operations. */
import { contextBridge, ipcRenderer } from 'electron';
import { DESKTOP_IPC } from "./ipc.js";
const api = {
    protocolVersion: 1,
    locale: () => ipcRenderer.invoke(DESKTOP_IPC.localeGet),
    plugins: {
        list: () => ipcRenderer.invoke(DESKTOP_IPC.pluginsList),
        add: spec => ipcRenderer.invoke(DESKTOP_IPC.pluginsAdd, spec),
        remove: name => ipcRenderer.invoke(DESKTOP_IPC.pluginsRemove, name),
        update: (name, version) => ipcRenderer.invoke(DESKTOP_IPC.pluginsUpdate, name, version),
    },
    updates: {
        check: () => ipcRenderer.invoke(DESKTOP_IPC.updatesCheck),
        install: () => ipcRenderer.invoke(DESKTOP_IPC.updatesInstall),
        subscribe(listener) {
            const handle = (_event, state) => { listener(state); };
            ipcRenderer.on(DESKTOP_IPC.updatesState, handle);
            return () => { ipcRenderer.off(DESKTOP_IPC.updatesState, handle); };
        },
    },
};
contextBridge.exposeInMainWorld('dshDesktop', api);
//# sourceMappingURL=preload.js.map