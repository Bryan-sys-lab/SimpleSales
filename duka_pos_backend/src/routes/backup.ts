import { Router } from 'express';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody, cloudBackupSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { requireRole } from '../middleware/auth';
import { deleteOpaqueBackup, getOpaqueBackup, putOpaqueBackup } from '../lib/r2';
import { randomUUID } from 'node:crypto';

const router = Router();

// The payload is client-encrypted JSON. Only an owner or manager may create or
// read a whole-shop backup; cashiers can continue selling and syncing sales.
// New ciphertext is kept in R2; the database row is only the tenant-scoped
// metadata/index. Legacy rows with payload text remain readable during rollout.
router.post('/', requireRole('admin', 'manager'), asyncHandler(async (req, res) => {
  const { workspaceKey, payload, kind, snapshotHash } = parseBody(cloudBackupSchema, req.body);
  const tenantId = requireUser(req).tenantId;
  if (snapshotHash) {
    const existing = await prisma.cloudBackup.findFirst({
      where: { tenantId, workspaceKey, kind, snapshotHash },
      select: { id: true, workspaceKey: true, kind: true, createdAt: true },
    });
    if (existing) return res.status(200).json(existing);
  }
  const id = randomUUID();
  const storageKey = `backups/${tenantId}/${encodeURIComponent(workspaceKey)}/${id}.duka`;
  await putOpaqueBackup(storageKey, payload);
  let backup;
  try {
    backup = await prisma.cloudBackup.create({
      data: {
        id,
        tenantId,
        workspaceKey,
        kind,
        snapshotHash,
        payload: '',
        storageKey,
      },
      select: { id: true, workspaceKey: true, kind: true, createdAt: true },
    });
  } catch (error) {
    await deleteOpaqueBackup(storageKey).catch(() => undefined);
    if (snapshotHash) {
      const existing = await prisma.cloudBackup.findFirst({
        where: { tenantId, workspaceKey, kind, snapshotHash },
        select: { id: true, workspaceKey: true, kind: true, createdAt: true },
      });
      if (existing) return res.status(200).json(existing);
    }
    throw error;
  }

  // Keep the cloud copy bounded without touching another workspace or tenant.
  const older = await prisma.cloudBackup.findMany({
    where: { tenantId, workspaceKey, kind },
    orderBy: { createdAt: 'desc' },
    skip: 12,
    select: { id: true, storageKey: true },
  });
  if (older.length) {
    await prisma.cloudBackup.deleteMany({ where: { id: { in: older.map((row) => row.id) } } });
    await Promise.all(
      older
        .map((row) => row.storageKey)
        .filter((key): key is string => Boolean(key))
        .map((key) => deleteOpaqueBackup(key).catch(() => undefined)),
    );
  }
  return res.status(201).json(backup);
}));

router.get('/', requireRole('admin', 'manager'), asyncHandler(async (req, res) => {
  const workspaceKey = typeof req.query.workspaceKey === 'string' ? req.query.workspaceKey.trim() : '';
  if (!workspaceKey) return res.status(400).json({ error: 'workspaceKey is required' });
  const requestedKind = typeof req.query.kind === 'string' ? req.query.kind : 'device_bound';
  if (requestedKind !== 'device_bound' && requestedKind !== 'portable') {
    return res.status(400).json({ error: 'Invalid backup kind' });
  }
  const backup = await prisma.cloudBackup.findFirst({
    where: { tenantId: requireUser(req).tenantId, workspaceKey, kind: requestedKind },
    orderBy: { createdAt: 'desc' },
    select: { id: true, workspaceKey: true, kind: true, payload: true, storageKey: true, createdAt: true },
  });
  if (!backup) return res.json({ payload: null });
  const payload = backup.storageKey
    ? await getOpaqueBackup(backup.storageKey)
    : backup.payload;
  return res.json({
    id: backup.id,
    workspaceKey: backup.workspaceKey,
    kind: backup.kind,
    payload,
    createdAt: backup.createdAt,
  });
}));

export default router;
