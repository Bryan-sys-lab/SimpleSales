import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  create: vi.fn(),
}));

vi.mock('../lib/prisma', () => ({
  prisma: {
    authAuditEvent: {
      create: mocks.create,
    },
  },
}));

import { recordAuthAuditEvent } from '../lib/auth_audit';

describe('auth audit metadata', () => {
  beforeEach(() => {
    mocks.create.mockReset().mockResolvedValue({});
  });

  it('retains the email and request ID alongside event metadata', async () => {
    await recordAuthAuditEvent({
      eventType: 'owner_login_failure',
      outcome: 'failure',
      email: 'owner@example.com',
      requestId: 'request-123',
      metadata: { flow: 'login' },
    });

    expect(mocks.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        eventType: 'owner_login_failure',
        metadata: {
          flow: 'login',
          email: 'owner@example.com',
          requestId: 'request-123',
        },
      }),
    });
  });
});
