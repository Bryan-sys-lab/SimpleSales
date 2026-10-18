/**
 * Role helpers for Duka POS RBAC.
 *
 * Profile.role is a plain String ('cashier' | 'manager' | 'admin' |
 * 'system_admin'). 'system_admin' is platform-level and entirely separate
 * from shop RBAC — owning a shop does not make one a platform administrator.
 */
import { NextFunction, Request, Response } from 'express';

/**
 * True when the role is the platform-wide system administrator role.
 */
export function isSystemAdmin(role: string): boolean {
  return role === 'system_admin';
}

/**
 * True when the role is a shop administrator.
 */
export function isShopAdmin(role: string): boolean {
  return role === 'admin';
}

/**
 * Middleware: only a system admin may proceed; otherwise 403.
 */
export function requireSystemAdmin(req: Request, res: Response, next: NextFunction): void {
  if (req.user?.role !== 'system_admin') {
    res.status(403).json({ error: 'System administrator access required' });
    return;
  }
  next();
}
