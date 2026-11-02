import { createServer, IncomingMessage, ServerResponse } from 'node:http';
import app from './index.js';

const server = createServer(app);

export default {
  async fetch(request: Request, env: any, ctx: any): Promise<Response> {
    for (const [k, v] of Object.entries(env || {})) {
      if (typeof v === 'string') process.env[k] = v;
    }

    const url = new URL(request.url);

    return new Promise<Response>((resolve) => {
      const req = new IncomingMessage(null as any);
      req.method = request.method;
      req.url = url.pathname + url.search;
      req.headers = Object.fromEntries(request.headers.entries());

      const res = new ServerResponse(req);
      const chunks: Buffer[] = [];
      const originalWrite = res.write.bind(res);
      const originalEnd = res.end.bind(res);
      res.write = (chunk: any, ...args: any[]) => {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        return originalWrite(chunk, ...args);
      };
      res.end = (chunk: any, ...args: any[]) => {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        const body = Buffer.concat(chunks);
        const headers = new Headers();
        for (const [k, v] of Object.entries(res.getHeaders())) {
          if (v !== undefined) headers.set(k, String(v));
        }
        resolve(new Response(body, { status: res.statusCode, headers }));
        return originalEnd(chunk, ...args);
      };

      // Invoke the Express app directly (it is a request handler).
      try { app(req as any, res as any); } catch (e) { console.error(e); }

      if (request.body) {
        const reader = request.body.getReader();
        const pump = async () => {
          while (true) {
            const { done, value } = await reader.read();
            if (done) { req.push(null); break; }
            req.push(Buffer.from(value));
          }
        };
        pump();
      } else {
        req.push(null);
      }
    });
  },
};
