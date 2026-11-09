-- The profile picture, in the object store. The route that serves it was
-- here before the column was, so a picture could be set and never read.
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "photo_url" TEXT;
