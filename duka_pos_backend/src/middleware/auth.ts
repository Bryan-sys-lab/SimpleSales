import { expressjwt } from 'express-jwt';
import jwksRsa from 'jwks-rsa';
import dotenv from 'dotenv';
import { Request, Response, NextFunction } from 'express';
import { prisma } from '../lib/prisma';

dotenv.config();

// Augment Express Request type to include auth
declare global {
  namespace Express {
    interface Request {
      auth?: {
        sub: string;
        email?: string;
        email_verified?: boolean;
        [key: string]: unknown;
      };
      user?: {
        id: string;
        tenantId: string;
        role: 'admin' | 'manager' | 'cashier';
        name: string;
      };
    }
  }
}

// JWT verification using any standards-compliant OIDC provider (Keycloak by
// default). The mobile client uses the same issuer and audience values.
const oidcIssuer = process.env.OIDC_ISSUER_URL?.replace(/\/$/, '');
const oidcAudience = process.env.OIDC_AUDIENCE;
const oidcJwksUri = process.env.OIDC_JWKS_URI || (oidcIssuer ? `${oidcIssuer}/protocol/openid-connect/certs` : undefined);

if (!oidcIssuer || !oidcAudience || !oidcJwksUri) {
  throw new Error('OIDC_ISSUER_URL and OIDC_AUDIENCE must be configured');
}

export const checkJwt = expressjwt({
  secret: jwksRsa.expressJwtSecret({
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 5,
    jwksUri: oidcJwksUri
  }),
  audience: oidcAudience,
  issuer: oidcIssuer,
  algorithms: ['RS256']
});

// Middleware to load user profile from database
export const authMiddleware = async (req: Request, res: Response, next: NextFunction) => {
  // First verify JWT
  checkJwt(req, res, async (err) => {
    if (err) return next(err);
    
    try {
      if (!req.auth?.sub) {
        return res.status(401).json({ error: 'No user ID in token' });
      }

      // Load user profile using the OIDC subject claim.
      const profiles = await prisma.profile.findMany({
        where: { oidcSubject: req.auth.sub, active: true, deletedAt: null },
        include: { tenant: true },
        orderBy: { createdAt: 'asc' },
      });

      // `authMiddleware` is mounted at `/api`, so Express exposes this as
      // `/tenant/provision` rather than `/provision`.
      // Provisioning is intentionally allowed for an authenticated OIDC
      // account even when it already owns another shop; this is the
      // multi-shop account creation path.
      if (req.method === 'POST' && req.path === '/tenant/provision') {
        return next();
      }
      if (req.method === 'GET' && req.path === '/tenant/shops') return next();
      if (profiles.length === 0) {
        return res.status(403).json({ error: 'No active profile found' });
      }

      const requestedTenantId = req.header('x-tenant-id');
      const profile = requestedTenantId
        ? profiles.find((candidate) => candidate.tenantId === requestedTenantId)
        : profiles.length === 1 ? profiles[0] : undefined;
      if (!profile) {
        return res.status(409).json({
          error: 'Tenant selection required',
          code: 'TENANT_SELECTION_REQUIRED',
          tenants: profiles.map((candidate) => ({ id: candidate.tenantId, shopName: candidate.tenant.shopName })),
          requestId: req.requestId,
        });
      }

      // Attach user to request
      req.user = {
        id: profile.id,
        tenantId: profile.tenantId,
        role: profile.role,
        name: profile.name
      };

      next();
    } catch (error) {
      next(error);
    }
  });
};

// Role-based access control helper
export const requireOwner = (req: Request, res: Response, next: NextFunction) => {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Shop admin access required', requestId: req.requestId });
  }
  next();
};

export const requireRole = (...roles: Array<'admin' | 'manager' | 'cashier'>) => (req: Request, res: Response, next: NextFunction) => {
  if (!req.user || !roles.includes(req.user.role)) return res.status(403).json({ error: 'Insufficient permissions', requestId: req.requestId });
  next();
};

/** Platform-level access is deliberately separate from shop RBAC. A shop
 * admin must never become a platform administrator by virtue of owning a shop. */
export const systemAdminMiddleware = (req: Request, res: Response, next: NextFunction) => {
  checkJwt(req, res, (error) => {
    if (error) return next(error);
    const allowed = (process.env.SYSTEM_ADMIN_SUBJECTS ?? '').split(',').map((value) => value.trim()).filter(Boolean);
    if (!req.auth?.sub || !allowed.includes(req.auth.sub)) {
      return res.status(403).json({ error: 'System administrator access required', requestId: req.requestId });
    }
    next();
  });
};
