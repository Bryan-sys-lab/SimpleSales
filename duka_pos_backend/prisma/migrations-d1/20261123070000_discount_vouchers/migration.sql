ALTER TABLE "access_vouchers"
ADD COLUMN "voucher_type" TEXT NOT NULL DEFAULT 'access';

ALTER TABLE "access_vouchers"
ADD COLUMN "discount_percent" INTEGER NOT NULL DEFAULT 0;
