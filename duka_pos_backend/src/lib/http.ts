import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { log } from './observability.js';

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
) {
  return (req: Request, res: Response, next: NextFunction) => {
    void fn(req, res, next).catch(next);
  };
}

export function errorHandler(error: unknown, req: Request, res: Response, _next: NextFunction) {
  const requestId = req.requestId;
  if (error instanceof ZodError) {
    return res.status(400).json({ error: 'Invalid request', fields: error.flatten().fieldErrors, requestId });
  }
  const status = typeof error === 'object' && error !== null && 'status' in error && typeof error.status === 'number' ? error.status : 500;
  log(status >= 500 ? 'error' : 'warn', 'http.error', { requestId, status, message: error instanceof Error ? error.message : 'Unknown error' });
  if (status >= 400 && status < 500) return res.status(status).json({ error: 'Request could not be completed', requestId });
  return res.status(500).json({ error: 'Internal server error', requestId });
}

/**
 * The value of a route parameter.
 *
 * Express 5 types a parameter as `string | string[]`, because a route may
 * repeat a name. Every parameter in this service is a single path segment,
 * so the first value is the value — and saying so in one place is better
 * than a cast at every use.
 */
export function routeParam(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}
