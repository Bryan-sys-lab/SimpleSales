'use client';

import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { WebSocketClient, wsClient } from '@/lib/ws';

interface WebSocketProviderProps {
  children: React.ReactNode;
}

interface WebSocketContextValue {
  client: WebSocketClient;
  connected: boolean;
  lastMessage: unknown | null;
  subscribe: (handler: (data: unknown) => void) => () => void;
  send: (message: unknown) => void;
}

const WebSocketContext = createContext<WebSocketContextValue | null>(null);

export function WebSocketProvider({ children }: WebSocketProviderProps) {
  const [connected, setConnected] = useState(wsClient.isConnected());
  const [lastMessage, setLastMessage] = useState<unknown | null>(null);
  const handlersRef = useRef<Set<(data: unknown) => void>>(new Set());

  const subscribe = useCallback((handler: (data: unknown) => void) => {
    handlersRef.current.add(handler);
    return () => {
      handlersRef.current.delete(handler);
    };
  }, []);

  const send = useCallback((message: unknown) => {
    wsClient.send(message);
  }, []);

  useEffect(() => {
    const unsubscribe = wsClient.subscribe((data) => {
      setLastMessage(data);
      handlersRef.current.forEach((h) => h(data));
    });

    const interval = setInterval(() => {
      setConnected(wsClient.isConnected());
    }, 1000);

    wsClient.connect();

    return () => {
      clearInterval(interval);
      unsubscribe();
    };
  }, []);

  const value: WebSocketContextValue = {
    client: wsClient,
    connected,
    lastMessage,
    subscribe,
    send,
  };

  return (
    <WebSocketContext.Provider value={value}>
      {children}
    </WebSocketContext.Provider>
  );
}

export function useWebSocket(): WebSocketContextValue {
  const ctx = useContext(WebSocketContext);
  if (!ctx) {
    throw new Error('useWebSocket must be used within a WebSocketProvider');
  }
  return ctx;
}
