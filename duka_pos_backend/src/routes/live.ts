// The live channel: one WebSocket per till, carrying "go and read again".
//
// WHAT STREAMS AND WHAT DOES NOT
// The channel carries no business data — see lib/live.ts. It carries a signal,
// and the client answers it by reading `/tenant/portfolio`, which is where the
// figures live and where the ownership rules are enforced once. That keeps one
// security surface: a WebSocket that leaked a stray fact would be a leak the
// HTTP route does not have.
//
// WHO MAY CONNECT
// Only a till holding a session this server minted — the app session from
// `/auth/verify`. A Keycloak token is not accepted here yet, because the
// channel's audience is the till; the check is in one place, so widening it is
// a single change rather than a scattered one.
//
// WHAT IT IS NOT
// It is not the transport for the ledger. A dropped connection loses nothing:
// the next connect re-reads.

import type http from 'node:http';
import type { Duplex } from 'node:stream';
import { IncomingMessage } from 'node:http';
import { concerns, createLiveEventBus, liveBus, type LiveEventBus } from '../lib/live.js';
import {
  OPCODE_CLOSE,
  OPCODE_PING,
  OPCODE_TEXT,
  acceptKeyFor,
  decodeFrame,
  drainFrames,
  encodeClose,
  encodeFrame,
} from '../lib/websocket.js';
import { verifyKeycloakToken, type KeycloakClaims } from '../lib/keycloak_token.js';
import { prisma } from '../lib/prisma.js';
import { log } from '../lib/observability.js';
import { readPortfolio } from '../lib/portfolio_query.js';

export const LIVE_PATH = '/live';

/** The heartbeat. A till on a phone drops off the network constantly, and a
 * dead socket that still looks connected is how a shop ends up watching a
 * number that stopped updating hours ago. */
const PING_INTERVAL_MS = 30_000;

/** A connection that has not spoken in ten minutes is closed rather than
 * counted as streaming. */
const IDLE_TIMEOUT_MS = 10 * 60_000;

type Connection = {
  socket: Duplex;
  /** Every active profile the caller's account holds — the same shop set
   * `/tenant/portfolio` returns. */
  tenantIds: Set<string>;
  subject: string;
  lastSeen: Date;
  pingTimer: NodeJS.Timeout;
  idleTimer: NodeJS.Timeout;
};

export type LiveChannel = {
  bus: LiveEventBus;
  /** Open streams. Asserted in tests, and useful in a log line when a channel
   * that should be alive is not. */
  connectionCount(): number;
  close(): void;
};

export type LiveChannelOptions = {
  /** Injected so a test can drive the bus directly. */
  bus?: LiveEventBus;
  /** Injected so a test does not wait. */
  pingIntervalMs?: number;
  idleTimeoutMs?: number;
  /**
   * Where a session's shops come from. Defaults to the profile query; injected
   * by the route test, which has no database and therefore no other way to
   * reach the handshake at all.
   */
  shopsFor?: (subject: string) => Promise<Set<string>>;
  /**
   * Where a snapshot comes from. Defaults to the shared portfolio read, so the
   * stream and `/tenant/portfolio` cannot disagree about a shop's figures.
   */
  portfolioFor?: (subject: string) => Promise<{ shops: unknown[]; total: unknown; truncated: boolean }>;
  /**
   * How a token on the upgrade is checked.
   *
   * Injectable so a test can prove the channel's RULES — who may hold a
   * stream open, what a rejected upgrade looks like — without standing up a
   * JWKS endpoint. Production uses the Keycloak verifier.
   */
  verifyToken?: (token: string) => Promise<KeycloakClaims | null>;
};

/**
 * Attaches the live channel to an HTTP server.
 *
 * Returns the bus, so a route can `emit` after its write without importing a
 * module-level singleton it cannot replace in a test.
 */
