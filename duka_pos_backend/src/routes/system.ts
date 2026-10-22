// The admin API: everything an operator, and a script, needs about the platform.
//
// ## What this surface is for
//
// Two audiences, and the shape serves both. An operator needs to see which
// shops are selling, which are not, and why a till keeps failing. A script —
// a health check, a nightly report, an agent taking a question from a shop —
// needs stable JSON keys and no surprises. Where the two disagree, the response
// shape wins, which is why everything here is a function returning a plain
// object with snake_case keys.
//
// ## The security model
//
// This is platform administration, not shop administration: an operator here
// can read every shop's numbers, because answering "is anything wrong
// anywhere?" is the whole job. That is enforced by `systemAdminMiddleware`,
// which accepts only OIDC subjects on an explicit allowlist — never an app
// session, never a tenant token. The routes below therefore do not need to
// re-check that the caller is a platform admin; they DO still need to bound
// their queries, because an operator is one bad request away from loading
// every sale in the platform into memory.
//
// ## Why no endpoint here carries a raw date range without a default
//
// An unbounded `from` is a query that grows forever. Every read here applies
// the same bounded window the portfolio endpoint uses, so an operator asking
// for "everything" gets the last thirty days and a flag saying they did.

import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { prisma } from '../lib/prisma.js';
import { asyncHandler } from '../lib/http.js';
import { parseBody, settingsSchema, staffActiveSchema } from '../lib/validation.js';
import { routeParam } from '../lib/http';
import {
  buildDrilldown,
  defaultDrilldownWindow,
  isWindowUsable,
  type SaleRow,
} from '../lib/admin_analytics.js';

const router = Router();

/**
 * The widest window any read here covers.
 *
 * 400 days: enough for a year-on-year comparison, short enough that the
 * aggregate queries stay bounded on a platform with years of sales. A caller
 * asking for more gets the fence and a `window_truncated` flag.
 */
const MAX_WINDOW_DAYS = 400;

/** The most rows a single read returns, period. */
const MAX_ROWS = 2000;

/**
 * Bounds a requested window, and says so when it does.
 *
 * The flag rather than an error, because an operator exploring a dashboard
 * should not be told off for asking for a range the platform will not serve —
 * they should be told the range they are looking at.
 */
