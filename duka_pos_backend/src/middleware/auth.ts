/**
 * Authentication middleware for Duka POS backend.
 *
 * Verifies self-hosted JWT access tokens (HS256), loads the caller's
 * profiles from the database, and attaches `{ id, tenantId, role, name }`
 * to `req.user`. Device-tier tokens are restricted to catalogue/report
 * routes.
 */
import express from 'express';
import { prisma } from '../lib/prisma';
import { verifyAccessToken } from '../lib/jwt';

declare global {
  namespace Express {
    interface Request {
      auth?: {
        sub: string;
        email?: string;
        email_verified?: boolean;
        token_use?: string;
        [key: string]: unknown;
      };
      user?: {
        id: string;
        tenantId: string;
        role: string;
        name: string;
      };
      requestId?: string;
    }
  }
}

// Startup validation: AUTH_JWT_SECRET must be configured.
const jwtSecret = process.env.AUTH_JWT_SECRET;
if (!jwtSecret || jwtSecret.trim() === '') {
  throw new Error('AUTH_JWT_SECRET must be configured');
}

// ---------------------------------------------------------------------------
// Auth middleware: verify JWT, load profiles, attach req.user
// ---------------------------------------------------------------------------

export const authMiddleware = async (req: express.Request, res: express.Response, next: express.NextFunction): Promise<any> => {
  // Public paths.
  if (req.method === 'GET' && req.path.startsWith('/etims/verify/')) return next();
  if (req.method === 'GET' && req.path.startsWith('/receipt-links/')) return next();
  if (req.method === 'GET' && req.path.startsWith('/health')) return next();
  if (req.method === 'GET' && req.path.startsWith('/ready')) return next();

  const authorization = req.header('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) {
    const err: any = new Error('Missing bearer token');
    err.status = 401;
    return next(err);
  }
  const claims = verifyAccessToken(token);
  if (!claims) {
    const err: any = new Error('Invalid or expired token');
    err.status = 401;
    return next(err);
  }
  req.auth = {
    sub: claims.sub,
    email: claims.email,
    email_verified: claims.email_verified,
    token_use: claims.token_use,
  };

  // Provisioning / shop listing allowed for any authenticated account.
  if (req.method === 'POST' && req.path === '/tenant/provision') return next();
  if (req.method === 'GET' && req.path === '/tenant/shops') return next();

  // Device-tier restriction.
  if (claims.token_use === 'device') {
    const allowedPrefixes = ['/tenant/', '/products/', '/reports/'];
    const path = req.path.startsWith('/api') ? req.path.slice(4) : req.path;
    const ok = allowedPrefixes.some((p) => path.startsWith(p));
    if (!ok) {
      return res.status(403).json({ error: 'Device token not allowed', code: 'DEVICE_TOKEN_NOT_ALLOWED', requestId: req.requestId });
    }
  }

  try {
    const profiles = await prisma.profile.findMany({
      where: { userId: claims.sub, active: true, deletedAt: null },
      include: { tenant: true },
      orderBy: { createdAt: 'asc' },
    });
    if (profiles.length === 0) {
      // Allow provisioning path already handled; otherwise 403.
      if (req.method === 'POST' && req.path === '/tenant/provision') return next();
      return res.status(403).json({ error: 'No active profile found', requestId: req.requestId });
    }
    const requestedTenantId = req.header('x-tenant-id');
    const profile = requestedTenantId
      ? profiles.find((c) => c.tenantId === requestedTenantId)
      : profiles.length === 1 ? profiles[0] : undefined;
    if (requestedTenantId && !profile) {
      return res.status(403).json({ error: 'Tenant not accessible', code: 'TENANT_FORBIDDEN', requestId: req.requestId });
    }
    if (!profile) {
      return res.status(409).json({
        error: 'Tenant selection required',
        code: 'TENANT_SELECTION_REQUIRED',
        tenants: profiles.map((c) => ({ id: c.tenantId, shopName: c.tenant.shopName })),
        requestId: req.requestId,
      });
    }
    req.user = {
      id: profile.id,
      tenantId: profile.tenantId,
      role: profile.role,
      name: profile.name,
    };
    next();
  } catch (error) {
    next(error);
  }
};

// Alias for compatibility with existing route registration.
export const checkJwt = authMiddleware;

export const requireOwner = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Shop admin access required', requestId: req.requestId });
  }
  next();
};

export const requireRole = (...roles: string[]) => (req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (!req.user || !roles.includes(req.user.role))
    return res.status(403).json({ error: 'Insufficient permissions', requestId: req.requestId });
  next();
};

export const systemAdminMiddleware = async (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const authorization = req.header('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) return res.status(401).json({ error: 'Missing bearer token', requestId: req.requestId });
  const claims = verifyAccessToken(token);
  if (!claims) return res.status(401).json({ error: 'Invalid or expired token', requestId: req.requestId });
  const allowed = (process.env.SYSTEM_ADMIN_SUBJECTS ?? '').split(',').map((v) => v.trim()).filter(Boolean);
  if (!allowed.includes(claims.sub)) {
    return res.status(403).json({ error: 'System administrator access required', requestId: req.requestId });
  }
  req.auth = { sub: claims.sub, email: claims.email, email_verified: claims.email_verified, token_use: claims.token_use };
  next();
};