export function attachLiveChannel(server: http.Server, options: LiveChannelOptions = {}): LiveChannel {
  const bus = options.bus ?? liveBus;
  const pingIntervalMs = options.pingIntervalMs ?? PING_INTERVAL_MS;
  const idleTimeoutMs = options.idleTimeoutMs ?? IDLE_TIMEOUT_MS;
  const shopsFor = options.shopsFor ?? readShops;
  const portfolioFor = options.portfolioFor ?? readPortfolioFor;
  const verifyToken = options.verifyToken ?? ((token: string) =>
    verifyKeycloakToken(token, {
      issuer: (process.env.OIDC_ISSUER_URL ?? '').replace(/\/$/, ''),
      audience: process.env.OIDC_AUDIENCE ?? '',
      jwksUri:
        process.env.OIDC_JWKS_URI ??
        `${(process.env.OIDC_ISSUER_URL ?? '').replace(/\/$/, '')}/protocol/openid-connect/certs`,
    }));
  const connections = new Set<Connection>();

  function send(connection: Connection, message: Record<string, unknown>) {
    if (!connection.socket.writable) return;
    connection.socket.write(encodeFrame(JSON.stringify(message), OPCODE_TEXT));
  }

  function stop(connection: Connection) {
    clearInterval(connection.pingTimer);
    clearInterval(connection.idleTimer);
    connections.delete(connection);
  }

  server.on('upgrade', (req: IncomingMessage, socket: Duplex) => {
    void handleUpgrade(req, socket).catch((error: unknown) => {
      log('error', 'live.upgrade_failed', { message: error instanceof Error ? error.message : 'unknown' });
      try {
        socket.end('HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n');
      } catch {
        // The socket is already gone; there is nothing left to refuse.
      }
      socket.destroy();
    });
  });

  async function handleUpgrade(req: IncomingMessage, socket: Duplex) {
    const url = req.url ?? '';
    if (!url.startsWith(LIVE_PATH)) {
      // Not ours. A proxy's health check or another service's upgrade is left
      // alone rather than refused by us.
      socket.destroy();
      return;
    }

    const requestId = req.headers['x-request-id'] as string | undefined;
    const authHeader = req.headers.authorization;
    const token =
      typeof authHeader === 'string' && authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
    // The one credential: a Keycloak access token, checked against the
    // identity server's own signing keys.
    const claims = await verifyToken(token);
    if (!claims) {
      log('warn', 'live.rejected_no_session', { requestId });
      // An HTTP response, not a bare close frame: the handshake never happened,
      // and a close frame sent before a 101 is a frame the client has no
      // reason to parse.
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      return;
    }

    // The shops this account holds, read at connect time rather than trusted
    // from the token: a session outlives a shop being added, and a stream
    // subscribed to a shop the caller no longer runs is a channel nobody
    // should hold open.
    let tenantIds: Set<string>;
    try {
      tenantIds = await shopsFor(claims.sub);
    } catch (error) {
      log('error', 'live.shops_failed', { requestId, message: error instanceof Error ? error.message : 'unknown' });
      socket.end('HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n');
      return;
    }
    if (tenantIds.size === 0) {
      log('warn', 'live.rejected_no_shops', { requestId, profile: claims.email });
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      return;
    }

    const upgrade = req.headers.upgrade;
    const key = req.headers['sec-websocket-key'];
    if (typeof upgrade !== 'string' || upgrade.toLowerCase() !== 'websocket' || typeof key !== 'string' || !key) {
      socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
      return;
    }

    socket.write(
      [
        'HTTP/1.1 101 Switching Protocols',
        'Upgrade: websocket',
        'Connection: Upgrade',
        `Sec-WebSocket-Accept: ${acceptKeyFor(key)}`,
        '\r\n',
      ].join('\r\n'),
    );

    const now = new Date();
    const connection: Connection = {
      socket,
      tenantIds,
      subject: claims.sub,
      lastSeen: now,
      pingTimer: setInterval(() => {
        if (connections.has(connection)) socket.write(encodeFrame('', OPCODE_PING));
      }, pingIntervalMs),
      idleTimer: setInterval(() => {
        if (!connections.has(connection)) return;
        if (Date.now() - connection.lastSeen.getTime() <= idleTimeoutMs) return;
        log('warn', 'live.idle_closed', { shops: connection.tenantIds.size });
        socket.end(encodeClose(1000, 'idle'));
      }, Math.max(pingIntervalMs, Math.floor(idleTimeoutMs / 2))),
    };
    // `unref` so a heartbeat never holds the process open on its own.
    connection.pingTimer.unref?.();
    connection.idleTimer.unref?.();
    connections.add(connection);

    const unsubscribe = bus.subscribe((event) => {
      if (!concerns(event, connection.tenantIds)) return;
      send(connection, { type: 'stale', reasons: [event.reason], at: event.at });
    });

    log('info', 'live.connected', { requestId, shops: connection.tenantIds.size });

    // Typed, not inferred: a subarray of a socket chunk is an ArrayBufferLike,
    // and inferring the narrower ArrayBuffer from `Buffer.alloc` makes the
    // accumulator's type disagree with the parser's.
    let buffer: Buffer = Buffer.alloc(0);
    socket.on('data', (chunk: Buffer) => {
      buffer = Buffer.concat([buffer, chunk]);
      const { frames, rest, invalid } = drainFrames(buffer);
      buffer = rest;
      if (invalid) {
        // 1002 is a protocol error. Leaving the socket open while holding an
        // unparseable frame would leave it waiting for bytes that can never
        // complete it, which is how a stream looks alive and is not.
        log('warn', 'live.protocol_error', { requestId, reason: invalid });
        socket.end(encodeClose(1002, 'protocol error'));
        return;
      }
      for (const frame of frames) {
        handleFrame(connection, frame.opcode, frame.payload);
      }
    });

    socket.on('close', () => {
      unsubscribe();
      stop(connection);
      log('info', 'live.disconnected', { shops: connection.tenantIds.size });
    });

    socket.on('error', () => {
      // A till on mobile data errors constantly. The close handler does the
      // cleanup; this only stops the error surfacing as an unhandled one.
    });
  }

  function handleFrame(connection: Connection, opcode: number, payload: Buffer) {
    connection.lastSeen = new Date();

    if (opcode === OPCODE_CLOSE) {
      connection.socket.end(encodeClose(1000, ''));
      return;
    }
    if (opcode === OPCODE_PING) {
      connection.socket.write(encodeFrame(payload, 0xa));
      return;
    }
    if (opcode !== OPCODE_TEXT) return;

    let message: unknown;
    try {
      message = JSON.parse(payload.toString('utf8'));
    } catch {
      send(connection, { type: 'error', error: 'MALFORMED_MESSAGE' });
      return;
    }

    const type = (message as { type?: unknown }).type;
    if (type === 'ping') {
      send(connection, { type: 'pong', at: new Date().toISOString() });
      return;
    }
    if (type === 'read') {
      // The one message that matters. The reply comes from the same read the
      // HTTP endpoint uses, so a stream and a pull-to-refresh can never
      // disagree about a shop's figures.
      void sendSnapshot(connection, (message as { reasons?: unknown }).reasons);
      return;
    }
    send(connection, { type: 'error', error: 'UNKNOWN_MESSAGE' });
  }

  async function sendSnapshot(connection: Connection, reasons: unknown) {
    try {
      const reading = await portfolioFor(connection.subject);
      send(connection, {
        type: 'snapshot',
        at: new Date().toISOString(),
        reasons: normaliseReasons(reasons),
        shops: reading.shops,
        total: reading.total,
        truncated: reading.truncated,
      });
    } catch (error) {
      log('error', 'live.snapshot_failed', { message: error instanceof Error ? error.message : 'unknown' });
      send(connection, { type: 'error', error: 'SNAPSHOT_FAILED' });
    }
  }

  return {
    bus,
    connectionCount() {
        return connections.size;
    },
    close() {
      for (const connection of [...connections]) {
        clearInterval(connection.pingTimer);
        clearInterval(connection.idleTimer);
        connection.socket.end(encodeClose(1001, 'server going away'));
      }
      connections.clear();
    },
  };
}

/** The default shop lookup: the same profiles the portfolio endpoint reads. */
async function readShops(subject: string): Promise<Set<string>> {
  const profiles = await prisma.profile.findMany({
    where: { oidcSubject: subject, active: true, deletedAt: null },
    select: { tenantId: true },
  });
  return new Set(profiles.map((profile) => profile.tenantId));
}

/** The default snapshot: the shared portfolio read, over a 30-day window. */
async function readPortfolioFor(subject: string) {
  return readPortfolio(subject, {
    from: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
    to: new Date(),
  });
}

function normaliseReasons(reasons: unknown): string[] {
  if (!Array.isArray(reasons)) return [];
  return reasons.filter((reason): reason is string => typeof reason === 'string');
}
