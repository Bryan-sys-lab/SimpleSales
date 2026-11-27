import { Request, Response, Router } from 'express';
import crypto from 'node:crypto';
import { simpleRateLimit } from '../lib/simple_rate_limit';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { prepareAdminAudit } from '../lib/admin_audit_d1';
import { parseBody } from '../lib/validation';
import { issueAccessToken } from '../lib/jwt';
import { systemAdminMiddleware } from '../middleware/auth';
import { log } from '../lib/observability';
import { issueAdminWebSocketTicket } from '../services/admin_ws_tickets';
import { recordAuthAuditEvent } from '../lib/auth_audit';
import {
  adminPackagePermissions,
  adminPackages,
  effectiveAdminPermissions,
  adminPermissionOptions,
  normalizeAdminPackages,
} from '../lib/admin_access_catalog';

const router = Router();
const loginLimiter = simpleRateLimit('admin:login', { windowMs: 15 * 60 * 1000, limit: 8, standardHeaders: 'draft-7', legacyHeaders: false, skipSuccessfulRequests: true });
const refreshLimiter = simpleRateLimit('admin:refresh', { windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false });
const permissionOptions = adminPermissionOptions;
const packageId = z.string().refine((value) => adminPackages.some((item) => item.id === value));
const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  masterToken: z.string().min(24).max(512).optional(),
  phone: z.string().trim().min(6).max(30).optional(),
  key: z.string().min(24).max(128).optional(),
  rememberMe: z.boolean().default(false),
}).strict();
const mintSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  phone: z.string().trim().min(6).max(30),
  department: z.string().trim().min(2).max(80),
  role: z.enum(['worker', 'manager', 'department_head', 'executive']).default('worker'),
  packages: z.array(packageId).max(adminPackages.length).default([]),
  permissions: z.array(z.enum(permissionOptions)).max(permissionOptions.length),
  canRecruit: z.boolean().default(false),
  canMintKeys: z.boolean().default(false),
  canAssignTasks: z.boolean().default(false),
  expiresInDays: z.number().int().min(1).max(365).default(30),
}).strict();
const keyUpdateSchema = z.object({
  role: z.enum(['worker', 'manager', 'department_head', 'executive']).optional(),
  packages: z.array(packageId).max(adminPackages.length).optional(),
  permissions: z.array(z.enum(permissionOptions)).max(permissionOptions.length).optional(),
  canRecruit: z.boolean().optional(), canMintKeys: z.boolean().optional(), canAssignTasks: z.boolean().optional(),
  expiresInDays: z.number().int().min(1).max(365).optional(),
}).strict().refine((value) => Object.keys(value).length > 0);

function constantTimeEqual(a: string, b: string): boolean {
  const left = crypto.createHash('sha256').update(a).digest();
  const right = crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(left, right);
}

function isPackageSubset(target: readonly string[], allowed: readonly string[]): boolean {
  return target.every((packageId) => allowed.includes(packageId));
}

async function isWithinAdminScope(
  target: { parentKeyId: string | null; department: string; packages: unknown },
  access: NonNullable<Request['adminAccess']> | undefined,
): Promise<boolean> {
  if (access?.isSuperAdmin) return true;
  if (!access?.keyId) return false;
  if (!isPackageSubset(normalizeAdminPackages(target.packages, target.department), access.packages ?? [])) return false;
  let parentId = target.parentKeyId;
  for (let depth = 0; depth < 5 && parentId; depth += 1) {
    if (parentId === access.keyId) return true;
    const parent = await prisma.adminKey.findUnique({ where: { id: parentId }, select: { parentKeyId: true, department: true, packages: true } });
    if (!parent || !isPackageSubset(normalizeAdminPackages(parent.packages, parent.department), access.packages ?? [])) return false;
    parentId = parent.parentKeyId;
  }
  return false;
}

const ADMIN_LOCKOUT_MAX_ATTEMPTS = 5;
const ADMIN_LOCKOUT_MS = 15 * 60 * 1000;

