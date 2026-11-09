ALTER TABLE "tax_entities"
  ADD COLUMN "etims_onboarding_status" TEXT NOT NULL DEFAULT 'not_started',
  ADD COLUMN "etims_method" TEXT;
