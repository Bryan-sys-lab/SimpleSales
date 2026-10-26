import { Router, Request } from 'express';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, settingsSchema } from '../lib/validation';
import { taxReportingActivated } from '../services/tax_reporting';

const router = Router();

router.get('/access', (_req, res) => res.json({ systemAdmin: true }));

router.get('/users', asyncHandler(async (_req: Request, res) => {
  const users = await prisma.profile.findMany({
    where: { active: true, deletedAt: null },
    select: { id: true, name: true, role: true, createdAt: true, tenant: { select: { id: true, shopName: true } } },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ users });
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
