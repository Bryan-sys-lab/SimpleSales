import { describe, expect, it } from 'vitest';
import {
  OPCODE_CLOSE,
  OPCODE_TEXT,
  applyMask,
  decodeFrame,
  drainFrames,
  encodeClose,
  encodeFrame,
  handshakeResponse,
} from '../lib/websocket.js';

/** Builds a client frame the way a client must: masked, and with the
 * extended length form once the payload outgrows a byte. */
function clientFrame(payload: string, mask = Buffer.from([1, 2, 3, 4])): Buffer {
  const data = Buffer.from(payload, 'utf8');
  const header =
    data.length < 126
      ? Buffer.from([0x81, 0x80 | data.length])
      : Buffer.from([0x81, 0x80 | 126, data.length >> 8, data.length & 0xff]);
  return Buffer.concat([header, mask, applyMask(data, mask)]);
}

describe('the handshake', () => {
  it('answers with the RFC-specified accept key', () => {
    // The worked example from RFC 6455 section 1.3: any other value would be
    // rejected by every WebSocket client in existence.
    const response = handshakeResponse('dGhlIHNhbXBsZSBub25jZQ==');
    expect(response).toContain('HTTP/1.1 101 Switching Protocols');
    expect(response).toContain('Upgrade: websocket');
    expect(response).toContain('Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=');
  });

  it('is a complete response, in the right order', () => {
    const response = handshakeResponse('dGhlIHNhbXBsZSBub25jZQ==');
    // Four headers, then the blank line that ends them. Splitting on CRLF
    // leaves two empty trailing elements, because the response ends with a
    // CRLF of its own.
    const lines = response.split('\r\n');
    expect(lines).toHaveLength(6);
    expect(lines[0]).toBe('HTTP/1.1 101 Switching Protocols');
    expect(lines[1]).toBe('Upgrade: websocket');
    expect(lines[2]).toBe('Connection: Upgrade');
    expect(lines[3]).toBe('Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=');
    // The blank line that closes the header block, so a client stops reading.
    expect(response.endsWith('\r\n\r\n')).toBe(true);
  });
});

describe('server frames', () => {
  it('are unmasked and carry their payload', () => {
    const frame = encodeFrame('hello');
    // Bytes, not text: a header read as UTF-8 decodes its opcode byte into a
    // replacement character and proves nothing.
    expect(frame.subarray(0, 2)).toEqual(Buffer.from([0x81, 0x05]));
    expect(frame.subarray(2).toString('utf8')).toBe('hello');
    expect(frame[1] & 0x80).toBe(0);
  });

  it('use the 126 form for a 200-byte payload', () => {
    const frame = encodeFrame(Buffer.alloc(200, 0x61));
    expect(frame[1]).toBe(126);
    expect(frame.readUInt16BE(2)).toBe(200);
    expect(frame).toHaveLength(4 + 200);
  });

  it('use the 127 form for a 70,000-byte payload', () => {
    const frame = encodeFrame(Buffer.alloc(70000, 0x61));
    expect(frame[1]).toBe(127);
    expect(frame.readUInt32BE(6)).toBe(70000);
    expect(frame).toHaveLength(10 + 70000);
  });

  it('encode a close with a code and a reason', () => {
    const frame = encodeClose(1008, 'no token');
    expect(frame[0]).toBe(0x88);
    expect(frame.readUInt16BE(2)).toBe(1008);
    expect(frame.subarray(4).toString('utf8')).toBe('no token');
  });

  it('round-trip a masked frame, which is the only direction we decode', () => {
    // `decodeFrame` is the CLIENT side: the frame has to be masked for it to
    // be legal, so the round trip goes through the mask rather than through
    // `encodeFrame`.
    const payload = 'round trip';
    const frame = clientFrame(payload);
    const decoded = decodeFrame(frame);
    expect(decoded.kind).toBe('frame');
    if (decoded.kind !== 'frame') return;
    expect(decoded.payload.toString('utf8')).toBe(payload);
    expect(decoded.opcode).toBe(OPCODE_TEXT);
    expect(decoded.fin).toBe(true);
    // Nothing left over, so the socket has no second frame waiting.
    expect(decoded.bytesConsumed).toBe(frame.length);
  });
});

