import { randomUUID } from 'node:crypto';
import { Request, Response, NextFunction } from 'express';

export function requestContext(req: Request, res: Response, next: NextFunction) {
  const supplied = req.headers['x-request-id'];
  const requestId = typeof supplied === 'string' && supplied.length <= 80 ? supplied : randomUUID();
  req.requestId = requestId;
  res.setHeader('x-request-id', requestId);
  const started = process.hrtime.bigint();
  res.on('finish', () => log('info', 'http.request', { requestId, method: req.method, path: req.path, status: res.statusCode, durationMs: Number(process.hrtime.bigint() - started) / 1_000_000 }));
  next();
}

export function log(level: 'info' | 'warn' | 'error', event: string, fields: Record<string, unknown> = {}) {
  const line = JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...fields });
  if (level === 'error') console.error(line); else if (level === 'warn') console.warn(line); else console.log(line);
}

declare global { namespace Express { interface Request { requestId?: string; } } }
