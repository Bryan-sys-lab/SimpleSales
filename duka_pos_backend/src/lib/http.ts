import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { ZodError } from 'zod';
import { log } from './observability';

/**
 * Wraps an async route handler so a rejection reaches the error handler
 * instead of hanging the request. Typed against Express's own handler shape,
 * so the handlers it wraps keep their request/response types.
 */
export function asyncHandler(
  fn: (req: Request, res: Response, next?: NextFunction) => unknown,
): RequestHandler {
  return (req, res, next) => {
    void Promise.resolve(fn(req, res, next)).catch(next);
  };
}

export function errorHandler(error: any, req: any, res: any, _next: any) {
  const requestId = req.requestId;
  if (error instanceof ZodError) {
    return res.status(400).json({ error: 'Invalid request', fields: error.flatten().fieldErrors, requestId });
  }
  const status = typeof error === 'object' && error !== null && 'status' in error && typeof error.status === 'number' ? error.status : 500;
  log(status >= 500 ? 'error' : 'warn', 'http.error', { requestId, status, message: error instanceof Error ? error.message : 'Unknown error' });
  if (status >= 400 && status < 500) {
    return res.status(status).json({ error: 'Request could not be completed', requestId });
  }
  return res.status(500).json({ error: 'Internal server error', requestId });
}

/**
 * A failure with a deliberate status. The error handler already trusts a
 * numeric `status` on the error, so this rides the existing boundary.
 */
export class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

/**
 * The shop user the auth middleware attached, or a 401 the handler can rely on.
 *
 * Used INSIDE a route handler body, after the middleware has run: the type on
 * `req.user` is optional because `Request` is shared, but a route mounted
 * behind `authMiddleware` never runs without one. Calling this narrows the
 * type once per handler instead of littering `!` down the body.
 */
export function requireUser(req: Request): {
  id: string;
  tenantId: string;
  role: string;
  name: string;
} {
  if (!req.user) throw new HttpError(401, 'Authenticated shop user required');
  return req.user;
}
