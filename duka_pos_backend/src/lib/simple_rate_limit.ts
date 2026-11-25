import type { NextFunction, Request, Response } from 'express';

type KeyFn = (req: Request) => string;

type Options = {
  windowMs: number;
  limit: number;
  keyGenerator?: KeyFn;
  skip?: (req: Request) => boolean;
  skipSuccessfulRequests?: boolean;
  standardHeaders?: boolean | 'draft-7';
  legacyHeaders?: boolean;
  message?: Record<string, unknown>;
  validate?: unknown;
};

type Entry = { count: number; resetAt: number };

const stores = new Map<string, Map<string, Entry>>();

function getStore(name: string): Map<string, Entry> {
  let store = stores.get(name);
  if (!store) {
    store = new Map<string, Entry>();
    stores.set(name, store);
  }
  return store;
}

function defaultKey(req: Request): string {
  return req.ip || req.socket?.remoteAddress || 'unknown';
}

export function simpleRateLimit(name: string, options: Options) {
  const store = getStore(name);
  const keyFn = options.keyGenerator ?? defaultKey;
  return (req: Request, res: Response, next: NextFunction) => {
    if (options.skip?.(req)) return next();
    const now = Date.now();
    const key = keyFn(req) || 'unknown';
    let entry = store.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + options.windowMs };
      store.set(key, entry);
    }
    // Opportunistic cleanup to bound memory in long-lived isolates.
    if (store.size > 5000) {
      for (const [k, v] of store) {
        if (v.resetAt <= now) store.delete(k);
      }
    }
    entry.count += 1;
    const remaining = Math.max(0, options.limit - entry.count);
    if (options.standardHeaders) {
      res.setHeader('RateLimit-Limit', String(options.limit));
      res.setHeader('RateLimit-Remaining', String(remaining));
      res.setHeader('RateLimit-Reset', String(Math.ceil(entry.resetAt / 1000)));
    }
    if (entry.count > options.limit) {
      const retryAfter = Math.max(1, Math.ceil((entry.resetAt - now) / 1000));
      res.setHeader('Retry-After', String(retryAfter));
      return res.status(429).json(options.message ?? { error: 'Too many requests', code: 'RATE_LIMITED' });
    }
    if (options.skipSuccessfulRequests) {
      res.on('finish', () => {
        if (res.statusCode < 400) {
          const cur = store.get(key);
          if (cur && cur.count > 0) cur.count -= 1;
        }
      });
    }
    return next();
  };
}

export function _resetSimpleRateLimitStoresForTests(): void {
  stores.clear();
}
