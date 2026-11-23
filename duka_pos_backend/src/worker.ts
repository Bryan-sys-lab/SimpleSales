import { DurableObject } from "cloudflare:workers";
import { IncomingMessage, ServerResponse } from "node:http";
import { Duplex } from "node:stream";
import app from "./index.js";
import { verifyAccessToken } from "./lib/jwt.js";
import { setCloudflareEmailBinding } from "./lib/email_sender.js";
import { setD1DatabaseBinding } from "./lib/prisma.js";
import type { BackupStorage, ProfileImageStorage } from "./lib/r2.js";
import { withAdminLivePublisher } from "./services/admin_live_broker.js";
import {
  consumeAdminLiveTicket,
  registerAdminLiveTicket,
} from "./services/admin_ws_ticket_store.js";

function makeSocket(): Duplex {
  const socket = new Duplex({
    read() {},
    write(chunk, enc, cb) {
      cb();
    },
  });
  (socket as any).remoteAddress = "127.0.0.1";
  return socket;
}

export default {
  async fetch(request: Request, env: any, _ctx: any): Promise<Response> {
    setD1DatabaseBinding(env?.DB);
    setCloudflareEmailBinding(
      env?.EMAIL && typeof env.EMAIL.send === "function" ? env.EMAIL : null,
    );
    const adminLive = () => env.ADMIN_LIVE.get(env.ADMIN_LIVE.idFromName("admin"));
    for (const [k, v] of Object.entries(env || {})) {
      if (typeof v === "string") process.env[k] = v;
    }

    const url = new URL(request.url);
    if (url.pathname === "/api/admin/live") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return new Response("Expected websocket", { status: 426 });
      }
      if (request.headers.get("Origin") !== env?.ADMIN_APP_ORIGIN) {
        return new Response("Invalid origin", { status: 403 });
      }
      return adminLive().fetch(request);
    }
    if (url.pathname === "/live" || url.pathname === "/api/live") {
      const token = request.headers
        .get("authorization")
        ?.match(/^Bearer\s+(.+)$/i)?.[1]
        ?.trim();
      const tenantId = request.headers.get("x-tenant-id")?.trim();
      if (
        request.headers.get("Upgrade")?.toLowerCase() !== "websocket" ||
        !token ||
        !tenantId ||
        !verifyAccessToken(token)
      ) {
        return new Response("Authentication required", { status: 401 });
      }
      // One room per tenant prevents a till in shop A from receiving shop B's
      // change signals. The HTTP API remains the source of truth and the
      // socket carries signals only.
      const id = env.LIVE_ROOM.idFromName(`tenant:${tenantId}`);
      const stub = env.LIVE_ROOM.get(id);
      return stub.fetch(request);
    }

    // Read body up front (Workers-friendly) to avoid stream timing issues.
    let bodyText = "";
    if (request.method !== "GET" && request.method !== "HEAD") {
      try {
        bodyText = await request.text();
      } catch (e) {
        console.error("body read error", e);
      }
    }

    const socket = makeSocket();

    const response = await new Promise<Response>((resolve) => {
      const timer = setTimeout(
        () => resolve(new Response("gateway timeout", { status: 504 })),
        28000,
      );

      const req = new IncomingMessage(socket as any) as IncomingMessage & {
        backupStorage?: BackupStorage;
        profileImageStorage?: ProfileImageStorage;
      };
      req.backupStorage = env?.BACKUP_BUCKET;
      req.profileImageStorage = env?.PROFILE_IMAGE_BUCKET;
      req.method = request.method;
      req.url = url.pathname + url.search;
      req.headers = Object.fromEntries(request.headers.entries());

      const res = new ServerResponse(req);
      Object.defineProperty(req, "socket", { value: socket, writable: true });
      Object.defineProperty(req, "connection", {
        value: socket,
        writable: true,
      });

      const chunks: Buffer[] = [];
      const origWrite = res.write.bind(res);
      const origEnd = res.end.bind(res);
      res.write = (chunk: any, ...args: any[]) => {
        if (chunk)
          chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        return origWrite(chunk, ...args);
      };
      res.end = (chunk: any, ...args: any[]) => {
        if (chunk)
          chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        const body = Buffer.concat(chunks);
        const headers = new Headers();
        for (const [k, v] of Object.entries(res.getHeaders())) {
          if (v !== undefined) headers.set(k, String(v));
        }
        clearTimeout(timer);
        resolve(new Response(body, { status: res.statusCode, headers }));
        return origEnd(chunk, ...args);
      };

      withAdminLivePublisher(async (message) => {
        const published = await adminLive().fetch(
          new Request("https://admin-live.internal/broadcast", {
            method: "POST",
            headers: { "x-admin-live-internal": "1" },
            body: message,
          }),
        );
        if (!published.ok) throw new Error(`Admin live broadcast returned ${published.status}`);
      }, () => app(req as any, res as any));

      if (bodyText) req.push(Buffer.from(bodyText));
      req.push(null);
    });
    if (
      url.pathname === "/api/admin/auth/ws-ticket" &&
      request.method === "POST" &&
      response.ok
    ) {
      let payload: { ticket?: unknown; expiresIn?: unknown };
      try {
        payload = await response.clone().json() as { ticket?: unknown; expiresIn?: unknown };
      } catch {
        return Response.json({ error: "Admin live ticket response was invalid" }, { status: 502 });
      }
      if (typeof payload.ticket !== "string") {
        return Response.json({ error: "Admin live ticket was missing" }, { status: 502 });
      }
      let registered: Response;
      try {
        registered = await adminLive().fetch(
          new Request("https://admin-live.internal/ticket", {
            method: "POST",
            headers: { "x-admin-live-internal": "1", "content-type": "application/json" },
            body: JSON.stringify(payload),
          }),
        );
      } catch (error) {
        console.error("admin live ticket registration failed", error);
        return Response.json({ error: "Admin live service is unavailable" }, { status: 503 });
      }
      if (!registered.ok) {
        return Response.json({ error: "Admin live ticket could not be registered" }, { status: 503 });
      }
    }
    if (
      request.method !== "GET" &&
      request.method !== "HEAD" &&
      response.status >= 200 &&
      response.status < 300
    ) {
      const tenantId = request.headers.get("x-tenant-id")?.trim();
      if (tenantId && url.pathname.startsWith("/api/")) {
        const id = env.LIVE_ROOM.idFromName(`tenant:${tenantId}`);
        const stub = env.LIVE_ROOM.get(id);
        await stub.fetch(
          new Request("https://live.internal/broadcast", {
            method: "POST",
            headers: { "x-live-internal": "1" },
            body: JSON.stringify({
              type: "snapshot",
              reasons: [],
              at: new Date().toISOString(),
            }),
          }),
        );
      }
    }
    return response;
  },
  async scheduled(event: any, env: any, _ctx: any) {
    setD1DatabaseBinding(env?.DB);
    for (const [k, v] of Object.entries(env || {})) {
      if (typeof v === "string") process.env[k] = v;
    }
    try {
      const { prisma } = await import("./lib/prisma.js");
      await prisma.user.count();
      console.log("db warm ping ok");
    } catch (e) {
      console.error("db warm ping failed", e);
    }
  },
};

