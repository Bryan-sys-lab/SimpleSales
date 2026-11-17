import jwt from 'jsonwebtoken';

export type TokenTier = 'device' | 'access';
export type StaffSessionClaims = {
  sub: string;
  tenantId: string;
  profileId: string;
  token_use: 'staff';
  iat: number;
  exp: number;
  jti: string;
};

export type AccessTokenClaims = {
  sub: string;
  email: string;
  email_verified: boolean;
  token_use: TokenTier;
  iat: number;
  exp: number;
  jti: string;
};

const DEVICE_TTL_SECONDS = 12 * 60 * 60;
const ACCESS_TTL_SECONDS = 60 * 60;
const CLOCK_SKEW_SECONDS = 60;
const STAFF_SESSION_TTL_SECONDS = 12 * 60 * 60;

export function issueAccessToken(params: {
  userId: string;
  email: string;
  emailVerified: boolean;
  tier: TokenTier;
}): { token: string; expiresIn: number } {
  const ttl = params.tier === 'device' ? DEVICE_TTL_SECONDS : ACCESS_TTL_SECONDS;
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret) throw new Error('AUTH_JWT_SECRET must be configured');
  const jti = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2));
  const token = jwt.sign(
    {
      sub: params.userId,
      email: params.email,
      email_verified: params.emailVerified,
      token_use: params.tier,
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
      if (typeof decoded.iat === 'number' && typeof decoded.exp === 'number') {
        const maxLifetime = decoded.token_use === 'device' ? DEVICE_TTL_SECONDS : ACCESS_TTL_SECONDS;
        if (decoded.exp - decoded.iat > maxLifetime + CLOCK_SKEW_SECONDS) return null;
      }
      if (decoded.token_use !== 'device' && decoded.token_use !== 'access') return null;
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
}): { token: string; expiresIn: number } {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret) throw new Error('AUTH_JWT_SECRET must be configured');
  const jti = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2));
  return {
    token: jwt.sign(
      { sub: params.userId, tenantId: params.tenantId, profileId: params.profileId, token_use: 'staff', jti },
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
    if (claims.exp - claims.iat > STAFF_SESSION_TTL_SECONDS + CLOCK_SKEW_SECONDS) return null;
    return claims;
  } catch {
    return null;
  }
}

export function accessTokenTtlSeconds(tier: TokenTier): number {
  return tier === 'device' ? DEVICE_TTL_SECONDS : ACCESS_TTL_SECONDS;
}
