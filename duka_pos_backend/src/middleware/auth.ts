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
import { verifyAccessToken, verifyStaffSessionToken } from '../lib/jwt';
import { tenantEntitlement } from '../lib/entitlements';
import { effectiveAdminPermissions, normalizeAdminPackages } from '../lib/admin_access_catalog';

declare global {
  namespace Express {
    interface Request {
      auth?: {
        sub: string;
        email?: string;
        email_verified?: boolean;
        token_use?: string;
        remembered?: boolean;
        jti?: string;
        [key: string]: unknown;
      };
      user?: {
        id: string;
        tenantId: string;
        role: string;
        name: string;
      };
      requestId?: string;
      adminAccess?: {
        isSuperAdmin: boolean;
        permissions: string[];
        packages: string[];
        department: string;
        canRecruit: boolean;
        canMintKeys: boolean;
        canAssignTasks: boolean;
        keyId: string | null;
      };
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
  // `authMiddleware` is mounted once at `/api` and some route modules also
  // apply it locally. `req.path` therefore changes from
  // `/tenant/staff/authenticate` to `/staff/authenticate` on the second pass;
  // use the normalized original URL so the bootstrap exception remains
  // equally narrow at both layers.
  const normalizedOriginalPath = req.originalUrl
    .split('?')[0]
    .replace(/^\/api(?=\/)/, '');
  // Admin auth is a separate credential domain from shop profiles.
  if (normalizedOriginalPath === '/admin/auth/login') return next();
  // Public paths.
  if (req.method === 'GET' && req.path.startsWith('/etims/verify/')) return next();
  if (req.method === 'GET' && req.path.startsWith('/receipt-links/')) return next();
  if (req.method === 'GET' && req.path.startsWith('/health')) return next();
  if (req.method === 'GET' && req.path.startsWith('/ready')) return next();

  // Staff PIN authentication is the bootstrap path for a fresh till. It
  // cannot require the app bearer token that staff are trying to obtain; the
  // selected tenant ID scopes the request and the staff route verifies the
  // username/PIN against that tenant. Keep the exception narrow.
  if (
    req.method === 'POST' &&
    normalizedOriginalPath === '/tenant/staff/authenticate' &&
    Boolean(req.header('x-tenant-id')?.trim())
  ) {
    return next();
  }

  const authorization = req.header('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) {
    const err: any = new Error('Missing bearer token');
    err.status = 401;
    return next(err);
  }
  if (req.method === 'POST' && normalizedOriginalPath === '/tenant/staff/self-pin') {
    const staffClaims = verifyStaffSessionToken(token);
    if (!staffClaims || req.header('x-tenant-id') !== staffClaims.tenantId) {
      const err: any = new Error('Invalid or expired staff session');
      err.status = 401;
      return next(err);
    }
    return prisma.profile.findFirst({
      where: { id: staffClaims.profileId, tenantId: staffClaims.tenantId, active: true, deletedAt: null },
      select: { id: true, tenantId: true, role: true, name: true },
    }).then((profile) => {
      if (!profile) {
        const err: any = new Error('Invalid or expired staff session');
        err.status = 401;
        return next(err);
      }
      req.auth = { sub: staffClaims.sub, token_use: 'staff' };
      req.user = { id: profile.id, tenantId: profile.tenantId, role: profile.role, name: profile.name };
      return next();
    }).catch(next);
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
    jti: claims.jti,
  };

  const voucherBillingPath = normalizedOriginalPath === '/auth/voucher/redeem' ||
    normalizedOriginalPath === '/auth/voucher/claim';

  // Provisioning / shop listing allowed for any authenticated account.
  if (req.method === 'POST' && req.path === '/tenant/provision') return next();
  if (req.method === 'GET' && req.path === '/tenant/shops') return next();

  // Device-tier restriction.
  if (claims.token_use === 'device') {
    const allowedPrefixes = [
      '/tenant',
      '/products',
      '/reports',
      '/admin',
      '/sales',
      '/backups',
      '/payments',
    ];
    const ok = voucherBillingPath ||
      allowedPrefixes.some((p) => normalizedOriginalPath === p || normalizedOriginalPath.startsWith(p + '/'));
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
    // Billing endpoints remain reachable while access is blocked so an owner
    // can redeem a voucher or inspect the negotiated shop terms.
    const billingExemption = voucherBillingPath ||
      (req.method === 'GET' && normalizedOriginalPath === '/backups/full') ||
      normalizedOriginalPath === '/tenant/subscription' ||
      normalizedOriginalPath.startsWith('/tenant/subscription/') ||
      normalizedOriginalPath.startsWith('/tenant/membership') ||
      normalizedOriginalPath === '/telemetry/support';
    if (!billingExemption) {
      const entitlement = await tenantEntitlement(profile.tenantId);
      if (!entitlement.allowed) {
        return res.status(402).json({
          error: 'An active subscription or voucher is required',
          code: 'SUBSCRIPTION_REQUIRED',
          entitlement,
          requestId: req.requestId,
        });
      }
    }
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
  const allowed = (process.env.SYSTEM_ADMIN_SUBJECTS ?? '').split(',').map((v) => v.trim()).filter(Boolean);
  const authorization = req.header('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) return res.status(401).json({ error: 'Missing bearer token', requestId: req.requestId });
  const claims = verifyAccessToken(token);
  if (!claims || claims.token_use !== 'admin') return res.status(401).json({ error: 'Invalid or expired administrator token', requestId: req.requestId });
  let permissions: string[] = [];
  let packages: string[] = [];
  let keyId: string | null = null;
  let department = 'system';
  let canRecruit = true;
  let canMintKeys = true;
  let canAssignTasks = true;
  const isSuperAdmin = claims.sub === 'super-admin' || allowed.includes(claims.sub);
  if (!isSuperAdmin && claims.sub.startsWith('admin:')) {
    keyId = claims.sub.slice('admin:'.length);
    const key = await prisma.adminKey.findUnique({ where: { id: keyId } });
    if (!key || key.revokedAt || key.expiresAt < new Date()) {
      return res.status(403).json({ error: 'System administrator access required', requestId: req.requestId });
    }
    if (claims.email !== key.email) return res.status(403).json({ error: 'Administrator identity mismatch', requestId: req.requestId });
    department = key.department;
    packages = normalizeAdminPackages(key.packages, key.department);
    const storedPermissions = Array.isArray(key.permissions) ? key.permissions.filter((p): p is string => typeof p === 'string') : [];
    permissions = effectiveAdminPermissions(packages, storedPermissions);
    canRecruit = key.canRecruit;
    canMintKeys = key.canMintKeys;
    canAssignTasks = key.canAssignTasks;
  } else if (!isSuperAdmin && !allowed.includes(claims.sub)) {
    return res.status(403).json({ error: 'System administrator access required', requestId: req.requestId });
  }
  req.adminAccess = { isSuperAdmin, permissions, packages, department, canRecruit, canMintKeys, canAssignTasks, keyId };
  req.auth = {
    sub: claims.sub,
    email: claims.email,
    email_verified: claims.email_verified,
    token_use: claims.token_use,
    remembered: claims.remembered,
  };
  if (isSuperAdmin) return next();

  const method = req.method.toUpperCase();
  const path = req.originalUrl.split('?')[0].replace(/^\/api/, '');
  // The signed-in caller may read their own access descriptor so the UI can
  // hide screens and controls they cannot use.
  if (
    (method === 'GET' && path === '/admin/auth/session') ||
    (method === 'POST' && path === '/admin/auth/refresh') ||
    (method === 'POST' && path === '/admin/auth/ws-ticket')
  ) return next();
  const permission = adminPermissionFor(method, path);
  if (!permission || !permissions.includes(permission)) return res.status(403).json({ error: 'Administrator permission required', permission, requestId: req.requestId });
  if (method === 'POST' && /\/keys(?:\/mint)?$/.test(path) && !canMintKeys) return res.status(403).json({ error: 'Key minting is not permitted', requestId: req.requestId });
  if (/\/org\/tasks\/?$/.test(path) && method === 'POST' && !canAssignTasks) return res.status(403).json({ error: 'Task assignment is not permitted', requestId: req.requestId });
  if ((method === 'POST' || method === 'PATCH') && /\/users(?:\/|$)/.test(path) && !canRecruit) return res.status(403).json({ error: 'Recruiting is not permitted', requestId: req.requestId });
  return next();
};

export function adminPermissionFor(method: string, path: string): string | null {
  if (/\/auth\/(?:session|logout)$/.test(path)) return 'system:read';
  if (/\/auth\/access-catalog$/.test(path)) return method === 'GET' ? 'keys:read' : 'keys:manage';
  if (/\/org\/reports(?:\/|$)/.test(path)) return 'tasks:read';
  if (/\/keys(?:\/|$)/.test(path)) return method === 'GET' ? 'keys:read' : 'keys:manage';
  if (/\/org\/tasks(?:\/|$)/.test(path)) return method === 'POST' ? 'tasks:manage' : 'tasks:read';
  if (/\/users(?:\/|$)/.test(path)) return method === 'GET' ? 'users:read' : 'users:manage';
  if (/\/tenants(?:\/|$)/.test(path)) return method === 'GET' ? 'tenants:read' : 'tenants:manage';
  if (/\/telemetry(?:\/|$)/.test(path)) return method === 'GET' ? 'sessions:read' : 'sessions:manage';
  if (/\/sessions(?:\/|$)/.test(path)) return method === 'GET' ? 'sessions:read' : 'sessions:manage';
  if (/\/diagnostics(?:\/|$)/.test(path)) return method === 'GET' ? 'diagnostics:read' : 'diagnostics:manage';
  if (/\/commercial\/(?:ledger|aggregate-preview|quality)/.test(path)) return method === 'GET' ? 'commercial:read' : 'commercial:manage';
  if (/\/commercial\//.test(path)) return method === 'GET' ? 'commercial:read' : 'commercial:manage';
  if (/\/audit/.test(path)) return 'audit:read';
  if (/\/analytics|\/churn|\/financials|\/sales|\/products|\/expenses|\/laybys|\/exchanges|\/tax-compliance/.test(path)) return 'analytics:read';
  if (/\/billing\/provider(?:\/|$)/.test(path)) return method === 'GET' ? 'configuration:read' : 'configuration:manage';
  if (/\/billing(?:\/|$)/.test(path)) return method === 'GET' ? 'configuration:read' : 'billing:manage';
  if (/\/tax-rules|\/commercial-policy|\/announcement/.test(path)) return method === 'GET' ? 'configuration:read' : 'configuration:manage';
  if (/\/support/.test(path)) return method === 'GET' ? 'support:read' : 'support:manage';
  if (/\/membership/.test(path)) return method === 'GET' ? 'membership:read' : 'membership:manage';
  return 'system:read';
}
