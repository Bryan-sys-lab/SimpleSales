/**
 * Authentication middleware for Duka POS backend.
 *
 * Verifies OIDC JWTs via express-jwt + JWKS (Keycloak by default), loads the
 * caller's profile from the database, and attaches `{ id, tenantId, role, name }`
 * to `req.user`. `systemAdminMiddleware` grants platform-level access to an
 * OIDC subject allowlist (SYSTEM_ADMIN_SUBJECTS) — shop RBAC is entirely
 * separate from platform administration.
 *
 * ## ONE CREDENTIAL
 *
 * The only thing this service accepts is a Keycloak access token, verified
 * against the identity server's own JWKS.
 *
 * It used to accept a second one: a session token of our own, signed here and
 * minted by `/auth/verify` after an emailed code was presented. Two
 * credentials means two things to revoke, two expiry clocks, and a class of
 * token the identity server has never heard of — and the whole point of
 * running Keycloak is that one authority decides who a person is. The till
 * signs in to Keycloak and sends that token; this service checks it and
 * nothing else.
 */
import dotenv from 'dotenv';
import express, { Request, Response, NextFunction, RequestHandler } from 'express';
import { expressjwt } from 'express-jwt';
import jwksRsa from 'jwks-rsa';
import { prisma } from '../lib/prisma';

dotenv.config();

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
        role: string;
        name: string;
      };
      requestId?: string;
    }
  }
}

// ---------------------------------------------------------------------------
// OIDC / JWT verification
// ---------------------------------------------------------------------------

// JWT verification using any standards-compliant OIDC provider (Keycloak by
// default). The mobile client uses the same issuer and audience values.
const oidcIssuer = process.env.OIDC_ISSUER_URL?.replace(/\/$/, '');
const oidcAudience = process.env.OIDC_AUDIENCE;
const oidcJwksUri = process.env.OIDC_JWKS_URI || (oidcIssuer ? `${oidcIssuer}/protocol/openid-connect/certs` : undefined);
if (!oidcIssuer || !oidcAudience || !oidcJwksUri) {
  throw new Error('OIDC_ISSUER_URL and OIDC_AUDIENCE must be configured');
}

// Annotated rather than inferred: `express-jwt`'s return type reaches into
// `express-unless`, and in this worktree that module resolves through a
// symlinked node_modules outside the project root, which TypeScript refuses to
// name. The annotation names it once, portably.
export const checkJwt: RequestHandler = expressjwt({
  secret: jwksRsa.expressJwtSecret({
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 5,
    jwksUri: oidcJwksUri
  }),
  audience: oidcAudience,
  issuer: oidcIssuer,
  algorithms: ['RS256'],
});

/**
 * Loads the caller's shop profile from the verified subject.
 *
 * Split out of `authMiddleware` so there is exactly one place that decides
 * who the caller is.
 */
const attachProfile = async (req: Request, res: Response, next: NextFunction) => {
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
        name: profile.name,
      };
      next();
    } catch (error) {
      next(error);
    }
};

// Middleware to load user profile from database
export const authMiddleware = async (req: Request, res: Response, next: NextFunction) => {
  // The one credential: a Keycloak access token, checked against the identity
  // server's JWKS.
  checkJwt(req, res, (err) => {
    if (err) return next(err);
    void attachProfile(req, res, next);
  });
};

// ---------------------------------------------------------------------------
// Role-based access control helpers
// ---------------------------------------------------------------------------

/**
 * Requires the caller to be a shop admin (role === 'admin').
 */
export const requireOwner = (req: Request, res: Response, next: NextFunction) => {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Shop admin access required', requestId: req.requestId });
  }
  next();
};

/**
 * Factory: requires the caller's role to be one of the given roles.
 */
export const requireRole = (...roles: string[]) => (req: Request, res: Response, next: NextFunction) => {
  if (!req.user || !roles.includes(req.user.role))
    return res.status(403).json({ error: 'Insufficient permissions', requestId: req.requestId });
  next();
};

/**
 * Platform-level access is deliberately separate from shop RBAC. A shop admin
 * must never become a platform administrator by virtue of owning a shop.
 */
export const systemAdminMiddleware = (req: Request, res: Response, next: NextFunction) => {
  checkJwt(req, res, (error: any) => {
    if (error) return next(error);
    const allowed = (process.env.SYSTEM_ADMIN_SUBJECTS ?? '').split(',').map((value) => value.trim()).filter(Boolean);
    if (!req.auth?.sub || !allowed.includes(req.auth.sub)) {
      return res.status(403).json({ error: 'System administrator access required', requestId: req.requestId });
    }
    next();
  });
};
