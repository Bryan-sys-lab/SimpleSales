// The live channel, end to end over a real socket.
//
// The codec is unit-tested and the bus is unit-testable, but neither proves the
// thing that matters: that a till can upgrade, that a stream for a shop the
// caller does not run stays silent, and that a socket which fails the handshake
// is refused rather than left hanging. Those only happen over real TCP, so this
// speaks RFC 6455 with a `net` client and no WebSocket library.
//
// The two database reads the channel makes are injected, so this suite needs no
// Postgres — and the injected seams are the same ones the production code uses
// by default, so a stub here proves the gateway, not a variant of it.

import { createHash, createHmac, randomBytes } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import { createConnection, type Socket } from 'node:net';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import type { Express } from 'express';
import { attachLiveChannel, type LiveChannel } from '../routes/live';
import { createLiveEventBus, type LiveEventBus } from '../lib/live';
import { OPCODE_CLOSE, OPCODE_PING, OPCODE_TEXT, applyMask, encodeClose } from '../lib/websocket';

const SECRET = 'live-test-secret-of-at-least-32-bytes-xxxxxxxx';
const SUBJECT = 'kc-subject-1';
const TENANT_A = 'tenant-a';

let app: Express;
let bus: LiveEventBus;
let server: Server;
let channel: LiveChannel;
let port = 0;

/** A masked client frame, exactly as the protocol requires. */
function clientSend(payload: string, opcode = OPCODE_TEXT): Buffer {
  const data = Buffer.from(payload, 'utf8');
  const mask = randomBytes(4);
  const header =
    data.length < 126
      ? Buffer.from([0x80 | opcode, 0x80 | data.length])
      : Buffer.from([0x80 | opcode, 0x80 | 126, data.length >> 8, data.length & 0xff]);
  return Buffer.concat([header, mask, applyMask(data, mask)]);
}

function issueSession(secret: string = SECRET, subject: string = SUBJECT): string {
  const b64 = (value: Buffer | string) =>
    Buffer.from(value as never)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  const claims = {
    sub: subject,
    email: 'owner@example.com',
    email_verified: true,
    token_use: 'app_session',
    iss: 'simplesales-app',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    jti: randomBytes(8).toString('hex'),
  };
  const body = `${b64(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${b64(JSON.stringify(claims))}`;
  return `${body}.${createHmac('sha256', secret).update(body, 'utf8').digest('base64url')}`;
}

type Handshake = { socket: Socket; response: string; key: string };

