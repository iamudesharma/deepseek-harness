/** Upstream-Node child lifecycle and streaming custom-protocol carrier. */
import { DESKTOP_HOST_PROTOCOL_VERSION } from './host-protocol.ts';
/** Ready facts reported by one installed dsh child. */
export interface DesktopHostReady {
    readonly protocolVersion: typeof DESKTOP_HOST_PROTOCOL_VERSION;
    readonly dshVersion: string;
}
/** One dsh backend running under the bundled upstream Node.js executable. */
export declare class DesktopHostProcess {
    private readonly node;
    private readonly projectDir;
    private readonly inspectPort?;
    private child;
    private requestPipe;
    private responsePipe;
    private readonly responseDecoder;
    private requestWriteTail;
    private nextStreamId;
    private readonly pending;
    private readonly blockedResponses;
    private readyResolve;
    private readyReject;
    private readonly readyPromise;
    private exitPromise;
    private stderr;
    /**
     * @param node - absolute bundled upstream Node.js executable.
     * @param projectDir - active or staged desktop npm project.
     * @param inspectPort - optional loopback inspector port for workspace development.
     */
    constructor(node: string, projectDir: string, inspectPort?: number | undefined);
    /** Start the child once and resolve only after its complete composition is active. */
    start(): Promise<DesktopHostReady>;
    /** Forward one `dsh-app://app` request to the child without buffering its body. */
    fetch(request: Request): Promise<Response>;
    /** Request graceful teardown, then wait for child exit. */
    stop(): Promise<void>;
    private pumpRequest;
    private enqueueRequestFrame;
    private send;
    private acceptResponseBytes;
    private handleResponseFrame;
    private cancelResponse;
    private failPending;
    private finishPending;
    private resumeResponsePipe;
    private handleMessage;
    private fail;
}
//# sourceMappingURL=host-process.d.ts.map