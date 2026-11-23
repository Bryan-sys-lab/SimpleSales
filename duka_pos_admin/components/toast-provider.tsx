'use client';

import { useEffect, useRef, useState } from 'react';
import { subscribeToToasts, ToastNotice } from '@/lib/toast';

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastNotice[]>([]);
  const [minimized, setMinimized] = useState<Set<number>>(() => new Set());
  const timers = useRef(new Map<number, number>());

  useEffect(() => {
    const activeTimers = timers.current;
    const unsubscribe = subscribeToToasts((notice) => {
      setToasts((current) => [...current.filter((toast) => toast.id !== notice.id), notice].slice(-4));
      setMinimized((current) => {
        const next = new Set(current);
        next.delete(notice.id);
        return next;
      });
      const previousTimer = activeTimers.get(notice.id);
      if (previousTimer !== undefined) window.clearTimeout(previousTimer);
      const timer = window.setTimeout(() => {
        setToasts((current) => current.filter((toast) => toast.id !== notice.id));
        setMinimized((current) => {
          const next = new Set(current);
          next.delete(notice.id);
          return next;
        });
        activeTimers.delete(notice.id);
      }, notice.kind === 'error' ? 7000 : 4500);
      activeTimers.set(notice.id, timer);
    });
    return () => {
      unsubscribe();
      activeTimers.forEach((timer) => window.clearTimeout(timer));
      activeTimers.clear();
    };
  }, []);

  function dismiss(id: number) {
    const timer = timers.current.get(id);
    if (timer !== undefined) window.clearTimeout(timer);
    timers.current.delete(id);
    setToasts((current) => current.filter((toast) => toast.id !== id));
    setMinimized((current) => {
      const next = new Set(current);
      next.delete(id);
      return next;
    });
  }

  function toggleMinimized(id: number) {
    setMinimized((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <>
      {children}
      <div
        className="pointer-events-none fixed inset-x-0 z-[2147483647] mx-auto flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-2 px-0 sm:inset-x-auto sm:right-4 sm:mx-0"
        style={{ top: 'max(1rem, env(safe-area-inset-top))' }}
        aria-label="Notifications"
      >
        {toasts.map((toast) => (
          (() => {
            const isMinimized = minimized.has(toast.id);
            return (
          <div
            key={toast.id}
            role={toast.kind === 'error' ? 'alert' : 'status'}
            aria-live={toast.kind === 'error' ? 'assertive' : 'polite'}
            aria-atomic="true"
            className={`pointer-events-auto flex items-start gap-3 rounded-xl border text-sm shadow-xl ${
              isMinimized ? 'p-2.5' : 'p-4'
            } ${
              toast.kind === 'success'
                ? 'border-sage-200 bg-sage-50 text-sage-900 dark:border-sage-700 dark:bg-sage-950 dark:text-sage-100'
                : 'border-coral-200 bg-coral-50 text-coral-900 dark:border-coral-700 dark:bg-coral-950 dark:text-coral-100'
            }`}
          >
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{toast.kind === 'success' ? 'Success' : 'Something went wrong'}</p>
              <p className={`break-words ${isMinimized ? 'line-clamp-1' : 'mt-0.5'}`}>{toast.message}</p>
            </div>
            <div className="flex shrink-0 items-center gap-1">
              <button
                type="button"
                className="min-h-8 rounded px-2 text-xs font-semibold underline underline-offset-2"
                aria-label={isMinimized ? 'Expand notification' : 'Minimize notification'}
                aria-expanded={!isMinimized}
                onClick={() => toggleMinimized(toast.id)}
              >
                {isMinimized ? 'Expand' : 'Minimize'}
              </button>
              <button
                type="button"
                className="min-h-8 rounded px-2 text-xs font-semibold underline underline-offset-2"
                aria-label="Dismiss notification"
                onClick={() => dismiss(toast.id)}
              >
                Dismiss
              </button>
            </div>
          </div>
            );
          })()
        ))}
      </div>
    </>
  );
}