describe('client frames', () => {
  it('unmask the payload', () => {
    const decoded = decodeFrame(clientFrame('{"type":"ping"}'));
    expect(decoded.kind).toBe('frame');
    if (decoded.kind !== 'frame') return;
    expect(JSON.parse(decoded.payload.toString('utf8'))).toEqual({ type: 'ping' });
  });

  it('unmask a payload longer than the mask, where the rolling index matters',
      () => {
    const body = 'x'.repeat(500);
    const decoded = decodeFrame(clientFrame(body));
    expect(decoded.kind).toBe('frame');
    if (decoded.kind !== 'frame') return;
    expect(decoded.payload.toString('utf8')).toBe(body);
    expect(decoded.payload).toHaveLength(500);
  });

  it('reject an unmasked frame, because the client is the one that must mask', () => {
    const unmasked = Buffer.from([0x81, 0x05, 0x68, 0x69]); // "hi", not masked
    const decoded = decodeFrame(Buffer.concat([unmasked, Buffer.from('there')]));
    expect(decoded.kind).toBe('invalid');
    if (decoded.kind !== 'invalid') return;
    expect(decoded.reason).toBe('CLIENT_FRAMES_MUST_BE_MASKED');
  });

  it('reject a control frame carrying a full frame of payload', () => {
    const mask = Buffer.from([0, 0, 0, 0]);
    const data = Buffer.alloc(200, 0x61);
    const forged = Buffer.from([0x88, 0x80 | 126, data.length >> 8, data.length & 0xff]);
    const decoded = decodeFrame(Buffer.concat([forged, mask, data]));
    expect(decoded.kind).toBe('invalid');
    if (decoded.kind !== 'invalid') return;
    expect(decoded.reason).toBe('CONTROL_FRAME_TOO_LARGE');
  });

  it('reject a frame that claims 2^32 bytes', () => {
    const decoded = decodeFrame(Buffer.from([0x81, 127, 0, 0, 0, 1, 0, 0, 0, 0]));
    expect(decoded.kind).toBe('invalid');
    if (decoded.kind !== 'invalid') return;
    expect(decoded.reason).toBe('FRAME_TOO_LARGE');
  });
});

describe('partial reads', () => {
  it('report incomplete rather than throwing on a short header', () => {
    expect(decodeFrame(Buffer.from([0x81])).kind).toBe('incomplete');
  });

  it('report incomplete on a short extended length', () => {
    expect(decodeFrame(Buffer.from([0x81, 126, 0])).kind).toBe('incomplete');
  });

  it('report incomplete on a short mask', () => {
    expect(decodeFrame(Buffer.from([0x81, 0x84, 1, 2])).kind).toBe('incomplete');
  });

  it('report incomplete on a short payload, and succeed once the rest arrives', () => {
    const half = clientFrame('half of a message').subarray(0, 8);
    expect(decodeFrame(half).kind).toBe('incomplete');
    const whole = clientFrame('half of a message');
    expect(decodeFrame(whole).kind).toBe('frame');
  });

  it('keep the leftover rather than dropping half a frame', () => {
    const buffer = Buffer.concat([clientFrame('first'), clientFrame('second')]);
    const { frames, rest } = drainFrames(buffer);
    expect(frames).toHaveLength(2);
    expect(frames[0].payload.toString('utf8')).toBe('first');
    expect(frames[1].payload.toString('utf8')).toBe('second');
    expect(rest).toHaveLength(0);

    const split = Buffer.concat([clientFrame('first'), clientFrame('second').subarray(0, 3)]);
    const partial = drainFrames(split);
    expect(partial.frames).toHaveLength(1);
    expect(partial.rest).toHaveLength(3);
  });
});

describe('masking arithmetic', () => {
  it('is its own inverse', () => {
    const mask = Buffer.from([9, 8, 7, 6]);
    const original = Buffer.from('abcdefgh', 'utf8'); // longer than the mask
    const masked = applyMask(original, mask);
    expect(applyMask(masked, mask).toString('utf8')).toBe('abcdefgh');
    expect(masked.equals(original)).toBe(false);
  });
});
