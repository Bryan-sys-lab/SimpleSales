import { IncomingMessage, ServerResponse } from 'node:http';
import { Duplex } from 'node:stream';
import app from './index.js';

function makeSocket(): Duplex {
  const socket = new Duplex({
    read() {},
    write(chunk, enc, cb) { cb(); },
  });
  (socket as any).remoteAddress = '127.0.0.1';
  return socket;
}

export default {
  async fetch(request: Request, env: any, _ctx: any): Promise<Response> {
    for (const [k, v] of Object.entries(env || {})) {
      if (typeof v === 'string') process.env[k] = v;
    }

    const url = new URL(request.url);
    if (url.pathname === '/live' || url.pathname === '/api/live') {
      const id = env.LIVE_ROOM.idFromName('default');
      const stub = env.LIVE_ROOM.get(id);
      return stub.fetch(request);
    }

    // Read body up front (Workers-friendly) to avoid stream timing issues.
    let bodyText = '';
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      try {
        bodyText = await request.text();
      } catch (e) {
        console.error('body read error', e);
      }
    }

    const socket = makeSocket();

    return new Promise<Response>((resolve) => {
      const timer = setTimeout(() => resolve(new Response('gateway timeout', { status: 504 })), 10000);

      const req = new IncomingMessage(socket as any);
      req.method = request.method;
      req.url = url.pathname + url.search;
      req.headers = Object.fromEntries(request.headers.entries());

      const res = new ServerResponse(req);
      Object.defineProperty(req, 'socket', { value: socket, writable: true });
      Object.defineProperty(req, 'connection', { value: socket, writable: true });

      const chunks: Buffer[] = [];
      const origWrite = res.write.bind(res);
      const origEnd = res.end.bind(res);
      res.write = (chunk: any, ...args: any[]) => {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        return origWrite(chunk, ...args);
      };
      res.end = (chunk: any, ...args: any[]) => {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        const body = Buffer.concat(chunks);
        const headers = new Headers();
        for (const [k, v] of Object.entries(res.getHeaders())) {
          if (v !== undefined) headers.set(k, String(v));
        }
        clearTimeout(timer);
        resolve(new Response(body, { status: res.statusCode, headers }));
        return origEnd(chunk, ...args);
      };

      app(req as any, res as any);

      if (bodyText) req.push(Buffer.from(bodyText));
      req.push(null);
    });
  },
};


// Durable Object backing the /live WebSocket channel.
export class LiveRoom {
  private sessions: Set<any> = new Set();

  constructor(_state: any, _env: any) {}

  async fetch(request: any): Promise<Response> {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected websocket', { status: 426 });
    }
    const pair: any = new (globalThis as any).WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();
    this.sessions.add(server);
    server.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
    server.addEventListener('close', () => this.sessions.delete(server));
    server.addEventListener('message', (ev: any) => {
      for (const s of this.sessions) {
        if (s.readyState === 1) s.send(ev.data);
      }
    });
    return new Response(null, { status: 101, webSocket: client } as any);
  }

  async broadcast(message: string) {
    for (const s of this.sessions) {
      if (s.readyState === 1) s.send(message);
    }
  }
}
