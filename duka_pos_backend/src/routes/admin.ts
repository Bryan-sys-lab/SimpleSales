/**
 * System administration routes.
 *
 * Mounted at /api/admin. Every route is protected by systemAdminMiddleware
 * (OIDC JWT + SYSTEM_ADMIN_SUBJECTS allowlist). A system admin sees ALL tenants.
 */
import { Request, Response, Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { adminAuditSchema, adminListQuerySchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { runRetention } from '../lib/retention';
import { log } from '../lib/observability';
import { systemAdminMiddleware } from '../middleware/auth';

const router = Router();

// All admin routes require a system-admin OIDC subject.
router.use(systemAdminMiddleware);

// ---------------------------------------------------------------------------
// GET /api/admin/dashboard — platform overview
// ---------------------------------------------------------------------------

router.get(
  '/dashboard',
  asyncHandler(async (_req: Request, res: Response) => {
    const [tenantCount, activeUserCount, sales] = await Promise.all([
      prisma.tenant.count(),
      prisma.profile.count({ where: { active: true, deletedAt: null } }),
      prisma.sale.aggregate({ _count: true, _sum: { total: true, profit: true } }),
    ]);
    const churnByRisk = await prisma.churnSnapshot.groupBy({
      by: ['risk'],
      _count: { risk: true },
    });
    const distribution: Record<string, number> = {};
    for (const row of churnByRisk as Array<{ risk: string; _count: { risk: number } }>) {
      distribution[row.risk] = row._count.risk;
    }
    return res.json({
      tenants: tenantCount,
      activeUsers: activeUserCount,
      sales: {
        count: sales._count,
        total: Number(sales._sum.total ?? 0),
        profit: Number(sales._sum.profit ?? 0),
      },
      churnByRisk: distribution,
    });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/churn — churn snapshots across all tenants
// ---------------------------------------------------------------------------

router.get(
  '/churn',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, to, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const where: Record<string, unknown> = {};
    if (tenantId) where.tenantId = tenantId;
    if (from || to) {
      where.date = {};
      if (from) (where.date as Record<string, unknown>).gte = from;
      if (to) (where.date as Record<string, unknown>).lte = to;
    }
    const snapshots = await prisma.churnSnapshot.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { computedAt: 'desc' },
      take: limit,
    });
    return res.json({ snapshots });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/sales — sales across all tenants
// ---------------------------------------------------------------------------

router.get(
  '/sales',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, to, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const toDate = to ? new Date(to) : new Date();
    if (!Number.isFinite(fromDate.getTime()) || !Number.isFinite(toDate.getTime()) || fromDate > toDate) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }
    const where: Record<string, unknown> = { createdAt: { gte: fromDate, lte: toDate } };
    if (tenantId) where.tenantId = tenantId;
    const sales = await prisma.sale.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ sales });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/accounts — the shop accounts across all tenants
// ---------------------------------------------------------------------------

/**
 * Who has access, across every shop on the platform.
 *
 * It used to be a list of app SESSIONS: rows in this service's own table,
 * written when a till signed in here. There is no such table any more, and
 * there should not be — the sessions live in Keycloak, which is where a
 * sign-in belongs, and a service that keeps its own copy of who is signed in
 * is a service with a second answer to "is this person allowed in".
 *
 * What the operator can still be told is the durable half: the accounts that
 * exist, the shop each one runs, the role it holds, and when its address was
 * proven. The live half — who is signed in right now — is Keycloak's to
 * answer.
 */
router.get(
  '/accounts',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, tenantId, limit } = parseBody(adminListQuerySchema, req.query);
    const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    if (!Number.isFinite(fromDate.getTime())) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }
    const where: Record<string, unknown> = { createdAt: { gte: fromDate } };
    if (tenantId) where.tenantId = tenantId;
    const accounts = await prisma.profile.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ accounts });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/tenants — all tenants with profile and sale counts
// ---------------------------------------------------------------------------

router.get(
  '/tenants',
  asyncHandler(async (_req: Request, res: Response) => {
    const tenants = await prisma.tenant.findMany({
      include: { _count: { select: { profiles: true, sales: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return res.json({ tenants });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/support-tickets — support tickets across all tenants
// ---------------------------------------------------------------------------

const supportTicketListQuerySchema = z.object({
  status: z.enum(['open', 'in_progress', 'resolved']).optional().nullable(),
  tenantId: z.string().uuid().optional().nullable(),
  limit: z.coerce.number().int().positive().max(1000).default(100),
});

router.get(
  '/support-tickets',
  asyncHandler(async (req: Request, res: Response) => {
    const { status, tenantId, limit } = parseBody(supportTicketListQuerySchema, req.query);
    const where: Record<string, unknown> = {};
    if (status) where.status = status;
    if (tenantId) where.tenantId = tenantId;
    const tickets = await prisma.supportTicket.findMany({
      where,
      include: { tenant: { select: { id: true, shopName: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return res.json({ tickets });
  })
);

// ---------------------------------------------------------------------------
// GET /api/admin/audit — admin audit log
// POST /api/admin/audit — record an admin action
// ---------------------------------------------------------------------------

router.get(
  '/audit',
  asyncHandler(async (req: Request, res: Response) => {
    const { limit } = parseBody(adminListQuerySchema, req.query);
    const logs = await prisma.adminAuditLog.findMany({
      orderBy: { at: 'desc' },
      take: limit,
    });
    return res.json({ logs });
  })
);

router.post(
  '/audit',
  asyncHandler(async (req: Request, res: Response) => {
    const { action, targetType, targetId, tenantId } = parseBody(adminAuditSchema, req.body);
    if (!req.auth?.sub) {
      return res.status(401).json({ error: 'Authenticated system admin required' });
    }
    const log = await prisma.adminAuditLog.create({
      data: { adminId: req.auth.sub, action, targetType, targetId, tenantId },
    });
    return res.status(201).json(log);
  })
);



// ---------------------------------------------------------------------------
// POST /api/admin/retention/run — purge aged telemetry events (data retention)
// ---------------------------------------------------------------------------

const retentionRunSchema = z.object({
  olderThanDays: z.coerce.number().int().positive().optional().nullable(),
  dryRun: z.coerce.number().int().nonnegative().optional().nullable(),
}).strict();

router.post(
  '/retention/run',
  asyncHandler(async (req: Request, res: Response) => {
    const { olderThanDays, dryRun } = parseBody(retentionRunSchema, req.body);
    if (!req.auth?.sub) {
      return res.status(401).json({ error: 'Authenticated system admin required' });
    }
    const { deletedTelemetryEvents } = await runRetention({
      olderThanDays: olderThanDays ?? undefined,
      dryRun: dryRun ?? undefined,
    });
    await prisma.adminAuditLog.create({
      data: { adminId: req.auth.sub, action: 'purge_telemetry', targetType: 'telemetry_event', tenantId: null },
    });
    log('info', 'admin.purge_telemetry', { adminId: req.auth.sub, deletedTelemetryEvents, olderThanDays, dryRun });
    return res.json({ deletedTelemetryEvents, olderThanDays, dryRun });
  })
);

export default router;
