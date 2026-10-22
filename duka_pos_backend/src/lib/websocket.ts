// RFC 6455 server-side framing, dependency-free.
//
// The live channel needs a WebSocket, and the backend's dependency list is
// deliberately short. Hand-rolling the wire format is normally the wrong call —
// a protocol implementation is a library's job — so the reasons this one is
// short and honest are worth stating:
//
//  1. THE CLIENT IS OUR OWN TILL. Not a browser, not a third party. The frames
//     this side has to parse are the handful our app sends, and it can rely on
//     the text frames this side sends.
//  2. EVERY BIT IS TESTED HERE. The masking arithmetic, the length extensions,
//     the close handshake and every invalid input have cases in
//     websocket.test.ts, and the route test drives the whole thing over a real
//     TCP socket with no library in between.
//  3. IT IS ONE FILE AND IT IS PURE. No timers, no sockets, no state. If the
//     operator later prefers `ws`, this file is replaced and nothing else moves.

import { createHash } from 'node:crypto';

export const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/** Opcodes this gateway uses or must recognise. */
export const OPCODE_CONTINUATION = 0x0;
export const OPCODE_TEXT = 0x1;
export const OPCODE_CLOSE = 0x8;
export const OPCODE_PING = 0x9;
export const OPCODE_PONG = 0xa;

/** The largest payload a control frame may carry. Beyond this the frame is not
 * a control frame, whatever its opcode says. */
const MAX_CONTROL_PAYLOAD = 125;

/**
 * The `Sec-WebSocket-Accept` value for a client's offer.
 *
 * The transform is fixed by the RFC — the GUID concatenated with the client's
 * key, hashed. It is not a security check on its own: it proves the server can
 * read the offer, and nothing more. Authentication is the token, further down.
 */
export function acceptKeyFor(clientKey: string): string {
  return createHash('sha1').update(clientKey + WS_GUID).digest('base64');
}

/** The 101 response lines that complete the handshake. */
export function handshakeResponse(clientKey: string): string {
  return [
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: websocket',
    'Connection: Upgrade',
    `Sec-WebSocket-Accept: ${acceptKeyFor(clientKey)}`,
    '\r\n',
  ].join('\r\n');
}

/**
 * Encodes one server-to-client frame.
 *
 * Server frames are never masked — the RFC requires the opposite direction to
 * mask, and a server that masked would be talking to a client that does not
 * expect it.
 */
export function encodeFrame(payload: string | Buffer, opcode: number = OPCODE_TEXT): Buffer {
  const data = typeof payload === 'string' ? Buffer.from(payload, 'utf8') : payload;
  const header: number[] = [0x80 | opcode];
  if (data.length < 126) {
    header.push(data.length);
  } else if (data.length < 65536) {
    header.push(126, (data.length >> 8) & 0xff, data.length & 0xff);
  } else {
    const big = Buffer.alloc(8);
    big.writeUInt32BE(Math.floor(data.length / 2 ** 32), 0);
    big.writeUInt32BE(data.length >>> 0, 4);
    header.push(127, ...big);
  }
  return Buffer.concat([Buffer.from(header), data]);
}

export function encodeClose(code: number, reason = ''): Buffer {
  const payload = Buffer.alloc(2 + Buffer.byteLength(reason));
  payload.writeUInt16BE(code, 0);
  payload.write(reason, 2);
  return encodeFrame(payload, OPCODE_CLOSE);
}

export type DecodedFrame =
  | { kind: 'incomplete' }
  | { kind: 'invalid'; reason: string }
  | {
      kind: 'frame';
      opcode: number;
      payload: Buffer;
      fin: boolean;
      /** Bytes the frame occupies, so the caller can slice the buffer. */
      bytesConsumed: number;
    };

