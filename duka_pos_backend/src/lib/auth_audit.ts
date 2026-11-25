import { Prisma } from '../generated/client/client.js';
import { prisma } from './prisma.js';

export interface AuthAuditInput {
  tenantId?: string | null;
  actorType: string;
  actorId?: string | null;
  action: string;
  outcome: 'success' | 'failure' | 'denied' | 'error';
  reason?: string | null;
  ip?: string | null;
  userAgent?: string | null;
  deviceId?: string | null;
  metadata?: Record<string, unknown> | null;
}

export async function recordAuthAuditEvent(input: AuthAuditInput): Promise<void> {
  try {
    await prisma.authAuditEvent.create({
      data: {
        tenantId: input.tenantId ?? null,
        actorType: input.actorType,
        actorId: input.actorId ?? null,
        action: input.action,
        outcome: input.outcome,
        reason: input.reason ?? null,
        ip: input.ip ?? null,
        userAgent: input.userAgent ?? null,
        deviceId: input.deviceId ?? null,
        metadataJson: input.metadata ? JSON.stringify(input.metadata) : null,
      },
    });
  } catch (error) {
    console.warn('[auth-audit] failed to record event', {
      action: input.action,
      outcome: input.outcome,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}