// Durable Object backing the /live WebSocket channel.
export class LiveRoom extends DurableObject {
  private sessions: Set<any> = new Set();

  async fetch(request: Request): Promise<Response> {
    if (
      request.headers.get("x-live-internal") === "1" &&
      request.method === "POST"
    ) {
      const message = await request.text();
      for (const s of this.sessions) {
        if (s.readyState === 1) s.send(message);
      }
      return new Response(null, { status: 204 });
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected websocket", { status: 426 });
    }
    const pair: any = new (globalThis as any).WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    server.accept();
    this.sessions.add(server);
    server.send(
      JSON.stringify({ type: "connected", at: new Date().toISOString() }),
    );
    server.addEventListener("close", () => this.sessions.delete(server));
    server.addEventListener("message", (ev: any) => {
      try {
        const message = JSON.parse(String(ev.data));
        if (message?.type === "read" && server.readyState === 1) {
          server.send(
            JSON.stringify({
              type: "snapshot",
              reasons: [],
              at: new Date().toISOString(),
            }),
          );
        }
      } catch {
        // Ignore malformed optional signal frames.
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

export class AdminLiveHub extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (
      request.headers.get("x-admin-live-internal") === "1" &&
      request.method === "POST" &&
      url.pathname === "/broadcast"
    ) {
      const message = await request.text();
      for (const socket of this.ctx.getWebSockets()) {
        if (socket.readyState === WebSocket.OPEN) socket.send(message);
      }
      return new Response(null, { status: 204 });
    }
    if (
      request.headers.get("x-admin-live-internal") === "1" &&
      request.method === "POST" &&
      url.pathname === "/ticket"
    ) {
      const payload = await request.json() as { ticket?: unknown; expiresIn?: unknown };
      if (
        typeof payload.ticket !== "string" ||
        !/^[A-Za-z0-9_-]{43}$/.test(payload.ticket) ||
        typeof payload.expiresIn !== "number" ||
        !Number.isInteger(payload.expiresIn) ||
        payload.expiresIn < 1 ||
        payload.expiresIn > 60
      ) {
        return new Response("Invalid ticket", { status: 400 });
      }
      const registered = await registerAdminLiveTicket(
        this.ctx.storage,
        payload.ticket,
        payload.expiresIn,
      );
      if (!registered) return new Response("Invalid ticket", { status: 400 });
      return new Response(null, { status: 204 });
    }
    if (
      (url.pathname !== "/api/admin/live" && url.pathname !== "/live") ||
      request.headers.get("Upgrade")?.toLowerCase() !== "websocket"
    ) {
      return new Response("Expected websocket", { status: 426 });
    }
    const ticket = url.searchParams.get("ticket");
    if (!ticket || !/^[A-Za-z0-9_-]{43}$/.test(ticket)) {
      return new Response("Invalid or expired ticket", { status: 401 });
    }
    const valid = await consumeAdminLiveTicket(this.ctx.storage, ticket);
    if (!valid) return new Response("Invalid or expired ticket", { status: 401 });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server);
    server.send(JSON.stringify({ type: "connected", at: new Date().toISOString() }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    try {
      const payload = JSON.parse(message) as { type?: unknown };
      if (payload.type === "ping") socket.send(JSON.stringify({ type: "pong" }));
    } catch {
      // Ignore malformed optional signal frames.
    }
  }

  async webSocketClose(socket: WebSocket, code: number, reason: string): Promise<void> {
    if (code >= 1000 && code < 5000 && ![1004, 1005, 1006, 1015].includes(code)) {
      socket.close(code, reason);
    } else {
      socket.close();
    }
  }

}
