/**
 * Cloudflare R2 storage service for profile images.
 *
 * Images are stored in Cloudflare R2 (S3-compatible object storage).
 * Only profile photos are stored in R2 - all other images (receipts, product
 * images, documents) stay on the user's device.
 *
 * Environment variables:
 *   R2_ENDPOINT        - R2 endpoint URL (e.g. https://<account>.r2.cloudflarestorage.com)
 *   R2_ACCESS_KEY_ID   - R2 access key
 *   R2_SECRET_ACCESS_KEY - R2 secret key
 *   R2_BUCKET_NAME     - R2 bucket name
 *   R2_PUBLIC_URL      - Public URL for accessing objects (e.g. https://pub-<id>.r2.dev)
 */
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const r2 = new S3Client({
  endpoint: process.env.R2_ENDPOINT,
  region: 'auto',
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || '',
  },
  forcePathStyle: true,
});

const BUCKET = process.env.R2_BUCKET_NAME || 'duka-pos-profile-photos';

/**
 * Upload a profile photo to R2.
 * Returns the object key and public URL.
 */
export async function uploadProfilePhoto(params: {
  userId: string;
  fileName: string;
  contentType: string;
  body: Buffer | Uint8Array;
}) {
  const key = `profile-photos/${params.userId}/${params.fileName}`;

  await r2.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: params.body,
    ContentType: params.contentType,
  }));

  const publicUrl = `${process.env.R2_PUBLIC_URL || ''}/${key}`;

  return {
    key,
    publicUrl,
    bucket: BUCKET,
  };
}

/**
 * Get a profile photo from R2.
 * Returns the object stream and metadata, or null if not found.
 */
export async function getProfilePhoto(key: string) {
  try {
    const head = await r2.send(new HeadObjectCommand({
      Bucket: BUCKET,
      Key: key,
    }));

    const response = await r2.send(new GetObjectCommand({
      Bucket: BUCKET,
      Key: key,
    }));

    return {
      key,
      contentType: head.ContentType,
      contentLength: head.ContentLength,
      lastModified: head.LastModified,
      body: response.Body as unknown as NodeJS.ReadableStream,
    };
  } catch (error: any) {
    if (error.name === 'NotFound' || error.$metadata?.httpStatusCode === 404) {
      return null;
    }
    throw error;
  }
}

/**
 * Delete a profile photo from R2.
 */
export async function deleteProfilePhoto(key: string) {
  await r2.send(new DeleteObjectCommand({
    Bucket: BUCKET,
    Key: key,
  }));
}

/**
 * Generate a presigned PUT URL for direct browser upload to R2.
 * Returns the URL and the object key.
 */
export async function getProfilePhotoUploadUrl(params: {
  userId: string;
  fileName: string;
  contentType: string;
}) {
  const key = `profile-photos/${params.userId}/${params.fileName}`;

  const url = await getSignedUrl(r2, new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    ContentType: params.contentType,
  }), { expiresIn: 3600 }); // 1 hour

  return {
    key,
    uploadUrl: url,
    expiresIn: 3600,
  };
}

/**
 * Generate a presigned GET URL for direct browser download from R2.
 */
export async function getProfilePhotoDownloadUrl(key: string, expiresIn = 3600) {
  const url = await getSignedUrl(r2, new GetObjectCommand({
    Bucket: BUCKET,
    Key: key,
  }), { expiresIn });

  return {
    key,
    downloadUrl: url,
    expiresIn,
  };
}

export { BUCKET };