type AdminLockoutState = { count: number; lockedUntil: number };

async function readAdminLockout(email: string): Promise<AdminLockoutState | null> {
  const key = `admin_lockout:${email.toLowerCase()}`;
  try {
    const row = await prisma.systemSettings.findUnique({ where: { key } });
    if (!row?.value) return null;
    const parsed = JSON.parse(row.value) as Partial<AdminLockoutState>;
    if (typeof parsed.count !== 'number' || typeof parsed.lockedUntil !== 'number') return null;
    return { count: parsed.count, lockedUntil: parsed.lockedUntil };
  } catch {
    return null;
  }
}

async function writeAdminLockout(email: string, state: AdminLockoutState): Promise<void> {
  const key = `admin_lockout:${email.toLowerCase()}`;
  const value = JSON.stringify(state);
  try {
    await prisma.systemSettings.upsert({
      where: { key },
      update: { value },
      create: { key, value, description: 'Durable admin login lockout state' },
    });
  } catch {
    // Best-effort: lockout enforcement still benefits from in-request checks and AdminKey DB lockout.
  }
}

async function clearAdminLockout(email: string): Promise<void> {
  const key = `admin_lockout:${email.toLowerCase()}`;
  try {
    await prisma.systemSettings.deleteMany({ where: { key } });
  } catch {
    // Best-effort.
  }
}

