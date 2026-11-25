import jwt from 'jsonwebtoken';

export type TokenTier = 'device' | 'access' | 'admin';
export type StaffSessionClaims = {
  sub: string;
  tenantId: string;
  profileId: string;
  deviceId?: string;
  token_use: 'staff';
  pin_cv?: number;
  iat: number;
  exp: number;
  jti: string;
};

export type AccessTokenClaims = {
  sub: string;
  email: string;
  email_verified: boolean;
  token_use: TokenTier;
  remembered?: boolean;
  iat: number;
  exp: number;
  jti: string;
};

const DEVICE_TTL_SECONDS = 12 * 60 * 60;
const ACCESS_TTL_SECONDS = 60 * 60;
const ADMIN_TTL_SECONDS = 60 * 60;
const REMEMBERED_ADMIN_TTL_SECONDS = 30 * 24 * 60 * 60;
const CLOCK_SKEW_SECONDS = 60;
const STAFF_SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

export function issueAccessToken(params: {
  userId: string;
  email: string;
  emailVerified: boolean;
  tier: TokenTier;
  rememberMe?: boolean;
}): { token: string; expiresIn: number } {
  const remembered = params.tier === 'admin' && params.rememberMe === true;
  const ttl = params.tier === 'device'
    ? DEVICE_TTL_SECONDS
    : params.tier === 'admin'
      ? remembered ? REMEMBERED_ADMIN_TTL_SECONDS : ADMIN_TTL_SECONDS
      : ACCESS_TTL_SECONDS;
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret) throw new Error('AUTH_JWT_SECRET must be configured');
  const jti = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2));
  const token = jwt.sign(
    {
      sub: params.userId,
      email: params.email,
      email_verified: params.emailVerified,
      token_use: params.tier,
      ...(remembered ? { remembered: true } : {}),
      jti,
    },
    secret,
    { algorithm: 'HS256', expiresIn: ttl },
  );
  return { token, expiresIn: ttl };
}

export function verifyAccessToken(token: string): AccessTokenClaims | null {
  const candidateSecrets = [process.env.AUTH_JWT_SECRET ?? '', process.env.AUTH_JWT_SECRET_PREVIOUS ?? ''].filter(Boolean);
  if (candidateSecrets.length === 0) return null;
  for (const secret of candidateSecrets) {
    try {
      const decoded = jwt.verify(token, secret, {
        algorithms: ['HS256'],
        clockTolerance: CLOCK_SKEW_SECONDS,
      }) as AccessTokenClaims;
      if (!decoded || typeof decoded.sub !== 'string') return null;
      if (decoded.remembered !== undefined && typeof decoded.remembered !== 'boolean') return null;
      if (decoded.remembered && decoded.token_use !== 'admin') return null;
      if (typeof decoded.iat === 'number' && typeof decoded.exp === 'number') {
        const maxLifetime = decoded.token_use === 'device'
          ? DEVICE_TTL_SECONDS
          : decoded.token_use === 'admin'
            ? decoded.remembered ? REMEMBERED_ADMIN_TTL_SECONDS : ADMIN_TTL_SECONDS
            : ACCESS_TTL_SECONDS;
        if (decoded.exp - decoded.iat > maxLifetime + CLOCK_SKEW_SECONDS) return null;
      }
      if (decoded.token_use !== 'device' && decoded.token_use !== 'access' && decoded.token_use !== 'admin') return null;
      return decoded;
    } catch {
      // try next
    }
  }
  return null;
}

/** A PIN-authenticated staff session, intentionally not accepted as an app token. */
export function issueStaffSessionToken(params: {
  profileId: string;
  tenantId: string;
  userId: string;
  deviceId?: string;
  pinCredentialVersion?: number | null;
}): { token: string; expiresIn: number } {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret) throw new Error('AUTH_JWT_SECRET must be configured');
  const jti = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2));
  return {
    token: jwt.sign(
      {
        sub: params.userId,
        tenantId: params.tenantId,
        profileId: params.profileId,
        ...(params.deviceId ? { deviceId: params.deviceId } : {}),
        token_use: 'staff',
        pin_cv: params.pinCredentialVersion ?? 0,
        jti,
      },
      secret,
      { algorithm: 'HS256', expiresIn: STAFF_SESSION_TTL_SECONDS },
    ),
    expiresIn: STAFF_SESSION_TTL_SECONDS,
  };
}

export function verifyStaffSessionToken(token: string): StaffSessionClaims | null {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret) return null;
  try {
    const claims = jwt.verify(token, secret, {
      algorithms: ['HS256'],
      clockTolerance: CLOCK_SKEW_SECONDS,
    }) as StaffSessionClaims;
    if (claims.token_use !== 'staff' || !claims.sub || !claims.tenantId || !claims.profileId) return null;
    if (claims.deviceId !== undefined && (typeof claims.deviceId !== 'string' || !claims.deviceId.trim())) return null;
    if (claims.exp - claims.iat > STAFF_SESSION_TTL_SECONDS + CLOCK_SKEW_SECONDS) return null;
    return claims;
  } catch {
    return null;
  }
}

export function accessTokenTtlSeconds(tier: TokenTier): number {
  return tier === 'device' ? DEVICE_TTL_SECONDS : ACCESS_TTL_SECONDS;
}
