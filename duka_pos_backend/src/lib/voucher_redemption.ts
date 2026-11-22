import { getD1DatabaseBinding } from './prisma';

export async function redeemVoucherAtomically(params: {
  voucherId: string;
  tenantId: string;
  profileId: string;
  email: string;
  now: Date;
  expiresAt: Date | null;
}): Promise<boolean> {
  const db = getD1DatabaseBinding();
  const now = params.now.toISOString();
  const expiresAt = params.expiresAt?.toISOString() ?? null;
  const subscriptionId = globalThis.crypto.randomUUID();

  const results = await db.batch([
    db.prepare(`
      UPDATE access_vouchers
      SET redeemed_at = ?,
          redeemed_by_profile_id = ?,
          tenant_id = COALESCE(tenant_id, ?),
          issued_to_profile_id = COALESCE(issued_to_profile_id, ?),
          expires_at = ?
      WHERE id = ?
        AND redeemed_at IS NULL
        AND revoked_at IS NULL
        AND paused_at IS NULL
        AND deleted_at IS NULL
        AND (expires_at IS NULL OR expires_at > ?)
        AND (tenant_id IS NULL OR tenant_id = ?)
        AND (issued_to_profile_id IS NULL OR issued_to_profile_id = ?)
        AND (issued_to_email IS NULL OR issued_to_email = ?)
    `).bind(
      now,
      params.profileId,
      params.tenantId,
      params.profileId,
      expiresAt,
      params.voucherId,
      now,
      params.tenantId,
      params.profileId,
      params.email,
    ),
    db.prepare(`
      INSERT INTO tenant_subscriptions (
        id, tenant_id, status, currency, billing_interval,
        current_period_end, voucher_id, created_at, updated_at
      )
      SELECT ?, ?, 'voucher', 'KES', 'monthly', ?, ?, ?, ?
      WHERE changes() = 1
      ON CONFLICT (tenant_id) DO UPDATE SET
        status = 'voucher',
        voucher_id = excluded.voucher_id,
        current_period_end = excluded.current_period_end,
        grace_until = NULL,
        updated_at = excluded.updated_at
    `).bind(
      subscriptionId,
      params.tenantId,
      expiresAt,
      params.voucherId,
      now,
      now,
    ),
  ]);

  return (results[0]?.meta.changes ?? 0) === 1;
}
