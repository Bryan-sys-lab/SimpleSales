import { Router, Request } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, settingsSchema } from '../lib/validation';
import { taxReportingActivated } from '../services/tax_reporting';
import { z } from 'zod';

const router = Router();

router.get('/access', (_req, res) => res.json({ systemAdmin: true }));

router.get('/users', asyncHandler(async (_req: Request, res) => {
  const users = await prisma.profile.findMany({
    where: { deletedAt: null },
    select: { id: true, name: true, role: true, active: true, createdAt: true, tenant: { select: { id: true, shopName: true } } },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ users });
}));

// System-admin user control for correcting access without impersonating a
// shop owner. Every change is attributable in the platform audit log.
router.patch('/users/:profileId', asyncHandler(async (req: Request, res) => {
  const input = z.object({
    active: z.boolean().optional(),
    role: z.enum(['admin', 'manager', 'cashier']).optional(),
  }).strict().refine((value) => value.active !== undefined || value.role !== undefined)
    .parse(req.body);
  const profileId = req.params.profileId as string;
  const profile = await prisma.profile.findUnique({ where: { id: profileId } });
  if (!profile || profile.deletedAt) return res.status(404).json({ error: 'User not found' });
  const updated = await prisma.$transaction(async (tx) => {
    const row = await tx.profile.update({
      where: { id: profileId },
      data: {
        ...(input.active !== undefined ? { active: input.active } : {}),
        ...(input.role !== undefined ? { role: input.role } : {}),
        ...(input.active === false ? { refreshTokenHash: null, refreshTokenPreviousHash: null } : {}),
      },
      select: { id: true, tenantId: true, name: true, role: true, active: true },
    });
    await tx.adminAuditLog.create({
      data: {
        adminId: req.auth?.sub ?? 'unknown',
        action: 'update_system_user',
        targetType: 'profile',
        targetId: profileId,
        tenantId: profile.tenantId,
      },
    });
    return row;
  });
  return res.json({ user: updated });
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
  res.json({ id: tenant.id, mpesaEnabled: tenant.mpesaEnabled, etimsEnabled: tenant.etimsEnabled });
}));

export default router;
