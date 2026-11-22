import { getD1DatabaseBinding } from './prisma';
import { requiredD1String } from './d1_results';

export type SyncRecordInput = {
  tenantId: string;
  kind: string;
  deviceId: string;
  localId: number;
  payload: unknown;
  createdAt: Date;
  updatePayload?: boolean;
  updateCreatedAt?: boolean;
};

export async function upsertSyncRecords(
  records: readonly SyncRecordInput[],
): Promise<Array<{ localId: number; remoteId: string }>> {
  if (records.length === 0) return [];

  const db = getD1DatabaseBinding();
  const statements = records.map((record) => {
    const updates = [
      'id = sync_records.id',
      ...(record.updatePayload ? ['payload = excluded.payload'] : []),
      ...(record.updateCreatedAt ? ['created_at = excluded.created_at'] : []),
      ...(record.updatePayload || record.updateCreatedAt ? ['updated_at = excluded.updated_at'] : []),
    ];
    const createdAt = record.createdAt.toISOString();

    return db.prepare(`
      INSERT INTO sync_records (
        id, tenant_id, kind, device_id, local_id, payload, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, kind, device_id, local_id)
      DO UPDATE SET ${updates.join(', ')}
      RETURNING id
    `).bind(
      globalThis.crypto.randomUUID(),
      record.tenantId,
      record.kind,
      record.deviceId,
      record.localId,
      JSON.stringify(record.payload),
      createdAt,
      new Date().toISOString(),
    );
  });
  const results = await db.batch(statements);

  return records.map((record, index) => ({
    localId: record.localId,
    remoteId: requiredD1String(results[index], 'id', `${record.kind}:${record.localId}`),
  }));
}