function boundWindow(from: unknown, to: unknown): { from: Date; to: Date; truncated: boolean } {
  const now = new Date();
  const fallback = defaultDrilldownWindow(now);
  const requestedFrom = typeof from === 'string' ? new Date(from) : fallback.from;
  const requestedTo = typeof to === 'string' ? new Date(to) : fallback.to;
  const first = Number.isNaN(requestedFrom.getTime()) ? fallback.from : requestedFrom;
  const last = Number.isNaN(requestedTo.getTime()) ? fallback.to : requestedTo;

  const floor = new Date(now.getTime() - MAX_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const boundedFrom = first < floor ? floor : first;
  const boundedTo = last > now ? now : last;
  return {
    from: boundedFrom,
    to: boundedTo < boundedFrom ? boundedFrom : boundedTo,
    truncated: boundedFrom.getTime() !== first.getTime() || boundedTo.getTime() !== last.getTime(),
  };
}

/**
 * Reads the sales a drill-down needs, bounded and projected.
 *
 * Only the columns the dashboard reads, never a hydrated relation: a dashboard
 * that pulls whole sale rows to display four numbers is a dashboard that loads
 * the platform into memory to draw a chart.
 */
async function readSales(tenantId: string | undefined, from: Date, to: Date): Promise<SaleRow[]> {
  const rows = await prisma.sale.findMany({
    where: {
      createdAt: { gte: from, lte: to },
      ...(tenantId ? { tenantId } : {}),
    },
    select: {
      tenantId: true,
      createdAt: true,
      total: true,
      profit: true,
      paymentMethod: true,
      staffId: true,
      staffName: true,
      tenant: { select: { shopName: true } },
    },
    orderBy: { createdAt: 'asc' },
    take: MAX_ROWS,
  });
  return rows.map((row) => ({
    tenantId: row.tenantId,
    tenantName: row.tenant.shopName,
    createdAt: row.createdAt,
    total: Number(row.total),
    profit: Number(row.profit),
    paymentMethod: row.paymentMethod,
    staffId: row.staffId,
    staffName: row.staffName,
  }));
}

// A bounded rate for the analytics reads: every one of them is several
// aggregates, and an operator with a stuck browser tab should not be able to
// run a thousand of them.
const analyticsLimiter = rateLimit({
  windowMs: 60_000,
  limit: 60,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

router.get('/access', (_req, res) => res.json({ systemAdmin: true }));

/**
 * Who is on the platform.
 *
 * `active: true` and no tombstone, paged and bounded. Deactivated rows are
 * omitted rather than marked, because a deactivated staff member is not
 * "a user who is off" — their account is gone, and showing it invites an
 * operator to try to re-enable it.
 */
router.get('/users', asyncHandler(async (req: Request, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, MAX_ROWS);
  const offset = Math.max(Number(req.query.offset) || 0, 0);
  const [users, total] = await Promise.all([
    prisma.profile.findMany({
      where: { active: true, deletedAt: null },
      select: {
        id: true,
        name: true,
        role: true,
        email: true,
        createdAt: true,
        emailVerifiedAt: true,
        tenant: { select: { id: true, shopName: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
      skip: offset,
    }),
    prisma.profile.count({ where: { active: true, deletedAt: null } }),
  ]);
  res.json({
    users: users.map((user) => ({
      id: user.id,
      name: user.name,
      role: user.role,
      // The masked form the till sees, never the raw address: an operator
      // reading a support ticket does not need a customer's inbox.
      email: user.email,
      shop: user.tenant.shopName,
      tenant_id: user.tenant.id,
      email_verified: user.emailVerifiedAt != null,
      joined_at: user.createdAt.toISOString(),
    })),
    total,
    limit,
    offset,
  });
}));

/**
 * Platform totals: the number an operator checks first.
 *
 * The same five aggregates as before, plus the window flag, plus every
 * count the dashboard's header needs so it does not make six calls to draw
 * one screen.
 */
router.get('/analytics', analyticsLimiter, asyncHandler(async (req: Request, res) => {
  const window = boundWindow(req.query.from, req.query.to);
  const [tenants, activeUsers, sales, products, salesByTenant] = await Promise.all([
    prisma.tenant.count(),
    prisma.profile.count({ where: { active: true, deletedAt: null } }),
    prisma.sale.aggregate({
      where: { createdAt: { gte: window.from, lte: window.to } },
      _count: { _all: true },
      _sum: { total: true, profit: true },
    }),
    prisma.product.count({ where: { active: true } }),
    prisma.sale.groupBy({
      by: ['tenantId', 'paymentMethod'],
      where: { createdAt: { gte: window.from, lte: window.to } },
      _count: { _all: true },
      _sum: { total: true, profit: true },
      // `take` without `orderBy` is refused by Prisma, so the page is ordered
      // by turnover — the largest earner first, which is the order an operator
      // reads a platform's shops in anyway.
      orderBy: { _sum: { total: 'desc' } },
      take: MAX_ROWS,
    }),
  ]);
  const salesRows: SaleRow[] = salesByTenant.map((row) => ({
    tenantId: row.tenantId,
    createdAt: window.from,
    total: Number(row._sum.total ?? 0),
    profit: Number(row._sum.profit ?? 0),
    paymentMethod: row.paymentMethod,
  }));
  const byTenant: Record<string, { salesCount: number; totalSales: number; totalProfit: number; byPaymentMethod: Record<string, number> }> = {};
  for (const sale of salesRows) {
    const row = byTenant[sale.tenantId] ??= { salesCount: 0, totalSales: 0, totalProfit: 0, byPaymentMethod: {} };
    row.salesCount += 1;
    row.totalSales += sale.total;
    row.totalProfit += sale.profit;
    const method = (sale.paymentMethod || 'cash').toLowerCase();
    row.byPaymentMethod[method] = (row.byPaymentMethod[method] ?? 0) + sale.total;
  }

  res.json({
    from: window.from.toISOString(),
    to: window.to.toISOString(),
    window_truncated: window.truncated,
    tenants,
    activeUsers,
    activeProducts: products,
    salesCount: sales._count._all,
    totalSales: Number(sales._sum.total ?? 0),
    totalProfit: Number(sales._sum.profit ?? 0),
    byTenant,
  });
}));

/**
 * The drill-down: per-day series, tender mix, staff and per shop.
 *
 * `tenant_id` narrows it to one shop, which is the question a support ticket
 * actually asks — "what did this shop sell last week".
 */
router.get('/analytics/drilldown', analyticsLimiter, asyncHandler(async (req: Request, res) => {
  const window = boundWindow(req.query.from, req.query.to);
  const tenantId = typeof req.query.tenant_id === 'string' && req.query.tenant_id ? req.query.tenant_id : undefined;
  if (tenantId) {
    const tenant = await prisma.tenant.findUnique({ where: { id: tenantId }, select: { id: true } });
    if (!tenant) return res.status(404).json({ error: 'No such shop', code: 'TENANT_NOT_FOUND' });
  }
  const sales = await readSales(tenantId, window.from, window.to);
  const drilldown = buildDrilldown(sales, { from: window.from, to: window.to });
  res.json({
    ...drilldown,
    window_truncated: window.truncated,
    rows_read: sales.length,
    rows_capped: sales.length >= MAX_ROWS,
  });
}));

/**
 * One shop's settings, read.
 *
 * Separate from the write because the two have different failure modes: a
 * read that 404s means "the shop is gone", while a write that 404s means "you
 * are about to create a shop by typing its id into a text box".
 */
router.get('/tenants/:tenantId/settings', asyncHandler(async (req: Request, res) => {
  const tenant = await prisma.tenant.findUnique({
    where: { id: routeParam(req.params.tenantId) },
    select: { id: true, shopName: true, mpesaEnabled: true, etimsEnabled: true, payheroChannelId: true },
  });
  if (!tenant) return res.status(404).json({ error: 'No such shop', code: 'TENANT_NOT_FOUND' });
  res.json({
    id: tenant.id,
    shop_name: tenant.shopName,
    mpesaEnabled: tenant.mpesaEnabled,
    etimsEnabled: tenant.etimsEnabled,
    payheroChannelId: tenant.payheroChannelId,
  });
}));

router.patch('/tenants/:tenantId/settings', asyncHandler(async (req: Request, res) => {
  const input = parseBody(settingsSchema, req.body);
  const existing = await prisma.tenant.findUnique({ where: { id: routeParam(req.params.tenantId) }, select: { id: true } });
  if (!existing) return res.status(404).json({ error: 'No such shop', code: 'TENANT_NOT_FOUND' });
  // A write that changes nothing must not claim it did: an empty payload is
  // rejected rather than silently becoming a no-op that returns success.
  if (Object.keys(req.body ?? {}).length === 0) {
    return res.status(400).json({ error: 'Nothing to change', code: 'EMPTY_UPDATE' });
  }
  const tenant = await prisma.tenant.update({ where: { id: routeParam(req.params.tenantId) }, data: {
    ...(input.mpesaEnabled !== undefined && { mpesaEnabled: input.mpesaEnabled }),
    ...(input.etimsEnabled !== undefined && { etimsEnabled: input.etimsEnabled }),
    ...(input.payheroChannelId !== undefined && { payheroChannelId: input.payheroChannelId }),
  } });
  res.json({ id: tenant.id, mpesaEnabled: tenant.mpesaEnabled, etimsEnabled: tenant.etimsEnabled });
}));

/**
 * Toggles a staff member, or deletes them with a tombstone.
 *
 * Deletion deliberately goes through the same anonymising path the till uses,
 * not a Prisma `delete`: a staff row that vanishes leaves audit rows naming
 * a display name, which is the leak the tombstone exists to prevent.
 */
router.patch('/users/:profileId/active', asyncHandler(async (req: Request, res) => {
  const { active } = parseBody(staffActiveSchema, req.body);
  const profile = await prisma.profile.findFirst({
    where: { id: routeParam(req.params.profileId), deletedAt: null },
    select: { id: true },
  });
  if (!profile) return res.status(404).json({ error: 'No such user', code: 'PROFILE_NOT_FOUND' });
  const updated = await prisma.profile.update({
    where: { id: routeParam(req.params.profileId) },
    data: { active },
  });
  res.json({ id: updated.id, active: updated.active });
}));

/**
 * Observability: is anything wrong anywhere, right now.
 *
 * The counts an operator polls, and the last few verification attempts — a
 * spike in rejections is the signal that a shop's email is failing before
 * anyone notices they never got a code.
 */
router.get('/observability', analyticsLimiter, asyncHandler(async (_req: Request, res) => {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [tenants, profiles, pendingVerifications, burntCodes, recentCodes] = await Promise.all([
    prisma.tenant.count(),
    prisma.profile.count({ where: { active: true, deletedAt: null } }),
    prisma.emailVerification.count({ where: { consumedAt: null, expiresAt: { gt: new Date() } } }),
    prisma.emailVerification.count({ where: { consumedAt: { not: null }, createdAt: { gte: since }, attempts: { gte: 5 } } }),
    prisma.emailVerification.findMany({
      where: { createdAt: { gte: since } },
      select: { email: true, attempts: true, consumedAt: true, expiresAt: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 20,
    }),
  ]);
  res.json({
    generated_at: new Date().toISOString(),
    window: { from: since.toISOString(), to: new Date().toISOString() },
    tenants,
    activeUsers: profiles,
    verification: {
      pending: pendingVerifications,
      burnt_last_24h: burntCodes,
      sent_last_24h: recentCodes.length,
      recent: recentCodes.map((row) => ({
        // Masked at the response, because an operator does not need the inbox
        // to know that a code went out and was not used.
        email: row.email.replace(/^(.).*(@.*)$/, '$1***$2'),
        attempts: row.attempts,
        used: row.consumedAt != null,
        expired: row.expiresAt.getTime() <= Date.now(),
        at: row.createdAt.toISOString(),
      })),
    },
  });
}));

export default router;
