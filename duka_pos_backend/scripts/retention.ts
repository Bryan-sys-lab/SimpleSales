/**
 * Standalone data retention script.
 *
 * Usage: npx tsx scripts/retention.ts
 * Can be wired into cron for periodic telemetry event purging.
 */
import { runRetention } from '../src/lib/retention';
import { log } from '../src/lib/observability';

runRetention()
  .then(({ deletedTelemetryEvents }) => {
    log('info', 'retention.script.complete', { deletedTelemetryEvents });
    process.exit(0);
  })
  .catch((error) => {
    log('error', 'retention.script.failed', {
      message: error instanceof Error ? error.message : 'unknown',
      stack: error instanceof Error ? error.stack : undefined,
    });
    process.exit(1);
  });
