/** Framed request and response bytes for the Electron Desktop Host transport. */
/** Protocol version shared with the Electron shell. */
export declare const DESKTOP_HOST_PROTOCOL_VERSION: 3;
/** Child descriptor that receives Electron request frames. */
export declare const DESKTOP_REQUEST_PIPE_FD = 3;
/** Child descriptor that emits Host response frames. */
export declare const DESKTOP_RESPONSE_PIPE_FD = 4;
/** Maximum raw body bytes carried by one data frame. */
export declare const DESKTOP_PIPE_CHUNK_BYTES: number;
/** One validated request-pipe frame. */
export type DesktopHostRequestFrame = {
    readonly type: 'start';
    readonly streamId: number;
    readonly url: string;
    readonly method: string;
    readonly headers: readonly [string, string][];
    readonly hasBody: boolean;
} | {
    readonly type: 'data';
    readonly streamId: number;
    readonly data: Buffer;
} | {
    readonly type: 'end' | 'cancel';
    readonly streamId: number;
};
/** Encode response metadata before any body frames. */
export declare function encodeDesktopResponseStart(streamId: number, response: {
    readonly status: number;
    readonly headers: readonly [string, string][];
    readonly hasBody: boolean;
}): Buffer;
/** Encode one bounded raw response-body chunk. */
export declare function encodeDesktopResponseData(streamId: number, data: Uint8Array): Buffer;
/** Encode normal response completion. */
export declare function encodeDesktopResponseEnd(streamId: number): Buffer;
/** Encode one response failure without exposing an Error object across processes. */
export declare function encodeDesktopResponseError(streamId: number, message: string): Buffer;
/** Incrementally decode validated request frames from the Electron byte pipe. */
export declare class DesktopHostRequestDecoder {
    private buffer;
    /**
     * Append bytes and return every complete request frame.
     * @param chunk - next bytes read from the Electron request pipe.
     * @returns complete frames in pipe order.
     */
    push(chunk: Buffer): DesktopHostRequestFrame[];
    /** Reject EOF that splits a frame. */
    finish(): void;
    private next;
    private parseStart;
}
//# sourceMappingURL=wire.d.ts.map