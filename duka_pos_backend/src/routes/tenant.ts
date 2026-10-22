import { Router, Request, Response } from 'express';
import { requireOwner, requireRole } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, provisionSchema, settingsSchema, staffSyncSchema, deletionSchema, staffAuthenticateSchema } from '../lib/validation';
import { isVerifiedEmailMatch } from '../lib/identity';
import { readPortfolio } from '../lib/portfolio_query';
import { announceChange } from '../lib/live';

const router = Router();

// Provision tenant (first-time setup)
router.post('/provision', asyncHandler(async (req: Request, res: Response) => {
    const { shopName, ownerName, email } = parseBody(provisionSchema, req.body);
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) return res.status(401).json({ error: 'Authenticated user required' });
    if (!isVerifiedEmailMatch(req.auth, email)) {
      return res.status(403).json({ error: 'The verified Keycloak email must match the account email' });
    }

    const existingShop = await prisma.profile.findFirst({ where: { oidcSubject: oidcUserId, tenant: { shopName: shopName.trim() } } });
    if (existingShop) return res.status(409).json({ error: 'This account is already linked to this shop', tenant_id: existingShop.tenantId });

    // Create tenant and owner profile in transaction
    const result = await prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({
        data: { shopName: shopName.trim() }
      });

      const profile = await tx.profile.create({
        data: {
          oidcSubject: oidcUserId,
          tenantId: tenant.id,
          name: ownerName.trim(),
          email,
          role: 'admin'
        }
      });

      return { tenant, profile };
    });

    res.json({ tenant_id: result.tenant.id });
}));

router.get('/shops', asyncHandler(async (req: Request, res: Response) => {
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) return res.status(401).json({ error: 'Authenticated user required' });
    const profiles = await prisma.profile.findMany({ where: { oidcSubject: oidcUserId, active: true, deletedAt: null }, include: { tenant: true }, orderBy: { createdAt: 'asc' } });
    res.json({ shops: profiles.map((profile) => ({ tenantId: profile.tenantId, shopName: profile.tenant.shopName, role: profile.role })) });
}));

// ---------------------------------------------------------------------------
// Staff sign-in check
// ---------------------------------------------------------------------------

/**
 * Confirms that a member of staff may work in this shop.
 *
 * The till has already verified the PIN against its own copy of the staff
 * row; this asks the server whether that person is still active in this
 * shop, which is the question a till that has been offline for a week cannot
 * answer for itself.
 *
 * The PIN is NOT sent and NOT checked here. It is a device-bound unlock
 * credential, it never leaves the phone, and the server has no copy of it to
 * check it against.
 */
router.post('/staff/authenticate', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const { username, pin } = parseBody(staffAuthenticateSchema, req.body);

  const profile = await prisma.profile.findFirst({
    where: {
      tenantId: req.user!.tenantId,
      name: username,
      role: { in: ['cashier', 'manager'] },
      active: true,
      deletedAt: null,
    },
  });
  if (!profile) {
    return res.status(401).json({ error: 'Staff not found or inactive' });
  }

  return res.json({
    staff_id: profile.id,
    local_id: profile.localId ?? null,
    name: profile.name,
    role: profile.role,
    tenant_id: profile.tenantId,
  });
}));

// ---------------------------------------------------------------------------
// Cross-shop KPI roll-up: how every shop the caller RUNS is doing, in one body.
//
// An owner with two dukas needs one screen that answers "how are all my shops
// doing", and that is a question no single tenant can answer — `/report/sales`
// is scoped to `req.user.tenantId`, so asking it twice still gives two bodies to
// combine on a phone that is often offline when it needs the answer most.
//
// Three properties this must not break, in order of how badly they break:
//
//   1. LEAKS NOTHING. The tenant list is the caller's OWN profiles. It is never
//      derived from the request body, a query parameter, or the target header,
//      any of which would let one customer enumerate another's tenants by
//      guessing ids.
//   2. A CASHIER GETS NOTHING. `role: 'admin' | 'manager'` is the ownership
//      predicate, applied in the SAME query that scopes the tenants — a
//      separate role check afterwards would be a second gate that has to stay
//      in step with this one. A cashier's request therefore resolves to an
//      empty shop list and a zeroed total, not a 403 the client has to
//      interpret.
//   3. STAYS BOUNDED. One aggregate query per shop, capped at MAX_PORTFOLIO_SHOPS,
//      with `truncated` set when the cap is hit. An owner with 200 shops is
//      served a partial answer that says so, rather than 200 queries and a
//      timeout.
//
// The totals are computed in SQL (`groupBy`/`aggregate`), not by summing
// hydrated rows in Node: the cost is the same however long each shop's ledger
// grows, which is the same reason `/report/sales` does it that way.
router.get('/portfolio', requireRole('admin', 'manager'), asyncHandler(async (req: Request, res: Response) => {
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) return res.status(401).json({ error: 'Authenticated user required' });

    const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }

    const reading = await readPortfolio(req.auth?.sub, { from, to });
    if (reading.truncated) {
      // Deliberately not an error: an owner with more shops than the cap gets
      // the ones they set up first and a flag saying the rest are missing.
      res.setHeader('X-Portfolio-Truncated', 'true');
    }

    // The whole comes back with the parts, so a screen does not have to add
    // them and risk disagreeing with them — see lib/portfolio.ts.
    res.json({
      from: from.toISOString(),
      to: to.toISOString(),
      shops: reading.shops,
      total: reading.total,
    });
}));

