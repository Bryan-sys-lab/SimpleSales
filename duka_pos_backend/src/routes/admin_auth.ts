import { Request, Response, Router } from 'express';
import rateLimit from 'express-rate-limit';
import crypto from 'node:crypto';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { prisma } from '../lib/prisma';
import { parseBody } from '../lib/validation';
import { issueAccessToken } from '../lib/jwt';
import { systemAdminMiddleware } from '../middleware/auth';
import { log } from '../lib/observability';
import { issueAdminWebSocketTicket } from '../services/admin_ws_tickets';

const router = Router();
const loginLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 8, standardHeaders: 'draft-7', legacyHeaders: false, skipSuccessfulRequests: true });
const permissionOptions = [
  'system:read', 'keys:read', 'keys:manage', 'users:read', 'users:manage',
  'tenants:read', 'tenants:manage', 'sessions:read', 'sessions:manage',
  'diagnostics:read', 'diagnostics:manage', 'commercial:read', 'commercial:manage',
  'audit:read', 'analytics:read', 'configuration:read', 'configuration:manage', 'tasks:read', 'tasks:manage',
  'support:read', 'support:manage',
] as const;
const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  masterToken: z.string().min(24).max(512).optional(),
  phone: z.string().trim().min(6).max(30).optional(),
  key: z.string().min(24).max(128).optional(),
}).strict();
const mintSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  phone: z.string().trim().min(6).max(30),
  department: z.string().trim().min(2).max(80),
  role: z.enum(['worker', 'manager', 'department_head', 'executive']).default('worker'),
  permissions: z.array(z.enum(permissionOptions)).max(permissionOptions.length),
  canRecruit: z.boolean().default(false),
  canMintKeys: z.boolean().default(false),
  canAssignTasks: z.boolean().default(false),
  expiresInDays: z.number().int().min(1).max(365).default(30),
}).strict();
const keyUpdateSchema = z.object({
  role: z.enum(['worker', 'manager', 'department_head', 'executive']).optional(),
  permissions: z.array(z.enum(permissionOptions)).max(permissionOptions.length).optional(),
  canRecruit: z.boolean().optional(), canMintKeys: z.boolean().optional(), canAssignTasks: z.boolean().optional(),
  expiresInDays: z.number().int().min(1).max(365).optional(),
}).strict().refine((value) => Object.keys(value).length > 0);

function constantTimeEqual(a: string, b: string): boolean {
  const left = crypto.createHash('sha256').update(a).digest();
  const right = crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(left, right);
}

async function isWithinAdminScope(target: { parentKeyId: string | null; department: string }, access: any): Promise<boolean> {
  if (access?.isSuperAdmin) return true;
  if (!access?.keyId || target.department !== access.department) return false;
  let parentId = target.parentKeyId;
  for (let depth = 0; depth < 5 && parentId; depth += 1) {
    if (parentId === access.keyId) return true;
    const parent = await prisma.adminKey.findUnique({ where: { id: parentId }, select: { parentKeyId: true, department: true } });
    if (!parent || parent.department !== access.department) return false;
    parentId = parent.parentKeyId;
  }
  return false;
}

router.post('/login', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(loginSchema, req.body);
  const superEmail = (process.env.SYSTEM_ADMIN_EMAIL ?? 'brian@nerva.co.ke').trim().toLowerCase();
  const masterToken = process.env.SYSTEM_ADMIN_TOKEN;
  if (input.email === superEmail && input.masterToken && masterToken && constantTimeEqual(input.masterToken, masterToken)) {
    const { token, expiresIn } = issueAccessToken({ userId: 'super-admin', email: superEmail, emailVerified: true, tier: 'admin' });
    log('info', 'admin.auth.login', { subject: 'super-admin' });
    return res.json({ access_token: token, token_type: 'Bearer', expires_in: expiresIn, email: superEmail, role: 'super_admin' });
  }
  if (!input.phone || !input.key) return res.status(401).json({ error: 'Invalid administrator credentials' });
  const key = await prisma.adminKey.findFirst({ where: { email: input.email, phone: input.phone, revokedAt: null, expiresAt: { gt: new Date() } }, orderBy: { createdAt: 'desc' } });
  if (!key || key.revokedAt || key.expiresAt <= new Date() || !constantTimeEqual(crypto.createHash('sha256').update(input.key).digest('hex'), key.keyHash)) {
    return res.status(401).json({ error: 'Invalid administrator credentials' });
  }
  await prisma.adminKey.update({ where: { id: key.id }, data: { usedAt: new Date() } });
  const { token, expiresIn } = issueAccessToken({ userId: `admin:${key.id}`, email: input.email, emailVerified: true, tier: 'admin' });
  log('info', 'admin.auth.login', { subject: `admin:${key.id}` });
  return res.json({ access_token: token, token_type: 'Bearer', expires_in: expiresIn, email: input.email, role: 'department_admin' });
}));

