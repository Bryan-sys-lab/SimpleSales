export type ToastKind = 'success' | 'error';

export type ToastNotice = {
  id: number;
  kind: ToastKind;
  message: string;
};

type ToastListener = (notice: ToastNotice) => void;

const listeners = new Set<ToastListener>();
let pendingNotices: ToastNotice[] = [];
let nextToastId = 0;

export function showToast(kind: ToastKind, message: string): void {
  const text = message.trim();
  if (!text || typeof window === 'undefined') return;
  const notice = { id: ++nextToastId, kind, message: text };
  if (listeners.size === 0) {
    pendingNotices = [...pendingNotices.slice(-3), notice];
    return;
  }
  listeners.forEach((listener) => listener(notice));
}

export function subscribeToToasts(listener: ToastListener): () => void {
  listeners.add(listener);
  const pending = pendingNotices;
  pendingNotices = [];
  pending.forEach(listener);
  return () => listeners.delete(listener);
}
