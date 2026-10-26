CREATE TABLE "tax_return_events" (
  "id" TEXT NOT NULL,
  "tax_entity_id" TEXT NOT NULL,
  "vat_return_id" TEXT,
  "tot_return_id" TEXT,
  "from_status" TEXT,
  "to_status" TEXT NOT NULL,
  "actor_id" TEXT NOT NULL,
  "note" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "tax_return_events_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "tax_return_events_tax_entity_id_created_at_idx"
  ON "tax_return_events"("tax_entity_id", "created_at");
CREATE INDEX "tax_return_events_vat_return_id_created_at_idx"
  ON "tax_return_events"("vat_return_id", "created_at");
CREATE INDEX "tax_return_events_tot_return_id_created_at_idx"
  ON "tax_return_events"("tot_return_id", "created_at");

ALTER TABLE "tax_return_events"
  ADD CONSTRAINT "tax_return_events_tax_entity_id_fkey"
  FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tax_return_events"
  ADD CONSTRAINT "tax_return_events_vat_return_id_fkey"
  FOREIGN KEY ("vat_return_id") REFERENCES "vat_returns"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tax_return_events"
  ADD CONSTRAINT "tax_return_events_tot_return_id_fkey"
  FOREIGN KEY ("tot_return_id") REFERENCES "tot_returns"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