async function connect(token: string | null): Promise<Handshake> {
  const key = randomBytes(16).toString('base64');
  const socket = createConnection({ port, host: '127.0.0.1' });
  await new Promise<void>((resolve, reject) => {
    socket.once('connect', () => resolve());
    socket.once('error', reject);
  });
  socket.write(
    [
      'GET /live HTTP/1.1',
      `Host: 127.0.0.1:${port}`,
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Key: ${key}`,
      'Sec-WebSocket-Version: 13',
      ...(token ? [`Authorization: Bearer ${token}`] : []),
      '\r\n',
    ].join('\r\n'),
  );
  const response = await new Promise<string>((resolve, reject) => {
    let buffer = '';
    const onData = (chunk: Buffer) => {
      buffer += chunk.toString('utf8');
      if (buffer.includes('\r\n\r\n')) {
        socket.off('data', onData);
        resolve(buffer);
      }
    };
    socket.on('data', onData);
    socket.once('error', reject);
    setTimeout(() => reject(new Error(`handshake timed out: ${JSON.stringify(buffer)}`)), 3000);
  });
  return { socket, response, key };
}

/** Reads the next server text frame as JSON, ignoring control frames. */
function nextMessage(socket: Socket, timeoutMs = 3000): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    let buffer = Buffer.alloc(0);
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`timed out waiting for a message; server sent ${buffer.toString('utf8')}`));
    }, timeoutMs);
    const cleanup = () => {
      clearTimeout(timer);
      socket.off('data', onData);
    };
    const onData = (chunk: Buffer) => {
      buffer = Buffer.concat([buffer, chunk]);
      for (;;) {
        if (buffer.length < 2) return;
        const opcode = buffer[0] & 0x0f;
        const lengthField = buffer[1] & 0x7f;
        let length = lengthField;
        let offset = 2;
        if (lengthField === 126) {
          if (buffer.length < 4) return;
          length = buffer.readUInt16BE(2);
          offset = 4;
        } else if (lengthField === 127) {
          if (buffer.length < 10) return;
          length = buffer.readUInt32BE(6);
          offset = 10;
        }
        if (buffer.length < offset + length) return;
        const payload = buffer.subarray(offset, offset + length);
        buffer = buffer.subarray(offset + length);
        // A heartbeat ping arrives with an empty payload; skip past it.
        if (opcode === OPCODE_PING) continue;
        cleanup();
        resolve(JSON.parse(payload.toString('utf8')) as Record<string, unknown>);
        return;
      }
    };
    socket.on('data', onData);
  });
}

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL = 'postgresql://localhost:5432/duka_pos_test';
  process.env.APP_SESSION_SECRET = SECRET;

  const module = await import('../index');
  app = module.default;
  bus = createLiveEventBus();
  server = createServer(app as unknown as Parameters<typeof createServer>[0]);
  channel = attachLiveChannel(server, {
    bus,
    // No heartbeat, no idle close: a test that must wait for a timer it does
    // not control is a test that fails on a loaded machine.
    pingIntervalMs: 60_000,
    idleTimeoutMs: 600_000,
    shopsFor: async (subject) =>
      subject === SUBJECT ? new Set([TENANT_A]) : new Set<string>(),
    portfolioFor: async () => ({
      shops: [{ tenantId: TENANT_A, shopName: 'Amina Duka', revenue: 4000 }],
      total: { shopCount: 1, revenue: 4000 },
      truncated: false,
    }),
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', () => resolve()));
  const address = server.address();
  port = typeof address === 'object' && address ? address.port : 0;
});

afterEach(() => {
  // A client-side destroy does not reach this environment's loopback quickly
  // enough for a test to observe, so every stream is reaped here by ending it
  // from the server side — the one close this environment does deliver.
  for (let attempt = 0; attempt < 20 && channel.connectionCount() > 0; attempt += 1) {
    channel.close();
  }
});

afterAll(async () => {
  channel.close();
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

describe('the handshake', () => {
  it('refuses a socket with no session rather than opening a stream', async () => {
    const { socket, response } = await connect(null);
    expect(response).toContain('401 Unauthorized');
    expect(response).not.toContain('101 Switching Protocols');
    socket.destroy();
  });

  it('refuses a session signed with the wrong secret', async () => {
    const { socket, response } = await connect(issueSession('not-the-server-secret'));
    expect(response).toContain('401 Unauthorized');
    socket.destroy();
  });

  it('refuses a session signed with no secret configured at all', async () => {
    delete process.env.APP_SESSION_SECRET;
    const { socket, response } = await connect(issueSession());
    process.env.APP_SESSION_SECRET = SECRET;
    expect(response).toContain('401 Unauthorized');
    socket.destroy();
  });

  it('upgrades a session it issued, answering with the RFC accept key', async () => {
    const { socket, response, key } = await connect(issueSession());
    expect(response).toContain('101 Switching Protocols');
    // The worked transform from RFC 6455: the GUID, hashed with the client's
    // key. A server that answers with anything else is refused by every
    // WebSocket client in existence, so this is the handshake's whole job.
    expect(response).toContain(
      `Sec-WebSocket-Accept: ${createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')}`,
    );
    socket.end(encodeClose(1000, ''));
  });

  it('refuses a session whose account holds no shop', async () => {
    const { socket, response } = await connect(issueSession(SECRET, 'a-subject-with-no-shops'));
    expect(response).toContain('401 Unauthorized');
    socket.destroy();
  });

  it('leaves an upgrade it does not own alone', async () => {
    // A health check or another service's upgrade is not refused with a 101;
    // the gateway simply destroys the socket rather than answering for it.
    const socket = createConnection({ port, host: '127.0.0.1' });
    await new Promise<void>((resolve) => socket.once('connect', () => resolve()));
    const closed = new Promise<boolean>((resolve) => {
      socket.once('close', () => resolve(true));
      socket.once('error', () => resolve(true));
    });
    // A WELL-FORMED upgrade request for a path this channel does not own.
    // Without `Connection: Upgrade` Node never raises the upgrade event at all,
    // and the assertion would be testing the HTTP parser rather than the
    // gateway.
    socket.write(
      'GET /not-live HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n',
    );
    expect(await closed).toBe(true);
  });
});