// Get tenant settings
router.get('/settings', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
    const tenant = await prisma.tenant.findUnique({
      where: { id: req.user!.tenantId },
      select: {
        id: true,
        shopName: true,
        mpesaEnabled: true,
        etimsEnabled: true,
        payheroChannelId: true
      }
    });

    // A platform-wide signal: settings change for every till in the shop, and
    // the reason carries no tenant list, so every stream in this shop is told.
    announceChange([], 'settings');
    res.json(tenant);
}));

// Update tenant settings (owner only)
router.patch('/settings', requireOwner, asyncHandler(async (req: Request, res: Response) => {
    const { mpesaEnabled, etimsEnabled, payheroChannelId } = parseBody(settingsSchema, req.body);

    const tenant = await prisma.tenant.update({
      where: { id: req.user!.tenantId },
      data: {
        ...(mpesaEnabled !== undefined && { mpesaEnabled }),
        ...(etimsEnabled !== undefined && { etimsEnabled }),
        ...(payheroChannelId !== undefined && { payheroChannelId })
      }
    });

    res.json(tenant);
}));

// Create/update local cashier profiles (owner only). A localId makes this
// idempotent when the till reconnects after creating staff while offline.
router.post('/staff/sync', requireOwner, asyncHandler(async (req: Request, res: Response) => {
    const { staff } = parseBody(staffSyncSchema, req.body);
    const tenantId = req.user!.tenantId;
    // Resolve every existing profile for the batch in one query. The till sends
    // up to 500 staff on every auto-sync, and a lookup per item turned that
    // into up to 1,000 sequential round-trips inside a single transaction.
    const remoteIds = staff
      .map((item) => item.remoteId)
      .filter((id): id is string => typeof id === 'string' && id.length > 0);
    const localIds = staff.map((item) => item.localId);

    const existingProfiles = await prisma.profile.findMany({
      where: {
        tenantId,
        role: { in: ['cashier', 'manager'] },
        OR: [
          ...(remoteIds.length ? [{ id: { in: remoteIds } }] : []),
          ...(localIds.length ? [{ localId: { in: localIds } }] : []),
        ],
      },
      select: { id: true, localId: true },
    });
    const byRemoteId = new Map(existingProfiles.map((p) => [p.id, p]));
    const byLocalId = new Map(
      existingProfiles.filter((p) => p.localId != null).map((p) => [p.localId as number, p]),
    );

    const synced = await prisma.$transaction(async (tx) => {
      const result: Array<{ localId: number; remoteId: string }> = [];
      for (const item of staff) {
        const existing =
          (item.remoteId ? byRemoteId.get(item.remoteId) : undefined) ??
          byLocalId.get(item.localId);
        const profile = existing
          ? await tx.profile.update({ where: { id: existing.id }, data: { name: item.name, active: item.active } })
          : await tx.profile.create({ data: { tenantId, localId: item.localId, name: item.name, role: item.role, active: item.active } });
        result.push({ localId: item.localId, remoteId: profile.id });
      }
      return result;
    });
    res.json({ synced });
}));

// Delete a cashier's identity data while preserving an auditable financial
// ledger. Sales remain for accounting, but personal staff labels are replaced
// and the profile is retained only as a tombstone for referential integrity.
router.delete('/staff/:profileId', requireOwner, asyncHandler(async (req: Request, res: Response) => {
    const { reason } = parseBody(deletionSchema, req.body ?? {});
    const profile = await prisma.profile.findFirst({
      where: { id: req.params.profileId, tenantId: req.user!.tenantId, role: { in: ['cashier', 'manager'] } },
    });
    if (!profile) return res.status(404).json({ error: 'Staff profile not found' });

    const deletedLabel = 'Deleted cashier';
    await prisma.$transaction(async (tx) => {
      await tx.deletionLedger.create({
        data: {
          tenantId: req.user!.tenantId,
          subjectType: 'staff_profile',
          subjectId: profile.id,
          reason,
          completedAt: new Date(),
        },
      });
      await tx.profile.update({
        where: { id: profile.id },
        data: { name: deletedLabel, active: false, deletedAt: new Date() },
      });
      await tx.sale.updateMany({ where: { tenantId: req.user!.tenantId, staffId: profile.id }, data: { staffName: deletedLabel } });
      await tx.stockAdjustment.updateMany({ where: { tenantId: req.user!.tenantId, staffId: profile.id }, data: { staffId: profile.id } });
      await tx.payment.updateMany({ where: { tenantId: req.user!.tenantId, initiatedBy: profile.id }, data: { staffName: deletedLabel } });
    });
    res.json({ deleted: true, profile_id: profile.id });
}));

export default router;