router.get('/session', systemAdminMiddleware, (req, res) => res.json({
  email: req.auth?.email,
  role: (req as any).adminAccess?.isSuperAdmin ? 'super_admin' : 'department_admin',
  department: (req as any).adminAccess?.department,
  permissions: (req as any).adminAccess?.isSuperAdmin ? permissionOptions : (req as any).adminAccess?.permissions ?? [],
  canRecruit: (req as any).adminAccess?.canRecruit ?? false,
  canMintKeys: (req as any).adminAccess?.canMintKeys ?? false,
  canAssignTasks: (req as any).adminAccess?.canAssignTasks ?? false,
}));

router.post('/ws-ticket', systemAdminMiddleware, (_req, res) => res.json({ ticket: issueAdminWebSocketTicket(), expiresIn: 30 }));

router.get('/keys', systemAdminMiddleware, asyncHandler(async (req, res) => {
  const access = (req as any).adminAccess;
  let ids: string[] | undefined;
  if (!access?.isSuperAdmin && access?.keyId) {
    let frontier = [access.keyId];
    ids = [];
    for (let depth = 0; depth < 4 && frontier.length; depth += 1) {
      const children = await prisma.adminKey.findMany({ where: { parentKeyId: { in: frontier }, department: access.department }, select: { id: true } });
      frontier = children.map((child) => child.id);
      ids.push(...frontier);
    }
  }
  const keys = ids && !ids.length ? [] : await prisma.adminKey.findMany({
    where: ids ? { id: { in: ids } } : {},
    select: { id: true, email: true, phone: true, department: true, role: true, permissions: true, canRecruit: true, canMintKeys: true, canAssignTasks: true, parentKeyId: true, parent: { select: { id: true, email: true, department: true, role: true } }, createdBy: true, createdAt: true, usedAt: true, expiresAt: true, revokedAt: true },
    orderBy: { createdAt: 'desc' }, take: 500,
  });
  res.json({ keys });
}));

router.post('/keys/mint', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(mintSchema, req.body);
  const access = (req as any).adminAccess;
  if (!access?.isSuperAdmin) {
    const roleRank: Record<string, number> = { worker: 0, manager: 1, department_head: 2, executive: 3 };
    const caller = await prisma.adminKey.findUnique({ where: { id: access?.keyId ?? '' }, select: { role: true } });
    if (!access?.canMintKeys || !access?.canRecruit || input.department !== access.department ||
        roleRank[input.role] >= roleRank[caller?.role ?? 'worker'] ||
        input.canMintKeys && !access.canMintKeys || input.canRecruit && !access.canRecruit ||
        input.canAssignTasks && !access.canAssignTasks || input.permissions.some((p: string) => !access.permissions.includes(p))) {
      return res.status(403).json({ error: 'Requested key exceeds your department permissions' });
    }
  }
  const rawKey = crypto.randomBytes(32).toString('base64url');
  const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');
  const expiresAt = new Date(Date.now() + input.expiresInDays * 86400000);
  const key = await prisma.$transaction(async (tx) => {
    const created = await tx.adminKey.create({ data: {
      email: input.email, phone: input.phone, keyHash, createdBy: req.auth?.sub ?? 'unknown',
      expiresAt, department: input.department, role: input.role, permissions: input.permissions,
      canRecruit: input.canRecruit, canMintKeys: input.canMintKeys, canAssignTasks: input.canAssignTasks, parentKeyId: access?.keyId ?? null,
    } });
    await tx.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'admin_account_invited', targetType: 'admin_key', targetId: created.id, tenantId: null } });
    return created;
  });
  log('info', 'admin.key.minted', { keyId: key.id, createdBy: req.auth?.sub, department: key.department });
  res.status(201).json({ key: rawKey, id: key.id, email: key.email, phone: key.phone, department: key.department, role: key.role, permissions: key.permissions, canRecruit: key.canRecruit, canMintKeys: key.canMintKeys, canAssignTasks: key.canAssignTasks, expiresAt });
}));

