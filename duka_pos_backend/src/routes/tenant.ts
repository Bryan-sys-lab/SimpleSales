import { Router, Request, Response } from 'express';
import { requireOwner, requireRole } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { asyncHandler } from '../lib/http';
import { parseBody, provisionSchema, settingsSchema, staffSyncSchema, deletionSchema } from '../lib/validation';
import { isVerifiedEmailMatch } from '../lib/identity';

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