router.post('/login', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(loginSchema, req.body);
  const failureKey = (input.email || '').toLowerCase();
  const failureState = await readAdminLockout(failureKey);
  if (failureState && failureState.lockedUntil > Date.now()) {
    await recordAuthAuditEvent({ eventType: 'admin_login_locked', actorType: 'admin', outcome: 'failure', reason: 'account_locked', email: input.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
    return res.status(429).json({ error: 'Account locked. Try again later.', code: 'ADMIN_LOCKED' });
  }
  const superEmail = (process.env.SYSTEM_ADMIN_EMAIL ?? 'brian@nerva.co.ke').trim().toLowerCase();
  const masterToken = process.env.SYSTEM_ADMIN_TOKEN;
  const registerFailure = async () => {
    const prev = await readAdminLockout(failureKey);
    const count = (prev?.count ?? 0) + 1;
    await writeAdminLockout(failureKey, {
      count,
      lockedUntil: count >= ADMIN_LOCKOUT_MAX_ATTEMPTS ? Date.now() + ADMIN_LOCKOUT_MS : 0,
    });
  };

  if (input.email === superEmail && input.masterToken && masterToken && constantTimeEqual(input.masterToken, masterToken)) {
    await clearAdminLockout(failureKey);
    const { token, expiresIn } = issueAccessToken({
      userId: 'super-admin',
      email: superEmail,
      emailVerified: true,
      tier: 'admin',
      rememberMe: input.rememberMe,
    });
    log('info', 'admin.auth.login', { subject: 'super-admin' });
    await recordAuthAuditEvent({ eventType: 'admin_login_success', actorType: 'super_admin', outcome: 'success', email: superEmail, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
    return res.json({ access_token: token, token_type: 'Bearer', expires_in: expiresIn, email: superEmail, role: 'super_admin' });
  }
  if (!input.phone || !input.key) {
    await registerFailure();
    await recordAuthAuditEvent({ eventType: 'admin_login_failure', actorType: 'admin', outcome: 'failure', reason: 'missing_credentials', email: input.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
    return res.status(401).json({ error: 'Invalid administrator credentials' });
  }
  const now = new Date();
  const key = await prisma.adminKey.findFirst({
    where: { email: input.email, phone: input.phone, revokedAt: null, expiresAt: { gt: now } },
    orderBy: { createdAt: 'desc' },
  });
  if (key?.lockedUntil && key.lockedUntil > now) {
    await recordAuthAuditEvent({ eventType: 'admin_login_locked', actorType: 'admin', actorId: `admin:${key.id}`, outcome: 'failure', reason: 'account_locked', email: input.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
    return res.status(429).json({ error: 'Account locked. Try again later.', code: 'ADMIN_LOCKED' });
  }
  const validKey = !!key && constantTimeEqual(crypto.createHash('sha256').update(input.key).digest('hex'), key.keyHash);
  if (!key || !validKey) {
    if (key) {
      const failedAttempts = (key.failedAttempts ?? 0) + 1;
      await prisma.adminKey.update({
        where: { id: key.id },
        data: {
          failedAttempts,
          lockedUntil: failedAttempts >= ADMIN_LOCKOUT_MAX_ATTEMPTS ? new Date(Date.now() + ADMIN_LOCKOUT_MS) : null,
        },
      });
    } else {
      await registerFailure();
    }
    await recordAuthAuditEvent({ eventType: 'admin_login_failure', actorType: 'admin', actorId: key ? `admin:${key.id}` : undefined, outcome: 'failure', reason: 'invalid_credentials', email: input.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
    return res.status(401).json({ error: 'Invalid administrator credentials' });
  }
  await clearAdminLockout(failureKey);
  await prisma.adminKey.update({
    where: { id: key.id },
    data: { usedAt: new Date(), failedAttempts: 0, lockedUntil: null },
  });
  const { token, expiresIn } = issueAccessToken({
    userId: `admin:${key.id}`,
    email: input.email,
    emailVerified: true,
    tier: 'admin',
    rememberMe: input.rememberMe,
  });
  log('info', 'admin.auth.login', { subject: `admin:${key.id}` });
  await recordAuthAuditEvent({ eventType: 'admin_login_success', actorType: 'admin', actorId: `admin:${key.id}`, outcome: 'success', email: input.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  return res.json({ access_token: token, token_type: 'Bearer', expires_in: expiresIn, email: input.email, role: 'department_admin' });
}));

router.post('/refresh', refreshLimiter, systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const auth = req.auth;
  if (!auth || auth.token_use !== 'admin' || typeof auth.sub !== 'string' || typeof auth.email !== 'string') {
    return res.status(401).json({ error: 'Active administrator session required' });
  }
  const { token, expiresIn } = issueAccessToken({
    userId: auth.sub,
    email: auth.email,
    emailVerified: auth.email_verified === true,
    tier: 'admin',
    rememberMe: auth.remembered === true,
  });
  await recordAuthAuditEvent({ eventType: 'admin_refresh_success', actorType: 'admin', actorId: auth.sub, outcome: 'success', email: auth.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  res.setHeader('cache-control', 'no-store');
  return res.json({ access_token: token, token_type: 'Bearer', expires_in: expiresIn });
}));

router.get('/session', systemAdminMiddleware, (req, res) => res.json({
  email: req.auth?.email,
  role: req.adminAccess?.isSuperAdmin ? 'super_admin' : 'department_admin',
  department: req.adminAccess?.department,
  packages: req.adminAccess?.isSuperAdmin ? adminPackages.map((item) => item.id) : req.adminAccess?.packages ?? [],
  permissions: req.adminAccess?.isSuperAdmin ? permissionOptions : req.adminAccess?.permissions ?? [],
  canRecruit: req.adminAccess?.canRecruit ?? false,
  canMintKeys: req.adminAccess?.canMintKeys ?? false,
  canAssignTasks: req.adminAccess?.canAssignTasks ?? false,
}));

router.post('/ws-ticket', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const isSuperAdmin = req.adminAccess?.isSuperAdmin ?? false;
  const permissions = isSuperAdmin
    ? [...permissionOptions]
    : req.adminAccess?.permissions ?? [];
  const ticket = issueAdminWebSocketTicket({ isSuperAdmin, permissions });
  await recordAuthAuditEvent({ eventType: 'admin_ws_ticket_issued', actorType: 'admin', actorId: typeof req.auth?.sub === 'string' ? req.auth.sub : undefined, outcome: 'success', email: typeof req.auth?.email === 'string' ? req.auth.email : undefined, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  return res.json({ ticket, expiresIn: 30, isSuperAdmin, permissions });
}));

router.get('/access-catalog', systemAdminMiddleware, (req, res) => {
  const access = req.adminAccess;
  return res.json({
    packages: adminPackages,
    permissions: permissionOptions,
    assignablePackageIds: access?.isSuperAdmin ? adminPackages.map((item) => item.id) : access?.packages ?? [],
    assignablePermissions: access?.isSuperAdmin ? permissionOptions : access?.permissions ?? [],
  });
});

router.get('/keys', systemAdminMiddleware, asyncHandler(async (req, res) => {
  const access = req.adminAccess;
  let ids: string[] | undefined;
  if (!access?.isSuperAdmin && access?.keyId) {
    let frontier = [access.keyId];
    ids = [];
    for (let depth = 0; depth < 4 && frontier.length; depth += 1) {
      const children = await prisma.adminKey.findMany({ where: { parentKeyId: { in: frontier } }, select: { id: true, department: true, packages: true } });
      frontier = children
        .filter((child) => isPackageSubset(normalizeAdminPackages(child.packages, child.department), access.packages ?? []))
        .map((child) => child.id);
      ids.push(...frontier);
    }
  }
  const keys = ids && !ids.length ? [] : await prisma.adminKey.findMany({
    where: ids ? { id: { in: ids } } : {},
    select: { id: true, email: true, phone: true, department: true, role: true, packages: true, permissions: true, canRecruit: true, canMintKeys: true, canAssignTasks: true, parentKeyId: true, parent: { select: { id: true, email: true, department: true, role: true } }, createdBy: true, createdAt: true, usedAt: true, expiresAt: true, revokedAt: true },
    orderBy: { createdAt: 'desc' }, take: 500,
  });
  res.json({ keys: keys.map((key) => {
    const packages = normalizeAdminPackages(key.packages, key.department);
    const storedPermissions = Array.isArray(key.permissions) ? key.permissions.filter((permission): permission is string => typeof permission === 'string') : [];
    return { ...key, packages, permissions: effectiveAdminPermissions(packages, storedPermissions) };
  }) });
}));

router.post('/keys/mint', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(mintSchema, req.body);
  const access = req.adminAccess;
  const packages = normalizeAdminPackages(input.packages, input.department);
  const permissions = [...new Set([...adminPackagePermissions(packages), ...input.permissions])];
  if (!access?.isSuperAdmin) {
    const roleRank: Record<string, number> = { worker: 0, manager: 1, department_head: 2, executive: 3 };
    const caller = await prisma.adminKey.findUnique({ where: { id: access?.keyId ?? '' }, select: { role: true } });
    if (!access?.canMintKeys || !access?.canRecruit || input.department !== access.department ||
        roleRank[input.role] >= roleRank[caller?.role ?? 'worker'] ||
        !isPackageSubset(packages, access.packages ?? []) ||
        input.canMintKeys && !access.canMintKeys || input.canRecruit && !access.canRecruit ||
        input.canAssignTasks && !access.canAssignTasks || permissions.some((p: string) => !access.permissions.includes(p))) {
      return res.status(403).json({ error: 'Requested key exceeds your department permissions' });
    }
  }
  const rawKey = crypto.randomBytes(32).toString('base64url');
  const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');
  const expiresAt = new Date(Date.now() + input.expiresInDays * 86400000);
  const keyId = crypto.randomUUID();
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      INSERT INTO admin_keys (
        id, email, phone, key_hash, created_by, created_at, expires_at,
        department, role, packages, permissions, can_recruit, can_mint_keys,
        can_assign_tasks, parent_key_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      keyId,
      input.email,
      input.phone,
      keyHash,
      req.auth?.sub ?? 'unknown',
      new Date().toISOString(),
      expiresAt.toISOString(),
      input.department,
      input.role,
      JSON.stringify(packages),
      JSON.stringify(permissions),
      input.canRecruit ? 1 : 0,
      input.canMintKeys ? 1 : 0,
      input.canAssignTasks ? 1 : 0,
      access?.keyId ?? null,
    ),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_account_invited',
      targetType: 'admin_key',
      targetId: keyId,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Administrator key could not be created');
  const key = {
    id: keyId,
    email: input.email,
    phone: input.phone,
    department: input.department,
    role: input.role,
    packages,
    permissions,
    canRecruit: input.canRecruit,
    canMintKeys: input.canMintKeys,
    canAssignTasks: input.canAssignTasks,
  };
  log('info', 'admin.key.minted', { keyId: key.id, createdBy: req.auth?.sub, department: key.department });
  await recordAuthAuditEvent({ eventType: 'admin_key_minted', actorType: 'admin', actorId: req.auth?.sub ?? undefined, outcome: 'success', email: key.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  res.status(201).json({ key: rawKey, id: key.id, email: key.email, phone: key.phone, department: key.department, role: key.role, packages: key.packages, permissions: key.permissions, canRecruit: key.canRecruit, canMintKeys: key.canMintKeys, canAssignTasks: key.canAssignTasks, expiresAt });
}));

router.patch('/keys/:id', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(keyUpdateSchema, req.body);
  const access = req.adminAccess;
  const target = await prisma.adminKey.findUnique({ where: { id: req.params.id as string } });
  if (!target) return res.status(404).json({ error: 'Administrator key not found' });
  if (!access) return res.status(403).json({ error: 'Administrator access is unavailable' });
  if (!access.isSuperAdmin) {
    const caller = await prisma.adminKey.findUnique({ where: { id: access?.keyId ?? '' }, select: { role: true } });
    const rank: Record<string, number> = { worker: 0, manager: 1, department_head: 2, executive: 3 };
    const nextRole = input.role ?? target.role;
    const existingPackages = normalizeAdminPackages(target.packages, target.department);
    const nextPackages = input.packages ? normalizeAdminPackages(input.packages, target.department) : existingPackages;
    const existingPermissions = Array.isArray(target.permissions) ? target.permissions.filter((p): p is string => typeof p === 'string') : [];
    const existingPackagePermissions = new Set<string>(adminPackagePermissions(existingPackages));
    const existingAdditionalPermissions = existingPermissions.filter((permission) => !existingPackagePermissions.has(permission));
    const nextPermissions = [...new Set([
      ...adminPackagePermissions(nextPackages),
      ...(input.permissions ?? existingAdditionalPermissions),
    ])];
    if (!await isWithinAdminScope(target, access) || target.parentKeyId === null ||
        rank[nextRole] >= rank[caller?.role ?? 'worker'] ||
        !isPackageSubset(nextPackages, access.packages ?? []) ||
        input.canMintKeys === true && !access.canMintKeys ||
        input.canRecruit === true && !access.canRecruit ||
        input.canAssignTasks === true && !access.canAssignTasks ||
        nextPermissions.some((permission) => !access.permissions.includes(permission))) {
      return res.status(403).json({ error: 'Requested access exceeds your department permissions' });
    }
  }
  const changes: string[] = [];
  const bindings: unknown[] = [];
  const existingPackages = normalizeAdminPackages(target.packages, target.department);
  const nextPackages = input.packages ? normalizeAdminPackages(input.packages, target.department) : existingPackages;
  const existingPermissions = Array.isArray(target.permissions) ? target.permissions.filter((p): p is string => typeof p === 'string') : [];
  const existingPackagePermissions = new Set<string>(adminPackagePermissions(existingPackages));
  const existingAdditionalPermissions = existingPermissions.filter((permission) => !existingPackagePermissions.has(permission));
  const nextPermissions = [...new Set([
    ...adminPackagePermissions(nextPackages),
    ...(input.permissions ?? existingAdditionalPermissions),
  ])];
  if (input.packages !== undefined) { changes.push('packages = ?'); bindings.push(JSON.stringify(nextPackages)); }
  if (input.role !== undefined) { changes.push('role = ?'); bindings.push(input.role); }
  if (input.permissions !== undefined || input.packages !== undefined) { changes.push('permissions = ?'); bindings.push(JSON.stringify(nextPermissions)); }
  if (input.canRecruit !== undefined) { changes.push('can_recruit = ?'); bindings.push(input.canRecruit ? 1 : 0); }
  if (input.canMintKeys !== undefined) { changes.push('can_mint_keys = ?'); bindings.push(input.canMintKeys ? 1 : 0); }
  if (input.canAssignTasks !== undefined) { changes.push('can_assign_tasks = ?'); bindings.push(input.canAssignTasks ? 1 : 0); }
  if (input.expiresInDays !== undefined) {
    changes.push('expires_at = ?');
    bindings.push(new Date(Date.now() + input.expiresInDays * 86400000).toISOString());
  }
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`UPDATE admin_keys SET ${changes.join(', ')} WHERE id = ?`).bind(...bindings, target.id),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_access_updated',
      targetType: 'admin_key',
      targetId: target.id,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Administrator key could not be updated');
  const updated = await prisma.adminKey.findUnique({ where: { id: target.id }, select: { id: true, email: true, department: true, role: true, packages: true, permissions: true, canRecruit: true, canMintKeys: true, canAssignTasks: true, expiresAt: true, revokedAt: true } });
  if (!updated) throw new Error('Updated administrator key could not be reloaded');
  log('info', 'admin.key.permissions_updated', { keyId: updated.id, updatedBy: req.auth?.sub });
  await recordAuthAuditEvent({ eventType: 'admin_key_updated', actorType: 'admin', actorId: req.auth?.sub ?? undefined, outcome: 'success', email: updated.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  const updatedPackages = normalizeAdminPackages(updated.packages, updated.department);
  const updatedPermissions = Array.isArray(updated.permissions) ? updated.permissions.filter((permission): permission is string => typeof permission === 'string') : [];
  res.json({ key: { ...updated, packages: updatedPackages, permissions: effectiveAdminPermissions(updatedPackages, updatedPermissions) } });
}));

router.post('/keys/:id/revoke', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const access = req.adminAccess;
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
  const db = getD1DatabaseBinding();
  await db.batch([
    db.prepare(`
      UPDATE admin_keys SET revoked_at = ?
      WHERE revoked_at IS NULL
        AND id IN (SELECT value FROM json_each(?))
    `).bind(revokedAt.toISOString(), JSON.stringify(descendants)),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_access_revoked',
      targetType: 'admin_key',
      targetId: target.id,
    }, db),
  ]);
  const key = { id: target.id, revokedAt };
  log('info', 'admin.key.revoked', { keyId: key.id, revokedBy: req.auth?.sub });
  await recordAuthAuditEvent({ eventType: 'admin_key_revoked', actorType: 'admin', actorId: req.auth?.sub ?? undefined, outcome: 'success', email: target.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  res.json({ key });
}));

router.delete('/keys/:id', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const access = req.adminAccess;
  const target = await prisma.adminKey.findUnique({ where: { id: req.params.id as string } });
  if (!target) return res.status(404).json({ error: 'Administrator key not found' });
  if (!access) return res.status(403).json({ error: 'Administrator access is unavailable' });
  if (!access.isSuperAdmin) {
    if (!(await isWithinAdminScope(target, access))) {
      return res.status(403).json({ error: 'Key is outside your management scope' });
    }
  }
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`DELETE FROM admin_keys WHERE id = ?`).bind(target.id),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_access_deleted',
      targetType: 'admin_key',
      targetId: target.id,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    return res.status(404).json({ error: 'Administrator key not found' });
  }
  log('info', 'admin.key.deleted', { keyId: target.id, deletedBy: req.auth?.sub });
  await recordAuthAuditEvent({ eventType: 'admin_key_deleted', actorType: 'admin', actorId: req.auth?.sub ?? undefined, outcome: 'success', email: target.email, ip: req.ip, requestId: req.requestId, userAgent: req.header('user-agent') || undefined });
  return res.json({ deleted: true, id: target.id, key_id: target.id });
}));

export default router;
