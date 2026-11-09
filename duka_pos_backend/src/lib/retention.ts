/**
 * Data retention for raw telemetry events.
 *
 * Purges TelemetryEvent rows older than `olderThanDays` (default 90).
 * ChurnSnapshot, AdminAuditLog and SystemSettings are intentionally NOT purged:
 * they are snapshots/audit and are kept longer.
 */
import { prisma } from '../lib/prisma';
import { log } from '../lib/observability';

const DEFAULT_OLDER_THAN_DAYS = 90;

export async function runRetention(options?: {
  olderThanDays?: number;
  dryRun?: number;
}): Promise<{ deletedTelemetryEvents: number }> {
  const olderThanDays = options?.olderThanDays ?? DEFAULT_OLDER_THAN_DAYS;
  const cutoff = new Date(Date.now() - olderThanDays * 24 * 60 * 60 * 1000);
  const where = { createdAt: { lt: cutoff } };

  let deleted = 0;
  if (options?.dryRun) {
    deleted = await prisma.telemetryEvent.count({ where });
    log('info', 'retention.dry_run', { olderThanDays, wouldDelete: deleted, cutoff: cutoff.toISOString() });
  } else {
    const result = await prisma.telemetryEvent.deleteMany({ where });
    deleted = result.count;
    log('info', 'retention.run', { olderThanDays, deletedTelemetryEvents: deleted, cutoff: cutoff.toISOString() });
  }

  return { deletedTelemetryEvents: deleted };
}