describe('an open stream', () => {
  it('answers a ping with a pong', async () => {
    const { socket } = await connect(issueSession());
    socket.write(clientSend(JSON.stringify({ type: 'ping' })));
    const message = await nextMessage(socket);
    expect(message.type).toBe('pong');
    socket.destroy();
  });

  it('answers a read with the same figures the HTTP endpoint serves', async () => {
    const { socket } = await connect(issueSession());
    socket.write(clientSend(JSON.stringify({ type: 'read', reasons: ['sales'] })));
    const message = await nextMessage(socket);
    expect(message.type).toBe('snapshot');
    expect(message.reasons).toEqual(['sales']);
    expect(message.shops).toEqual([
      { tenantId: TENANT_A, shopName: 'Amina Duka', revenue: 4000 },
    ]);
    expect(message.total).toEqual({ shopCount: 1, revenue: 4000 });
    socket.destroy();
  });

  it('carries no business data itself: an event is a reason to re-read', async () => {
    const { socket } = await connect(issueSession());
    bus.emit({ tenantIds: [TENANT_A], reason: 'sales' });
    const message = await nextMessage(socket);
    expect(message).toMatchObject({ type: 'stale', reasons: ['sales'] });
    // The reason only. A signal that carried figures would be a second copy of
    // the ledger to keep honest.
    expect(message).not.toHaveProperty('shops');
    socket.destroy();
  });

  it('says nothing about a shop the caller does not run', async () => {
    const { socket } = await connect(issueSession());
    bus.emit({ tenantIds: ['somebody-elses-tenant'], reason: 'sales' });
    await expect(nextMessage(socket, 300)).rejects.toThrow(/timed out/);
    socket.destroy();
  });

  it('answers a close with a close', async () => {
    const { socket } = await connect(issueSession());
    const answered = new Promise<boolean>((resolve) => {
      socket.once('data', (chunk: Buffer) => {
        // The server's own close frame, echoed back before it hangs up.
        resolve((chunk[0] & 0x0f) === OPCODE_CLOSE);
      });
    });
    socket.write(encodeClose(1000, 'done'));
    expect(await answered).toBe(true);
    socket.destroy();
  });

  it('stops counting a stream the till closed', async () => {
    // A close FRAME rather than a destroyed socket. Both end the connection in
    // production, but this environment does not deliver a client's FIN to the
    // server's side of a loopback connection within a test's lifetime, and an
    // assertion that depends on that is asserting the sandbox. The frame is
    // written, delivered, and answered — which is the part this test is about.
    const before = channel.connectionCount();
    const connected = await connect(issueSession());
    const socket = connected.socket;
    expect(channel.connectionCount()).toBe(before + 1);

    socket.write(encodeClose(1000, 'closing'));
    for (let attempt = 0; attempt < 40 && channel.connectionCount() > before; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    expect(channel.connectionCount()).toBe(before);

    // And the signal it used to carry no longer reaches it: the stream is as
    // gone as its number says it is.
    bus.emit({ tenantIds: [TENANT_A], reason: 'sales' });
    await expect(nextMessage(socket, 200)).rejects.toThrow(/timed out/);
    socket.destroy();
  });

  it('rejects a frame the client did not mask', async () => {
    // The protocol is unambiguous: a client that does not mask is not a client.
    // The connection is closed rather than served.
    const { socket } = await connect(issueSession());
    socket.write(Buffer.from([0x81, 0x03, 0x61, 0x62, 0x63]));
    const closed = new Promise<boolean>((resolve) => {
      socket.once('close', () => resolve(true));
      socket.once('data', () => resolve(true));
      setTimeout(() => resolve(false), 1000);
    });
    expect(await closed).toBe(true);
    socket.destroy();
  });
});
