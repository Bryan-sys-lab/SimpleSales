import { Router, type Request } from 'express';
import { z } from 'zod';
import { asyncHandler, requireUser } from '../lib/http';
import { prisma } from '../lib/prisma';
import { parseBody } from '../lib/validation';
import {
  getSaleEvidenceDownloadUrl,
  getSaleEvidenceUploadUrl,
  profilePhotoExists,
  type ProfileImageStorage,
} from '../lib/r2';
import { requireRole } from '../middleware/auth';

const router = Router();
router.use(requireRole('admin', 'manager', 'cashier'));

function getProfileImageStorage(req: Request): ProfileImageStorage | undefined {
  return (req as Request & { profileImageStorage?: ProfileImageStorage }).profileImageStorage;
}

const identity = z.object({
  deviceId: z.string().min(1).max(160),
  localId: z.number().int().positive(),
});
const uploadRequest = identity.extend({
  fileName: z.string().min(1).max(255),
  contentType: z.string().regex(/^image\//).max(100),
});
const confirmRequest = identity.extend({
  key: z.string().min(1).max(512),
  mimeType: z.string().regex(/^image\//).max(100),
  byteSize: z.number().int().positive().max(10_000_000).optional(),
});

function ownedKey(tenantId: string, deviceId: string, localId: number, key: string): boolean {
  return key.startsWith(`profile-photos/${tenantId}/sale-evidence/${deviceId}-${localId}/`)
    && !key.includes('..') && !key.includes('\\');
}

router.post('/upload-url', asyncHandler(async (req, res) => {
  const input = parseBody(uploadRequest, req.body);
  const user = requireUser(req);
  const prepared = await getSaleEvidenceUploadUrl({
    tenantId: user.tenantId,
    saleKey: `${input.deviceId}-${input.localId}`,
    fileName: input.fileName,
    contentType: input.contentType,
  });
  res.json(prepared);
}));

router.post('/confirm', asyncHandler(async (req, res) => {
  const input = parseBody(confirmRequest, req.body);
  const user = requireUser(req);
  if (!ownedKey(user.tenantId, input.deviceId, input.localId, input.key) ||
      !(await profilePhotoExists(input.key, getProfileImageStorage(req)))) {
    return res.status(400).json({ error: 'Uploaded sale evidence was not found' });
  }
  const sale = await prisma.sale.findFirst({
    where: { tenantId: user.tenantId, deviceId: input.deviceId, localId: input.localId },
    select: { id: true },
  });
  const evidence = await prisma.saleEvidence.upsert({
    where: { tenantId_deviceId_localId_objectKey: {
      tenantId: user.tenantId, deviceId: input.deviceId, localId: input.localId, objectKey: input.key,
    } },
    create: {
      tenantId: user.tenantId, saleId: sale?.id, deviceId: input.deviceId,
      localId: input.localId, objectKey: input.key,
      publicUrl: `${process.env.R2_PUBLIC_URL || ''}/${input.key}`,
      mimeType: input.mimeType, byteSize: input.byteSize, createdBy: user.id,
    },
    update: { saleId: sale?.id, byteSize: input.byteSize, mimeType: input.mimeType },
  });
  res.status(201).json({ id: evidence.id, key: evidence.objectKey, publicUrl: evidence.publicUrl });
}));

router.post('/list', asyncHandler(async (req, res) => {
  const input = parseBody(identity, req.body);
  const user = requireUser(req);
  const rows = await prisma.saleEvidence.findMany({
    where: { tenantId: user.tenantId, deviceId: input.deviceId, localId: input.localId },
    orderBy: { createdAt: 'asc' },
  });
  const evidence = await Promise.all(rows.map(async (row) => ({
    id: row.id,
    createdAt: row.createdAt,
    ...(await getSaleEvidenceDownloadUrl(row.objectKey)),
  })));
  res.json({ evidence });
}));

export default router;
