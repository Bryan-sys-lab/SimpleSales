'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { isAdminLiveResource, resourcesForLiveMessage, type AdminLiveResource } from '@/lib/admin-live';
import { wsClient } from '@/lib/ws';

interface WebSocketProviderProps {
  children: React.ReactNode;
}

interface WebSocketContextValue {
  connected: boolean;
  activity: LiveActivity[];
  subscribeResources: (resources: AdminLiveResource[], handler: () => void) => () => void;
}

type LiveActivity = { id: string; label: string; at: string; detail: string };
type ResourceHandler = { resources: Set<AdminLiveResource>; handler: () => void };

const WebSocketContext = createContext<WebSocketContextValue | null>(null);

export function WebSocketProvider({ children }: WebSocketProviderProps) {
  const [connected, setConnected] = useState(wsClient.isConnected());
  const [activity, setActivity] = useState<LiveActivity[]>([]);
  const handlersRef = useRef<Set<ResourceHandler>>(new Set());

  const subscribeResources = useCallback((resources: AdminLiveResource[], handler: () => void) => {
    const subscription = { resources: new Set(resources), handler };
    handlersRef.current.add(subscription);
    return () => handlersRef.current.delete(subscription);
  }, []);

  useEffect(() => {
    const unsubscribe = wsClient.subscribe((data) => {
      const resources = resourcesForLiveMessage(data);
      if (resources.length > 0) {
        handlersRef.current.forEach((subscription) => {
          if (resources.some((resource) => subscription.resources.has(resource))) {
            subscription.handler();
          }
        });
      }
      if (!data || typeof data !== 'object') return;
      const message = data as {
        type?: unknown;
        events?: unknown;
        at?: unknown;
        deviceId?: unknown;
        entries?: unknown;
      };
      if (message.type === 'telemetry_event_ingested' && Array.isArray(message.events)) {
        const events = message.events.filter((event): event is { id: string; name: string; at: string } =>
          Boolean(event) && typeof event === 'object' &&
          typeof (event as { id?: unknown }).id === 'string' &&
          typeof (event as { name?: unknown }).name === 'string' &&
          typeof (event as { at?: unknown }).at === 'string',
        );
        setActivity((current) => [
          ...events.map((event) => ({
            id: event.id,
            label: event.name.replaceAll('_', ' '),
            at: event.at,
            detail: 'App event received',
          })),
          ...current,
        ].slice(0, 20));
      } else if (message.type === 'device_diagnostic_reported') {
        const entries = Array.isArray(message.entries) ? message.entries.length : 0;
        setActivity((current) => [{
          id: `diagnostic:${String(message.at)}:${String(message.deviceId)}`,
          label: 'Device diagnostic reported',
          at: typeof message.at === 'string' ? message.at : new Date().toISOString(),
          detail: `${entries} new entries`,
        }, ...current].slice(0, 20));
      }
    });
    const unsubscribeStatus = wsClient.subscribeStatus(setConnected);

    wsClient.connect();

    return () => {
      unsubscribe();
      unsubscribeStatus();
    };
  }, []);

  const value: WebSocketContextValue = {
    connected,
    activity,
    subscribeResources,
  };

  return (
    <WebSocketContext.Provider value={value}>
      {children}
    </WebSocketContext.Provider>
  );
}

export function useAdminLiveRefresh(
  refresh: () => void | Promise<void>,
  resources: AdminLiveResource[],
  enabled = true,
): void {
  const { connected, subscribeResources } = useWebSocket();
  const refreshRef = useRef(refresh);
  const hasConnected = useRef(false);
  const resourceKey = resources.join('|');
  const stableResources = useMemo(
    () => resourceKey.split('|').filter(isAdminLiveResource),
    [resourceKey],
  );

  useEffect(() => { refreshRef.current = refresh; }, [refresh]);

  useEffect(() => {
    if (!enabled) return;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const unsubscribe = subscribeResources(stableResources, () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        void refreshRef.current();
      }, 300);
    });
    return () => {
      if (timer) clearTimeout(timer);
      unsubscribe();
    };
  }, [enabled, stableResources, subscribeResources]);

  useEffect(() => {
    if (enabled && connected && hasConnected.current) void refreshRef.current();
    if (connected) hasConnected.current = true;
  }, [connected, enabled]);
}

export function useWebSocket(): WebSocketContextValue {
  const ctx = useContext(WebSocketContext);
  if (!ctx) {
    throw new Error('useWebSocket must be used within a WebSocketProvider');
  }
  return ctx;
}
