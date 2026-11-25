import { Router, Request } from 'express';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, settingsSchema } from '../lib/validation';
import { taxReportingActivated } from '../services/tax_reporting';
import { z } from 'zod';

const router = Router();
const userDirectoryPageSize = 25;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

router.get('/access', (_req, res) => res.json({ systemAdmin: true }));

router.get('/users', asyncHandler(async (_req: Request, res) => {
  const users = [];
  let cursor: { id: string } | undefined;
  while (true) {
    const page = await prisma.profile.findMany({
      where: { deletedAt: null },
      ...(cursor ? { cursor, skip: 1 } : {}),
      select: { id: true, name: true, role: true, active: true, createdAt: true, user: { select: { email: true } }, tenant: { select: { id: true, shopName: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: userDirectoryPageSize,
    });
    users.push(...page);
    if (page.length < userDirectoryPageSize) break;
    cursor = { id: page[page.length - 1].id };
  }
  res.json({ users });
}));

router.patch('/users/:profileId', asyncHandler(async (req: Request, res) => {
  const input = z.object({ active: z.boolean().optional(), role: z.enum(['admin', 'manager', 'cashier']).optional() })
    .strict().refine((v) => v.active !== undefined || v.role !== undefined).parse(req.body);
  const profileId = req.params.profileId as string;
  const profile = await prisma.profile.findUnique({ where: { id: profileId } });
  if (!profile || profile.deletedAt) return res.status(404).json({ error: 'User not found' });
  const now = new Date().toISOString();
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      UPDATE profiles
      SET active = COALESCE(?, active),
          role = COALESCE(?, role),
          refresh_token_hash = CASE WHEN ? = 1 THEN NULL ELSE refresh_token_hash END,
          refresh_token_previous_hash = CASE WHEN ? = 1 THEN NULL ELSE refresh_token_previous_hash END
      WHERE id = ? AND deleted_at IS NULL
      RETURNING id, tenant_id, name, role, active
    `).bind(
      input.active ?? null,
      input.role ?? null,
      input.active === false ? 1 : 0,
      input.active === false ? 1 : 0,
      profileId,
    ),
    db.prepare(`
      INSERT INTO admin_audit_logs (
        id, admin_id, action, target_type, target_id, tenant_id, "at"
      )
      SELECT ?, ?, 'update_system_user', 'profile', ?, ?, ?
      WHERE changes() = 1
    `).bind(
      globalThis.crypto.randomUUID(),
      req.auth?.sub ?? 'unknown',
      profileId,
      profile.tenantId,
      now,
    ),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) {
    return res.status(404).json({ error: 'User not found' });
  }
  const updated: unknown = results[0]?.results?.[0];
  if (
    !isRecord(updated) ||
    typeof updated.id !== 'string' ||
    typeof updated.tenant_id !== 'string' ||
    typeof updated.name !== 'string' ||
    typeof updated.role !== 'string' ||
    (typeof updated.active !== 'boolean' && typeof updated.active !== 'number')
  ) {
    throw new Error('Updated system user was not returned by D1');
  }
  return res.json({
    user: {
      id: updated.id,
      tenantId: updated.tenant_id,
      name: updated.name,
      role: updated.role,
      active: updated.active === true || updated.active === 1,
    },
  });
}));

router.get('/analytics', asyncHandler(async (_req: Request, res) => {
  const [tenants, activeUsers, sales, products, salesByTenant] = await Promise.all([
    prisma.tenant.count(),
    prisma.profile.count({ where: { active: true, deletedAt: null } }),
    prisma.sale.aggregate({ _count: { _all: true }, _sum: { total: true, profit: true } }),
    prisma.product.count({ where: { active: true } }),
    prisma.sale.groupBy({ by: ['tenantId', 'paymentMethod'], _count: { _all: true }, _sum: { total: true, profit: true } }),
  ]);
  const totalSales = Number(sales._sum.total ?? 0);
  const totalProfit = Number(sales._sum.profit ?? 0);
  const byTenant: Record<string, { salesCount: number; totalSales: number; totalProfit: number; byPaymentMethod: Record<string, number> }> = {};
  for (const sale of salesByTenant) {
    const row = byTenant[sale.tenantId] ??= { salesCount: 0, totalSales: 0, totalProfit: 0, byPaymentMethod: {} };
    row.salesCount += sale._count._all; row.totalSales += Number(sale._sum.total ?? 0); row.totalProfit += Number(sale._sum.profit ?? 0);
    const method = sale.paymentMethod || 'cash';
    row.byPaymentMethod[method] = (row.byPaymentMethod[method] ?? 0) + Number(sale._sum.total ?? 0);
  }
  res.json({ tenants, activeUsers, activeProducts: products, salesCount: sales._count._all, totalSales, totalProfit, byTenant });
}));

router.patch('/tenants/:tenantId/settings', asyncHandler(async (req: Request, res) => {
  const input = parseBody(settingsSchema, req.body);
  const tenantId = req.params.tenantId as string;
  if (input.etimsEnabled === true && !taxReportingActivated()) {
    return res.status(409).json({
      error: 'Tax reporting is not activated yet',
      provider: 'risiti',
      kra_activated: false,
    });
  }
  const tenant = await prisma.tenant.update({ where: { id: tenantId }, data: {
    ...(input.mpesaEnabled !== undefined && { mpesaEnabled: input.mpesaEnabled }),
    ...(input.etimsEnabled !== undefined && { etimsEnabled: input.etimsEnabled }),
    ...(input.payheroChannelId !== undefined && { payheroChannelId: input.payheroChannelId }),
  } });
  await prisma.adminAuditLog.create({ data: { adminId: (req as any).auth?.sub ?? 'unknown', action: 'update_tenant_settings', targetType: 'tenant', targetId: tenantId, tenantId } });
  res.json({ id: tenant.id, mpesaEnabled: tenant.mpesaEnabled, etimsEnabled: tenant.etimsEnabled });
}));

export default router;
