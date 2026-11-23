import { showToast } from '@/lib/toast';

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
  if (typeof window === 'undefined') return;
  try {
    const response = await fetch('/api/admin/auth/logout', { method: 'POST', credentials: 'same-origin' });
    if (!response.ok) throw new Error(response.statusText || 'Sign out failed.');
    showToast('success', 'Signed out successfully.');
  } catch (cause) {
    showToast('error', cause instanceof Error ? cause.message : 'Sign out failed.');
  }
}

export function isAuthenticated(): boolean {
  return false;
}

export function getAuthHeader(): null {
  return null;
}
