export type WsMessageHandler = (data: unknown) => void;

const WS_URL =
  typeof process !== 'undefined' && process.env.NEXT_PUBLIC_API_URL
    ? process.env.NEXT_PUBLIC_API_URL.replace(/^http/i, 'ws')
    : 'ws://localhost:3000';

export class WebSocketClient {
  private url: string;
  private ws: WebSocket | null = null;
  private handlers = new Set<WsMessageHandler>();
  private reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private manuallyClosed = false;
  private pingTimer: ReturnType<typeof setInterval> | null = null;

  constructor(url: string = `${WS_URL}/api/live`) {
    this.url = url;
  }

  connect(): void {
    if (this.manuallyClosed) return;
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    try {
      this.ws = new WebSocket(this.url);
    } catch {
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.reconnectAttempts = 0;
      this.startPing();
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        this.handlers.forEach((h) => h(data));
      } catch {
        // ignore malformed messages
      }
    };

    this.ws.onclose = () => {
      this.stopPing();
      this.ws = null;
      if (!this.manuallyClosed) {
        this.scheduleReconnect();
      }
    };

    this.ws.onerror = () => {
      this.ws?.close();
    };
  }

  private scheduleReconnect(): void {
    if (this.manuallyClosed || this.reconnectAttempts >= this.maxReconnectAttempts) return;
    this.reconnectAttempts += 1;
    const delay = Math.min(1000 * 2 ** (this.reconnectAttempts - 1), 30000);
    this.reconnectTimeout = setTimeout(() => this.connect(), delay);
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: 'ping' }));
      }
    }, 30000);
  }

  private stopPing(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  subscribe(handler: WsMessageHandler): () => void {
    this.handlers.add(handler);
    this.connect();
    return () => {
      this.handlers.delete(handler);
      if (this.handlers.size === 0) {
        this.disconnect();
      }
    };
  }

  send(message: unknown): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  disconnect(): void {
    this.manuallyClosed = true;
    this.stopPing();
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.ws?.close();
    this.ws = null;
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

export const wsClient = new WebSocketClient();
