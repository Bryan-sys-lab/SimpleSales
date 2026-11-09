export function normalizeEmail(value: any): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

/**
 * A shop may be linked only when the token carries a verified email that
 * matches the email collected during local account creation.
 */
export function isVerifiedEmailMatch(claims: any, requestedEmail: string): boolean {
  if (!claims) {
    return false;
  }
  if (claims.email_verified === false) {
    return false;
  }
  const tokenEmail = normalizeEmail(claims.email);
  const expected = normalizeEmail(requestedEmail);
  if (!tokenEmail || !expected) {
    return false;
  }
  return tokenEmail === expected;
}
