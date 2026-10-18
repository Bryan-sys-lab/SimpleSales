/**
 * Profile photo routes.
 *
 * Profile photos are stored in Cloudflare R2 (S3-compatible object storage).
 * Only profile photos are stored in R2 - all other images stay on the user's device.
 *
 * Routes:
 *   POST   /api/profile/photo/upload-url  - Get presigned PUT URL for direct upload
 *   POST   /api/profile/photo/confirm     - Confirm upload and save photoUrl to profile
 *   GET    /api/profile/photo/download-url - Get presigned GET URL for download
 *   DELETE /api/profile/photo              - Delete profile photo from R2 and profile
 */
import { Router } from 'express';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { authMiddleware } from '../middleware/auth';
import {
  uploadProfilePhoto,
  getProfilePhoto,
  deleteProfilePhoto,
  getProfilePhotoUploadUrl,
  getProfilePhotoDownloadUrl,
} from '../lib/r2';
import { z } from 'zod';

const router = Router();

// All profile routes require OIDC authentication
router.use(authMiddleware);

/**
 * Schema for upload-url request
 */
const uploadUrlSchema = z.object({
  fileName: z.string().min(1).max(255),
  contentType: z.string().min(1).max(100),
});

/**
 * Schema for confirm request
 */
const confirmSchema = z.object({
  key: z.string().min(1),
});

/**
 * POST /api/profile/photo/upload-url
 * Get a presigned PUT URL for direct browser upload to R2.
 */
router.post(
  '/upload-url',
  asyncHandler(async (req, res) => {
    const { fileName, contentType } = parseBody(uploadUrlSchema, req.body);
    const userId = req.user?.sub;

    if (!userId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }

    const { key, uploadUrl, expiresIn } = await getProfilePhotoUploadUrl({
      userId,
      fileName,
      contentType,
    });

    return res.json({
      key,
      uploadUrl,
      expiresIn,
    });
  })
);

/**
 * POST /api/profile/photo/confirm
 * Confirm upload and save photoUrl to profile.
 */
router.post(
  '/confirm',
  asyncHandler(async (req, res) => {
    const { key } = parseBody(confirmSchema, req.body);
    const userId = req.user?.sub;

    if (!userId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }

    // Find the profile for this user
    const profile = await prisma.profile.findFirst({
      where: { oidcSubject: userId },
    });

    if (!profile) {
      return res.status(404).json({ error: 'Profile not found' });
    }

    const publicUrl = `${process.env.R2_PUBLIC_URL || ''}/${key}`;

    // Update profile with photoUrl
    const updated = await prisma.profile.update({
      where: { id: profile.id },
      data: { photoUrl: publicUrl },
    });

    return res.json({
      photoUrl: updated.photoUrl,
      key,
    });
  })
);

/**
 * GET /api/profile/photo/download-url
 * Get a presigned GET URL for direct browser download from R2.
 */
router.get(
  '/download-url',
  asyncHandler(async (req, res) => {
    const userId = req.user?.sub;

    if (!userId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }

    const profile = await prisma.profile.findFirst({
      where: { oidcSubject: userId },
    });

    if (!profile || !profile.photoUrl) {
      return res.status(404).json({ error: 'No profile photo found' });
    }

    // Extract key from photoUrl
    const publicUrl = process.env.R2_PUBLIC_URL || '';
    const key = profile.photoUrl.replace(publicUrl + '/', '');

    const { downloadUrl, expiresIn } = await getProfilePhotoDownloadUrl(key);

    return res.json({
      downloadUrl,
      expiresIn,
    });
  })
);

/**
 * DELETE /api/profile/photo
 * Delete profile photo from R2 and clear photoUrl from profile.
 */
router.delete(
  '/',
  asyncHandler(async (req, res) => {
    const userId = req.user?.sub;

    if (!userId) {
      return res.status(401).json({ error: 'Authenticated user required' });
    }

    const profile = await prisma.profile.findFirst({
      where: { oidcSubject: userId },
    });

    if (!profile || !profile.photoUrl) {
      return res.status(404).json({ error: 'No profile photo found' });
    }

    // Extract key from photoUrl
    const publicUrl = process.env.R2_PUBLIC_URL || '';
    const key = profile.photoUrl.replace(publicUrl + '/', '');

    // Delete from R2
    try {
      await deleteProfilePhoto(key);
    } catch (error) {
      // Log but continue - we still want to clear the DB reference
    }

    // Clear photoUrl from profile
    await prisma.profile.update({
      where: { id: profile.id },
      data: { photoUrl: null },
    });

    return res.json({ deleted: true });
  })
);

export default router;