/**
 * Parses one client-to-server frame from the front of [buffer].
 *
 * Client frames MUST be masked, and an unmasked one is a protocol violation
 * the gateway answers with a 1002 close — accepted here as a classification
 * rather than an exception, so the caller decides what a protocol violation
 * means (failing the connection, or logging it) and the parser stays pure.
 *
 * Returns `incomplete` rather than throwing when more bytes are needed: a
 * socket delivers fragments of a header as readily as a whole one, and a
 * parser that threw on a short read would need a retry loop around it.
 */
export function decodeFrame(buffer: Buffer): DecodedFrame {
  if (buffer.length < 2) return { kind: 'incomplete' };
  const first = buffer[0];
  const second = buffer[1];
  const fin = (first & 0x80) !== 0;
  const opcode = first & 0x0f;
  const masked = (second & 0x80) !== 0;
  let length = second & 0x7f;

  let offset = 2;
  if (length === 126) {
    if (buffer.length < offset + 2) return { kind: 'incomplete' };
    length = buffer.readUInt16BE(offset);
    offset += 2;
  } else if (length === 127) {
    if (buffer.length < offset + 8) return { kind: 'incomplete' };
    // A frame larger than a 32-bit signed integer is either malicious or
    // broken, and JS cannot even address it usefully.
    if (buffer.readUInt32BE(offset) !== 0) return { kind: 'invalid', reason: 'FRAME_TOO_LARGE' };
    length = buffer.readUInt32BE(offset + 4);
    offset += 8;
  }

  const isControl = (opcode & 0x8) !== 0;
  if (isControl && length > MAX_CONTROL_PAYLOAD) {
    return { kind: 'invalid', reason: 'CONTROL_FRAME_TOO_LARGE' };
  }

  let mask: Buffer | null = null;
  if (masked) {
    if (buffer.length < offset + 4) return { kind: 'incomplete' };
    mask = buffer.subarray(offset, offset + 4);
    offset += 4;
  } else {
    // A client that does not mask is not a client this gateway talks to.
    return { kind: 'invalid', reason: 'CLIENT_FRAMES_MUST_BE_MASKED' };
  }

  if (buffer.length < offset + length) return { kind: 'incomplete' };

  const payload = Buffer.allocUnsafe(length);
  for (let index = 0; index < length; index += 1) {
    // The rolling index, not `index % 4` over the whole payload: this is the
    // classic off-by-one that makes a frame decode correctly for the first
    // four bytes and wrongly ever after.
    payload[index] = buffer[offset + index] ^ mask[index % 4];
  }

  return { kind: 'frame', opcode, payload, fin, bytesConsumed: offset + length };
}

/**
 * Reads every complete frame out of a buffer, plus what is left over.
 *
 * Keeps the leftover rather than assuming the buffer ends on a boundary: a
 * socket may deliver half of one frame and all of the next, and dropping the
 * half is how a connection starts answering nonsense.
 */
export function drainFrames(buffer: Buffer): {
  frames: ExtractedFrame[];
  rest: Buffer;
  /** Set when the buffer holds a frame this side refuses, so the caller can
   * end the connection instead of waiting for more bytes that will never
   * arrive. */
  invalid?: string;
} {
  const frames: ExtractedFrame[] = [];
  let cursor = buffer;
  for (;;) {
    const decoded = decodeFrame(cursor);
    if (decoded.kind === 'invalid') return { frames, rest: cursor, invalid: decoded.reason };
    if (decoded.kind !== 'frame') return { frames, rest: cursor };
    frames.push({ opcode: decoded.opcode, payload: decoded.payload, fin: decoded.fin });
    cursor = cursor.subarray(decoded.bytesConsumed);
  }
}

export type ExtractedFrame = { opcode: number; payload: Buffer; fin: boolean };

/**
 * Applies or removes the client mask.
 *
 * Exposed because the test asserts it directly: this is the one line of
 * arithmetic in the file that, wrong, silently corrupts every long payload.
 */
export function applyMask(payload: Buffer, mask: Buffer): Buffer {
  const out = Buffer.allocUnsafe(payload.length);
  for (let index = 0; index < payload.length; index += 1) {
    out[index] = payload[index] ^ mask[index % 4];
  }
  return out;
}
