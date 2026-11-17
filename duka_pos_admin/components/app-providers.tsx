'use client';

import { WebSocketProvider } from '@/components/websocket-provider';

export function AppProviders({ children }: { children: React.ReactNode }) {
  return <WebSocketProvider>{children}</WebSocketProvider>;
}
