/**
 * Verifying a Keycloak access token outside the request pipeline.
 *
 * ## WHY THIS EXISTS
 *
 * The WebSocket upgrade for the live channel is not an Express request: it
 * never reaches the router, so the middleware cannot see it. It needs the
 * SAME check the middleware makes, though — one credential, verified one way —
 * and this is that check, callable.
 *
 * ## WHY IT IS NOT A SECOND CREDENTIAL
 *
 * There is exactly one credential in this service: a Keycloak access token.
 * The live channel used to accept a session token of our own, signed here
 * against a secret that lived in this process. That is gone: a secret in this
 * process is a secret every deployment of this service has to manage, rotate
 * and leak, and a token the identity server has never heard of is a second
 * authority deciding who a person is.
 */

import jwksRsa from 'jwks-rsa';
import jwt from 'jsonwebtoken';

/** The claims the live channel needs out of a token. */
export type KeycloakClaims = {
  sub: string;
  email?: string;
};

let client: jwksRsa.JwksClient | null = null;

function jwksClient(jwksUri: string): jwksRsa.JwksClient {
  if (!client) {
    client = jwksRsa({
      jwksUri,
      cache: true,
      rateLimit: true,
      jwksRequestsPerMinute: 5,
    });
  }
  return client;
}

/**
 * Verifies [token] against the identity server's JWKS.
 *
 * Returns null for anything that is not a live, correctly signed token for
 * this issuer and audience — including a token that is expired, one signed by
 * the wrong key, and one that is not a token at all. A caller cannot tell
 * which, and does not need to.
 */
export async function verifyKeycloakToken(
  token: string,
  options: { issuer: string; audience: string; jwksUri: string },
): Promise<KeycloakClaims | null> {
  if (!token) return null;
  try {
    const decoded = jwt.decode(token, { complete: true });
    if (!decoded || typeof decoded === 'string' || !decoded.header.kid) {
      return null;
    }
    const key = await new Promise<string>((resolve, reject) => {
      jwksClient(options.jwksUri).getSigningKey(decoded.header.kid!, (error, signingKey) => {
        if (error || !signingKey) {
          reject(error ?? new Error('No signing key for that token'));
          return;
        }
        resolve(signingKey.getPublicKey());
      });
    });
    const claims = jwt.verify(token, key, {
      audience: options.audience,
      issuer: options.issuer,
      algorithms: ['RS256'],
    });
    if (typeof claims === 'string' || !claims.sub) return null;
    return { sub: String(claims.sub), email: claims.email as string | undefined };
  } catch {
    // A token that does not verify is a token that is not a credential.
    return null;
  }
}
