/**
 * Electron child-process entry: boots the desktop project without a listening
 * socket and carries API plus validated Web assets over framed byte pipes.
 * @module @deepseek-ai/dsh-desktop-host
 */
import { DESKTOP_HOST_PROTOCOL_VERSION } from './wire.ts';
export { DESKTOP_HOST_PROTOCOL_VERSION } from './wire.ts';
/** One request forwarded from Electron's `dsh-app://` handler. */
export interface DesktopHostFetchCommand {
    readonly streamId: number;
    readonly request: {
        readonly url: string;
        readonly method: string;
        readonly headers: readonly [string, string][];
    };
}
/** Commands accepted by the desktop child process. */
export type DesktopHostCommand = {
    readonly type: 'shutdown';
};
/** Events emitted by the desktop child process. */
export type DesktopHostEvent = {
    readonly type: 'ready';
    readonly protocolVersion: typeof DESKTOP_HOST_PROTOCOL_VERSION;
    readonly dshVersion: string;
} | {
    readonly type: 'fatal';
    readonly message: string;
};
/** Controller returned to tests and the self-executing process entry. */
export interface DesktopHostController {
    /** Installed dsh version carried by this host. */
    readonly dshVersion: string;
    /** Dispatch one custom-protocol request and stream its response to the response pipe. */
    fetch(command: DesktopHostFetchCommand, body: ReadableStream<Uint8Array> | null): Promise<void>;
    /** Abort one in-flight request. */
    cancel(streamId: number): void;
    /** Stop accepting messages and await complete host teardown. */
    dispose(): Promise<void>;
}
/**
 * Boot one installed desktop npm project.
 * @param projectDir - active or staged Electron-owned desktop profile.
 * @param writeResponse - serialized response-pipe writer that applies byte backpressure.
 * @param options - development-only allowance for workspace-linked bundle packages.
 * @returns controller after every Host and client-manifest row is active.
 */
export declare function runDesktopHost(projectDir: string, writeResponse: (frame: Buffer) => Promise<void>, options?: {
    allowLinkedPackages?: boolean;
}): Promise<DesktopHostController>;
//# sourceMappingURL=index.d.ts.map