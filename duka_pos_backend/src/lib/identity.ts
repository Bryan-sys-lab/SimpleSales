/**
 * Authoritative online identity rules.
 *
 * Duka POS has exactly one online identity: the self-hosted Keycloak/OIDC
 * account. The local 4-digit PIN is a device-bound offline unlock for the till
 * and is never a second identity. To stop an app from claiming a shop it does
 * not own, provisioning requires the email in the verified OIDC token to match
 * the email the operator typed during local setup.
 */

export type OidcTokenClaims = {
  sub?: unknown;
  email?: unknown;
  email_verified?: unknown;
};

export function normalizeEmail(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

/**
 * A shop may be linked only when the token carries a verified email that
 * matches the email collected during local account creation. This is the
 * authoritative link between the offline shop record and the online identity.
 */
export function isVerifiedEmailMatch(
  claims: OidcTokenClaims | undefined,
  requestedEmail: string,
): boolean {
  if (!claims) return false;
  // Keycloak sends `email_verified`; some deployments omit it for trusted
  // realms. An explicit `false` always fails, absence is treated as verified.
  if (claims.email_verified === false) return false;

  const tokenEmail = normalizeEmail(claims.email);
  const expected = normalizeEmail(requestedEmail);
  if (!tokenEmail || !expected) return false;

  return tokenEmail === expected;
}
