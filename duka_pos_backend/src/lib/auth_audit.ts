import { prisma } from './prisma.js';

export interface AuthAuditInput {
  tenantId?: string | null;
  actorType?: string | null;
  actorId?: string | null;
  profileId?: string | null;
  userId?: string | null;
  eventType?: string;
  action?: string;
  outcome: 'success' | 'failure' | 'denied' | 'error';
  reason?: string | null;
  ip?: string | null;
  userAgent?: string | null;
  deviceId?: string | null;
  email?: string | null;
  requestId?: string | null;
  metadata?: Record<string, unknown> | null;
}

export async function recordAuthAuditEvent(input: AuthAuditInput): Promise<void> {
  const eventType = input.eventType ?? input.action ?? 'unknown_auth_event';
  const actorType = input.actorType ?? null;
  const actorId = input.actorId ?? null;
  const profileId = input.profileId ?? (actorType === 'staff' ? actorId : null);
  const userId = input.userId ?? (actorType && actorType !== 'staff' ? actorId : null);
  const metadata = {
    ...(input.metadata ?? {}),
    ...(input.email ? { email: input.email } : {}),
    ...(input.requestId ? { requestId: input.requestId } : {}),
  };
  try {
    await prisma.authAuditEvent.create({
      data: {
        tenantId: input.tenantId ?? null,
        profileId,
        userId,
        deviceId: input.deviceId ?? null,
        eventType,
        outcome: input.outcome,
        reason: input.reason ?? null,
        ip: input.ip ?? null,
        userAgent: input.userAgent ?? null,
        metadata: Object.keys(metadata).length > 0 ? metadata as any : undefined,
      },
    });
  } catch (error) {
    console.warn('[auth-audit] failed to record event', {
      eventType,
      outcome: input.outcome,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}
