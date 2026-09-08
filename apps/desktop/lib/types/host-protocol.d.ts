/** Versioned control messages and framed byte transport for the Desktop Host child. */
/** Protocol version implemented by the Electron shell and installed dsh Host. */
export declare const DESKTOP_HOST_PROTOCOL_VERSION: 3;
/** Child descriptor Electron writes request frames to. */
export declare const DESKTOP_REQUEST_PIPE_FD = 3;
/** Child descriptor Electron reads response frames from. */
export declare const DESKTOP_RESPONSE_PIPE_FD = 4;
/** Child descriptor reserved for Node's lifecycle IPC channel. */
export declare const DESKTOP_CONTROL_IPC_FD = 5;
/** Maximum raw body bytes carried by one data frame. */
export declare const DESKTOP_PIPE_CHUNK_BYTES: number;
/** Metadata that precedes one optional request body on the request pipe. */
export interface DesktopHostRequestStart {
    readonly url: string;
    readonly method: string;
    readonly headers: readonly [string, string][];
    readonly hasBody: boolean;
}
/** Commands retained on Node IPC because they do not carry Fetch payload bytes. */
export type DesktopHostCommand = {
    readonly type: 'shutdown';
};
/** Lifecycle events retained on Node IPC. */
export type DesktopHostEvent = {
    readonly type: 'ready';
    readonly protocolVersion: typeof DESKTOP_HOST_PROTOCOL_VERSION;
    readonly dshVersion: string;
} | {
    readonly type: 'fatal';
    readonly message: string;
};
/** One decoded response-pipe frame. */
export type DesktopHostResponseFrame = {
    readonly type: 'start';
    readonly streamId: number;
    readonly status: number;
    readonly headers: readonly [string, string][];
    readonly hasBody: boolean;
} | {
    readonly type: 'data';
    readonly streamId: number;
    readonly data: Buffer;
} | {
    readonly type: 'end';
    readonly streamId: number;
} | {
    readonly type: 'error';
    readonly streamId: number;
    readonly message: string;
};
/** Encode the metadata opening one request stream. */
export declare function encodeDesktopRequestStart(streamId: number, request: DesktopHostRequestStart): Buffer;
/** Encode one bounded raw request-body chunk. */
export declare function encodeDesktopRequestData(streamId: number, data: Uint8Array): Buffer;
/** Encode normal request-body completion. */
export declare function encodeDesktopRequestEnd(streamId: number): Buffer;
/** Encode cancellation of one request and its response. */
export declare function encodeDesktopRequestCancel(streamId: number): Buffer;
/** Incrementally decode validated response frames from the Host byte pipe. */
export declare class DesktopHostResponseDecoder {
    private buffer;
    /**
     * Append bytes and return every complete response frame.
     * @param chunk - next bytes read from the Host response pipe.
     * @returns complete frames in pipe order.
     */
    push(chunk: Buffer): DesktopHostResponseFrame[];
    /** Reject EOF that splits a frame. */
    finish(): void;
    private next;
    private parseStart;
    private parseError;
    private parseJson;
}
//# sourceMappingURL=host-protocol.d.ts.map