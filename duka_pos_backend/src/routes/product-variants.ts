/**
 * Product variant routes — variant catalogue sync and pull.
 *
 * Variants are stored as SyncRecord kind 'product-variants' so any till can
 * pull the current Fashion variant catalogue (FASHION-04).
 */
import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { productVariantsSyncSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';

const router = Router();

// ---------------------------------------------------------------------------
// Bulk variant sync (upsert)
// ---------------------------------------------------------------------------

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req, res) => {
  const user = requireUser(req);
  const { variants } = parseBody(productVariantsSyncSchema, req.body);
  const synced: Array<{ localId: number; remoteId: string }> = [];

  await prisma.$transaction(async (tx) => {
    for (const variant of variants) {
      const saved = await tx.syncRecord.upsert({
        where: {
          tenantId_kind_deviceId_localId: {
            tenantId: user.tenantId,
            kind: 'product-variants',
            deviceId: variant.deviceId ?? 'legacy',
            localId: variant.localId,
          },
        },
        create: {
          tenantId: user.tenantId,
          kind: 'product-variants',
          deviceId: variant.deviceId ?? 'legacy',
          localId: variant.localId,
          payload: { ...variant, productId: variant.productId } as Prisma.InputJsonValue,
          createdAt: new Date(variant.createdAt ?? new Date().toISOString()),
        },
        update: {
          payload: { ...variant, productId: variant.productId } as Prisma.InputJsonValue,
          updatedAt: new Date(),
        },
        select: { id: true },
      });
      synced.push({ localId: variant.localId, remoteId: saved.id });
    }
  });

  return res.json({ synced });
}));

// ---------------------------------------------------------------------------
// Variant catalogue pull — lets another till browse current variants
// ---------------------------------------------------------------------------

router.get('/', asyncHandler(async (req, res) => {
  const tenantId = requireUser(req).tenantId;
  const productId = req.query.productId as string | undefined;
  const where: any = { tenantId, kind: 'product-variants' };
  if (productId) {
    where.payload = { productId };
  }
  const records = await prisma.syncRecord.findMany({
    where,
    orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
    take: 2000,
    select: { id: true, payload: true, createdAt: true, updatedAt: true },
  });
  return res.json({
    variants: records.map((record) => ({
      ...(record.payload as Record<string, unknown>),
      remoteId: record.id,
      remoteCreatedAt: record.createdAt.toISOString(),
      remoteUpdatedAt: record.updatedAt.toISOString(),
    })),
  });
}));

export default router;
