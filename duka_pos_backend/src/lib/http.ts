import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { log } from './observability';

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
