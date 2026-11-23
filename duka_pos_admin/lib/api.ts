import { showToast } from '@/lib/toast';

const API_URL = '';

class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

export async function fetchJson<T = unknown>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const method = (options.method ?? 'GET').toUpperCase();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> | undefined),
  };
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { ...options, headers, credentials: 'same-origin', cache: 'no-store' });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Network request failed';
    showToast('error', message);
    throw new ApiError(message, 0);
  }

  let body: unknown;
  let invalidJson = false;
  const contentType = res.headers.get('content-type') ?? '';
  if (contentType.includes('application/json') && res.status !== 204) {
    try {
      body = await res.json();
    } catch {
      body = null;
      invalidJson = true;
    }
  } else {
    body = await res.text();
  }

  if (!res.ok) {
    if (res.status === 401 && typeof window !== 'undefined') window.location.assign('/login');
    const responseMessage =
      body && typeof body === 'object' && 'error' in body
        ? String((body as { error?: unknown }).error)
        : res.statusText;
    const message = responseMessage || `Request failed (${res.status}).`;
    showToast('error', message || 'The request could not be completed.');
    throw new ApiError(message, res.status);
  }

  if (invalidJson) {
    const message = 'The server returned an invalid response.';
    showToast('error', message);
    throw new ApiError(message, res.status);
  }

  if (method !== 'GET' && method !== 'HEAD') showToast('success', successMessage(path, method));
  return body as T;
}

function successMessage(path: string, method: string): string {
  const route = path.split('?')[0];
  if (/\/billing\/subscriptions\/[^/]+$/.test(route)) return 'Subscription terms saved.';
  if (/\/billing\/vouchers\/[^/]+\/(?:pause|resume|revoke|delete)$/.test(route)) return 'Voucher updated.';
  if (/\/billing\/vouchers$/.test(route)) return 'Voucher created and emailed.';
  if (/\/billing\/provider$/.test(route)) return 'Payment destination saved.';
  if (/\/auth\/keys\/mint$/.test(route)) return 'Administrator key created.';
  if (/\/auth\/keys\/[^/]+$/.test(route)) return 'Administrator access updated.';
  if (method === 'DELETE') return 'Deleted successfully.';
  if (method === 'POST') return 'Action completed successfully.';
  return 'Changes saved successfully.';
}

export { ApiError, API_URL };
