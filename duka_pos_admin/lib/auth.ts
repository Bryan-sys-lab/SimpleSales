export const TOKEN_COOKIE = '__Host-duka_admin_session';

export function getToken(): null {
  // Admin credentials live in an HttpOnly cookie and are only read by the
  // same-origin server proxy. Browser code must never access the bearer token.
  return null;
}

export function setToken(_token: string): void {
  // Kept as a no-op for old call sites; token persistence is server-owned.
}

export async function removeToken(): Promise<void> {
  if (typeof window !== 'undefined') await fetch('/api/admin/auth/logout', { method: 'POST', credentials: 'same-origin' });
}

export function isAuthenticated(): boolean {
  return false;
}

export function getAuthHeader(): null {
  return null;
}
