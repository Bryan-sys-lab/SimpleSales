import { beforeEach, describe, expect, it, vi } from 'vitest';

process.env.AUTH_JWT_SECRET = 'test-secret-at-least-32-bytes-long-xxxxxxxx';

const mocks = vi.hoisted(() => ({
  findSession: vi.fn(),
  findDevice: vi.fn(),
}));

describe('device-bound staff sessions', () => {
  beforeEach(() => {
    mocks.findSession.mockReset().mockResolvedValue(null);
    mocks.findDevice.mockReset().mockResolvedValue({
      status: 'active',
      revokedAt: null,
    });
  });

  it('accepts self-PIN sessions only while their device remains active', async () => {
    const { issueStaffSessionToken } = await import('../lib/jwt');
    const { resolveActiveStaffSession } = await import('../lib/staff_session');
    const token = issueStaffSessionToken({
      profileId: 'staff-1',
      tenantId: 'tenant-1',
      userId: 'staff:staff-1',
      deviceId: 'device-1',
    }).token;
    const prisma = {
      authSession: { findUnique: mocks.findSession },
      deviceAuthorization: { findUnique: mocks.findDevice },
    };

    expect(await resolveActiveStaffSession(token, 'tenant-1', prisma)).not.toBeNull();
    expect(mocks.findDevice).toHaveBeenLastCalledWith({
      where: {
        tenantId_deviceId: { tenantId: 'tenant-1', deviceId: 'device-1' },
      },
    });

    mocks.findDevice.mockResolvedValue({
      status: 'revoked',
      revokedAt: new Date(),
    });
    expect(await resolveActiveStaffSession(token, 'tenant-1', prisma)).toBeNull();
  });
});