router.patch('/keys/:id', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(keyUpdateSchema, req.body);
  const access = (req as any).adminAccess;
  const target = await prisma.adminKey.findUnique({ where: { id: req.params.id as string } });
  if (!target) return res.status(404).json({ error: 'Administrator key not found' });
  if (!access?.isSuperAdmin) {
    const caller = await prisma.adminKey.findUnique({ where: { id: access?.keyId ?? '' }, select: { role: true } });
    const rank: Record<string, number> = { worker: 0, manager: 1, department_head: 2, executive: 3 };
    const nextRole = input.role ?? target.role;
    const nextPermissions = input.permissions ?? (Array.isArray(target.permissions) ? target.permissions : []);
    if (!await isWithinAdminScope(target, access) || target.parentKeyId === null ||
        rank[nextRole] >= rank[caller?.role ?? 'worker'] ||
        input.canMintKeys === true && !access.canMintKeys ||
        input.canRecruit === true && !access.canRecruit ||
        input.canAssignTasks === true && !access.canAssignTasks ||
        nextPermissions.some((permission) => !access.permissions.includes(permission))) {
      return res.status(403).json({ error: 'Requested access exceeds your department permissions' });
    }
  }
  const updated = await prisma.$transaction(async (tx) => {
    const row = await tx.adminKey.update({ where: { id: target.id }, data: {
      ...(input.role !== undefined ? { role: input.role } : {}),
      ...(input.permissions !== undefined ? { permissions: input.permissions } : {}),
      ...(input.canRecruit !== undefined ? { canRecruit: input.canRecruit } : {}),
      ...(input.canMintKeys !== undefined ? { canMintKeys: input.canMintKeys } : {}),
      ...(input.canAssignTasks !== undefined ? { canAssignTasks: input.canAssignTasks } : {}),
      ...(input.expiresInDays !== undefined ? { expiresAt: new Date(Date.now() + input.expiresInDays * 86400000) } : {}),
    }, select: { id: true, email: true, department: true, role: true, permissions: true, canRecruit: true, canMintKeys: true, canAssignTasks: true, expiresAt: true, revokedAt: true } });
    await tx.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'admin_access_updated', targetType: 'admin_key', targetId: row.id, tenantId: null } });
    return row;
  });
  log('info', 'admin.key.permissions_updated', { keyId: updated.id, updatedBy: req.auth?.sub });
  res.json({ key: updated });
}));

router.post('/keys/:id/revoke', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const access = (req as any).adminAccess;
  const target = await prisma.adminKey.findUnique({ where: { id: req.params.id as string } });
  if (!target) return res.status(404).json({ error: 'Administrator key not found' });
  if (!await isWithinAdminScope(target, access)) return res.status(403).json({ error: 'Key is outside your management scope' });
  const descendants: string[] = [target.id];
  let frontier = [target.id];
  for (let depth = 0; depth < 4 && frontier.length; depth += 1) {
    const children = await prisma.adminKey.findMany({ where: { parentKeyId: { in: frontier } }, select: { id: true } });
    frontier = children.map((child) => child.id);
    descendants.push(...frontier);
  }
  const revokedAt = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.adminKey.updateMany({ where: { id: { in: descendants }, revokedAt: null }, data: { revokedAt } });
    await tx.adminAuditLog.create({ data: { adminId: req.auth?.sub ?? 'unknown', action: 'admin_access_revoked', targetType: 'admin_key', targetId: target.id, tenantId: null } });
  });
  const key = { id: target.id, revokedAt };
  log('info', 'admin.key.revoked', { keyId: key.id, revokedBy: req.auth?.sub });
  res.json({ key });
}));

export default router;
