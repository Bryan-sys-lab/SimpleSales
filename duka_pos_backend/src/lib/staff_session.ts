import { createHash } from 'node:crypto';
import { verifyStaffSessionToken, type StaffSessionClaims } from './jwt';

type PrismaLike = {
  authSession?: {
    findUnique?: (args: any) => Promise<any>;
  };
  deviceAuthorization?: {
    findUnique?: (args: any) => Promise<any>;
  };
};

export type ActiveStaffSession = {
  claims: StaffSessionClaims;
  sessionHash: string;
  session: any | null;
};

export async function resolveActiveStaffSession(
  token: string,
  tenantId: string,
  prisma: PrismaLike,
): Promise<ActiveStaffSession | null> {
  const claims = verifyStaffSessionToken(token);
  if (!claims || claims.tenantId !== tenantId) return null;
  if (claims.deviceId) {
    const findDevice = prisma.deviceAuthorization?.findUnique;
    if (!findDevice) return null;
    const device = await findDevice({
      where: {
        tenantId_deviceId: { tenantId, deviceId: claims.deviceId },
      },
    });
    if (!device || device.status !== 'active' || device.revokedAt) return null;
  }
  const sessionHash = createHash('sha256').update(token).digest('hex');
  const session = await (prisma.authSession?.findUnique as any)?.({
    where: { refreshTokenHash: sessionHash },
  }).catch(() => null);
  if (session?.revokedAt) return null;
  if (session?.expiresAt && new Date(session.expiresAt).getTime() <= Date.now()) return null;
  return { claims, sessionHash, session };
}
