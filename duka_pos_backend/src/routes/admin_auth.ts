import { Request, Response, Router } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { prisma } from '../lib/prisma';
import { parseBody } from '../lib/validation';
import { issueAccessToken } from '../lib/jwt';
import { systemAdminMiddleware } from '../middleware/auth';
import { log } from '../lib/observability';

const router = Router();

const adminLoginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  phone: z.string().trim().min(6).max(30),
  key: z.string().trim().min(8).max(128),
});

const mintKeySchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  phone: z.string().trim().min(6).max(30),
  expiresInDays: z.number().int().min(1).max(365).default(30),
});

// POST /admin/auth/login — verify a minted key and issue a system-admin JWT.
router.post('/auth/login', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(adminLoginSchema, req.body);
  const key = await prisma.adminKey.findUnique({
    where: { email_phone: { email: input.email, phone: input.phone } },
  });
  if (!key || key.revokedAt || key.expiresAt < new Date()) {
    return res.status(401).json({ error: 'Invalid or expired admin key' });
  }
  const hash = crypto.createHash('sha256').update(input.key).digest('hex');
  if (hash !== key.keyHash) {
    return res.status(401).json({ error: 'Invalid admin key' });
  }
  // Mark used.
  await prisma.adminKey.update({ where: { id: key.id }, data: { usedAt: new Date() } });
  const token = issueAccessToken({ userId: `admin:${key.id}`, email: input.email, emailVerified: true, tier: 'access' });
  // Override token_use to 'admin' by re-issuing with a custom claim isn't supported;
  // instead we store the admin key id in the JWT subject and check SYSTEM_ADMIN_SUBJECTS.
  log('info', 'admin.auth.login', { email: input.email });
  return res.json({ access_token: token, token_type: 'Bearer', expires_in: 12 * 60 * 60 });
}));

// POST /admin/keys/mint — master admin mints a key for another admin.
// Protected by systemAdminMiddleware (mounted separately).
router.post('/keys/mint', systemAdminMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(mintKeySchema, req.body);
  const adminId = req.auth?.sub ?? 'unknown';
  const rawKey = crypto.randomBytes(24).toString('base64url');
  const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');
  const expiresAt = new Date(Date.now() + input.expiresInDays * 24 * 60 * 60 * 1000);
  const key = await prisma.adminKey.create({
    data: {
      email: input.email,
      phone: input.phone,
      keyHash,
      createdBy: adminId,
      expiresAt,
    },
  });
  log('info', 'admin.key.minted', { email: input.email, createdBy: adminId });
  return res.json({ key: rawKey, id: key.id, email: input.email, phone: input.phone, expiresAt });
}));

export default router;
