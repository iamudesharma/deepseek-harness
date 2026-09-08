//#region lib/types/preload-app.js
/** Minimal marker that selects the desktop custom-protocol API carrier. */
require("electron").contextBridge.exposeInMainWorld("dshDesktop", { protocolVersion: 1 });
//#endregion
