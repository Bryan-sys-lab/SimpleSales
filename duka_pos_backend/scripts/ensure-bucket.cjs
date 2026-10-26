const {
  CreateBucketCommand,
  HeadBucketCommand,
  S3Client,
} = require('@aws-sdk/client-s3');

const bucket = process.env.R2_BUCKET_NAME;
if (!bucket) throw new Error('R2_BUCKET_NAME is required');

const client = new S3Client({
  endpoint: process.env.R2_ENDPOINT,
  region: 'auto',
  forcePathStyle: true,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || '',
  },
});

(async () => {
  try {
    await client.send(new HeadBucketCommand({ Bucket: bucket }));
    console.log(`Object bucket already exists: ${bucket}`);
    return;
  } catch (error) {
    if (error?.$metadata?.httpStatusCode !== 404 && error?.name !== 'NotFound') {
      throw error;
    }
  }

  await client.send(new CreateBucketCommand({ Bucket: bucket }));
  console.log(`Created object bucket: ${bucket}`);
})().catch((error) => {
  console.error('Object bucket initialization failed:', error);
  process.exitCode = 1;
});
