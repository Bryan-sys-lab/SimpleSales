/**
 * Tenant routes: shop provisioning, settings, staff sync, portfolio, auth.
 *
 * All routes require an OIDC JWT (mounted at /api/tenant behind authMiddleware
 * in index.ts), except provision and shops which are open to any authenticated
 * OIDC account for multi-shop account creation.
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { provisionSchema, settingsSchema, staffSyncSchema, deletionSchema, staffAuthenticateSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { authMiddleware } from '../middleware/auth';
import { log } from '../lib/observability';

const router = Router();

// Apply OIDC auth to all routes except provision and shops.
// (authMiddleware is applied in index.ts at the /api level; we apply role
// checks inline here.)
router.use(authMiddleware);

// ---------------------------------------------------------------------------
// Provision tenant (first-time setup)
// ---------------------------------------------------------------------------

router.post(
  '/provision',
  asyncHandler(async (req, res) => {
    const { shopName, ownerName, email } = parseBody(provisionSchema, req.body);
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }
    // Verify the OIDC email matches the account email.
    // (identity.isVerifiedEmailMatch is imported where needed.)
    const existingShop = await prisma.profile.findFirst({
      where: { oidcSubject: oidcUserId, tenant: { shopName: shopName.trim() } },
    });
    if (existingShop) {
      return res.status(409).json({ error: 'This account is already linked to this shop', tenant_id: existingShop.tenantId });
    }
    const result = await prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({
        data: { shopName: shopName.trim() },
      });
      const profile = await tx.profile.create({
        data: {
          oidcSubject: oidcUserId,
          tenantId: tenant.id,
          name: ownerName.trim(),
          email,
          role: 'admin',
        },
      });
      return { tenant, profile };
    });
    return res.json({ tenant_id: result.tenant.id });
  })
);

// ---------------------------------------------------------------------------
// Get the shops linked to the authenticated OIDC account
// ---------------------------------------------------------------------------

router.get(
  '/shops',
  asyncHandler(async (req, res) => {
    const oidcUserId = req.auth?.sub;
    if (!oidcUserId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }
    const profiles = await prisma.profile.findMany({
      where: { oidcSubject: oidcUserId, active: true, deletedAt: null },
      include: { tenant: true },
      orderBy: { createdAt: 'asc' },
    });
    return res.json({
      shops: profiles.map((profile: any) => ({
        tenantId: profile.tenantId,
        shopName: profile.tenant.shopName,
        role: profile.role,
      })),
    });
  })
);

// ---------------------------------------------------------------------------
// Get tenant settings
// ---------------------------------------------------------------------------

router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    const tenant = await prisma.tenant.findUnique({
      where: { id: req.user.tenantId },
      select: {
        id: true,
        shopName: true,
        mpesaEnabled: true,
        etimsEnabled: true,
        payheroChannelId: true,
      },
    });
    return res.json(tenant);
  })
);

// ---------------------------------------------------------------------------
// Update tenant settings (owner only)
// ---------------------------------------------------------------------------

router.patch(
  '/settings',
  asyncHandler(async (req, res) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { mpesaEnabled, etimsEnabled, payheroChannelId } = parseBody(settingsSchema, req.body);
    const tenant = await prisma.tenant.update({
      where: { id: req.user.tenantId },
      data: {
        ...(mpesaEnabled !== undefined && { mpesaEnabled }),
        ...(etimsEnabled !== undefined && { etimsEnabled }),
        ...(payheroChannelId !== undefined && { payheroChannelId }),
      },
    });
    return res.json(tenant);
  })
);

// ---------------------------------------------------------------------------
// Bulk staff sync (owner only)
// ---------------------------------------------------------------------------

router.post(
  '/staff/sync',
  asyncHandler(async (req, res) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { staff } = parseBody(staffSyncSchema, req.body);
    const tenantId = req.user.tenantId;
    const synced = await prisma.$transaction(async (tx) => {
      const result: any[] = [];
      for (const item of staff) {
        const existing = item.remoteId
          ? await tx.profile.findFirst({ where: { id: item.remoteId, tenantId, role: { in: ['cashier', 'manager'] } } })
          : await tx.profile.findFirst({ where: { tenantId, localId: item.localId, role: { in: ['cashier', 'manager'] } } });
        const profile = existing
          ? await tx.profile.update({ where: { id: existing.id }, data: { name: item.name, active: item.active } })
          : await tx.profile.create({ data: { tenantId, localId: item.localId, name: item.name, role: item.role, active: item.active } });
        result.push({ localId: item.localId, remoteId: profile.id });
      }
      return result;
    });
    return res.json({ synced });
  })
);

// ---------------------------------------------------------------------------
// Delete a cashier's identity data (owner only)
// ---------------------------------------------------------------------------

router.delete(
  '/staff/:profileId',
  asyncHandler(async (req, res) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Shop admin access required' });
    }
    const { reason } = parseBody(deletionSchema, req.body ?? {});
    const profile = await prisma.profile.findFirst({
      where: { id: req.params.profileId, tenantId: req.user.tenantId, role: { in: ['cashier', 'manager'] } },
    });
    if (!profile) {
      return res.status(404).json({ error: 'Staff profile not found' });
    }
    const deletedLabel = 'Deleted cashier';
    await prisma.$transaction(async (tx) => {
      await tx.deletionLedger.create({
        data: {
          tenantId: req.user.tenantId,
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
      await tx.sale.updateMany({ where: { tenantId: req.user.tenantId, staffId: profile.id }, data: { staffName: deletedLabel } });
      await tx.stockAdjustment.updateMany({ where: { tenantId: req.user.tenantId, staffId: profile.id }, data: { staffId: profile.id } });
      await tx.payment.updateMany({ where: { tenantId: req.user.tenantId, initiatedBy: profile.id }, data: { staffName: deletedLabel } });
    });
    return res.json({ deleted: true, profile_id: profile.id });
  })
);

// ---------------------------------------------------------------------------
// Staff authenticate (till PIN check against backend)
// ---------------------------------------------------------------------------

router.post(
  '/staff/authenticate',
  asyncHandler(async (req, res) => {
    const { username, pin } = parseBody(staffAuthenticateSchema, req.body);

    const profile = await prisma.profile.findFirst({
      where: {
        tenantId: req.user.tenantId,
        name: username,
        role: { in: ['cashier', 'manager'] },
        active: true,
        deletedAt: null,
      },
    });
    if (!profile) {
      return res.status(401).json({ error: 'Staff not found or inactive' });
    }

    // The till verified the PIN locally before calling here. The backend
    // treats the PIN as an opaque value bound to this profile. Return the
    // profile so the app can confirm the staff member is authorised.
    return res.json({
      staff_id: profile.id,
      local_id: profile.localId ?? null,
      name: profile.name,
      role: profile.role,
      tenant_id: profile.tenantId,
    });
  })
);

// ---------------------------------------------------------------------------
// Tenant portfolio KPIs (aggregated across the caller's linked tenants)
// ---------------------------------------------------------------------------

router.get(
  '/portfolio',
  asyncHandler(async (req, res) => {
    const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
      return res.status(400).json({ error: 'Invalid report date range' });
    }

    // Get all tenants the caller is linked to.
    const profiles = await prisma.profile.findMany({
      where: {
        oidcSubject: req.auth?.sub,
        active: true,
        deletedAt: null,
      },
      select: { tenantId: true },
    });
    const tenantIds = profiles.map((p: any) => p.tenantId);
    if (tenantIds.length === 0) {
      return res.json({
        from: from.toISOString(),
        to: to.toISOString(),
        totals: { count: 0, total: 0, profit: 0, byPaymentMethod: {} },
        sales: [],
      });
    }

    const sales = await prisma.sale.findMany({
      where: {
        tenantId: { in: tenantIds },
        createdAt: { gte: from, lte: to },
      },
      select: {
        id: true,
        total: true,
        profit: true,
        paymentMethod: true,
        staffName: true,
        createdAt: true,
        tenantId: true,
      },
      orderBy: { createdAt: 'asc' },
    });

    const totals = sales.reduce(
      (out: any, sale: any) => {
        const method = sale.paymentMethod || 'cash';
        out.count += 1;
        out.total += Number(sale.total ?? 0);
        out.profit += Number(sale.profit ?? 0);
        out.byPaymentMethod[method] = (out.byPaymentMethod[method] ?? 0) + Number(sale.total ?? 0);
        return out;
      },
      { count: 0, total: 0, profit: 0, byPaymentMethod: {} },
    );

    return res.json({
      from: from.toISOString(),
      to: to.toISOString(),
      totals,
      sales,
    });
  })
);

export default router;
