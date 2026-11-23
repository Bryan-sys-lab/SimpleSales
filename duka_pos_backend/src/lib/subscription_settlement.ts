import { getD1DatabaseBinding } from './prisma';

export async function activateSubscriptionPaymentAtomically(params: {
  paymentId: string;
  tenantId: string;
  durationMonths: number;
  receiptCode: string | null;
  voucherApplied: boolean;
}): Promise<void> {
  const db = getD1DatabaseBinding();
  const now = new Date().toISOString();
  const results = await db.batch([
    db.prepare(`
      UPDATE subscription_payments
      SET status = 'SUCCESS', provider_status = 'SUCCESS', mpesa_receipt_code = ?
      WHERE id = ? AND status <> 'SUCCESS'
    `).bind(params.receiptCode, params.paymentId),
    db.prepare(`
      INSERT INTO tenant_subscriptions (
        id, tenant_id, status, currency, billing_interval, current_period_end,
        voucher_id, updated_by, created_at, updated_at
      )
      SELECT ?, ?, 'active', 'KES', 'monthly',
             CASE WHEN ? > 0
               THEN date(substr(?, 1, 10), '+' || ? || ' months') || substr(?, 11)
               ELSE NULL
             END,
             NULL, NULL, ?, ?
      WHERE changes() = 1
      ON CONFLICT (tenant_id) DO UPDATE SET
        status = 'active',
        current_period_end = CASE
          WHEN excluded.current_period_end IS NULL THEN NULL
          WHEN tenant_subscriptions.current_period_end > excluded.created_at
          THEN date(substr(tenant_subscriptions.current_period_end, 1, 10), '+' || ? || ' months')
               || substr(tenant_subscriptions.current_period_end, 11)
          ELSE date(substr(excluded.created_at, 1, 10), '+' || ? || ' months')
               || substr(excluded.created_at, 11)
        END,
        voucher_id = CASE WHEN ? = 1 THEN NULL ELSE tenant_subscriptions.voucher_id END,
        grace_until = NULL,
        updated_at = excluded.updated_at
    `).bind(
      globalThis.crypto.randomUUID(),
      params.tenantId,
      params.durationMonths,
      now,
      params.durationMonths,
      now,
      now,
      now,
      params.durationMonths,
      params.durationMonths,
      params.voucherApplied ? 1 : 0,
    ),
  ]);
  if ((results[0]?.meta.changes ?? 0) > 1) {
    throw new Error('Subscription payment update affected multiple rows');
  }
}
