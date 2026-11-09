ALTER TABLE "tax_rules"
  ADD COLUMN "filing_frequency" TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN "filing_due_day" INTEGER;
