export type WsMessageHandler = (data: unknown) => void;

function liveUrl(configured: string, ticket: string): string {
  const url = new URL(configured);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.pathname = '/api/admin/live';
  url.search = new URLSearchParams({ ticket }).toString();
  return url.toString();
}

export class WebSocketClient {
  private ws: WebSocket | null = null;
  private handlers = new Set<WsMessageHandler>();
  private reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 6;
  private manuallyClosed = false;
  private connecting = false;
  private pingTimer: ReturnType<typeof setInterval> | null = null;

  connect(): void {
    if (this.manuallyClosed || this.connecting || (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING))) return;
    this.connecting = true;
    void Promise.all([
      fetch('/api/admin/auth/ws-ticket', { method: 'POST', credentials: 'same-origin', headers: { 'content-type': 'application/json' }, body: '{}' }),
      fetch('/api/admin/auth/ws-url', { credentials: 'same-origin', cache: 'no-store' }),
    ]).then(async ([ticketResponse, urlResponse]) => {
        if (!ticketResponse.ok || !urlResponse.ok) throw new Error('Live session unavailable');
        const [data, address] = await Promise.all([ticketResponse.json(), urlResponse.json()]) as [{ ticket?: string }, { url?: string }];
        if (!data.ticket || !address.url || this.manuallyClosed) throw new Error('Live ticket unavailable');
        this.ws = new WebSocket(liveUrl(address.url, data.ticket));
        this.ws.onopen = () => { this.reconnectAttempts = 0; this.startPing(); };
        this.ws.onmessage = event => {
          try { const data = JSON.parse(event.data); this.handlers.forEach(handler => handler(data)); } catch { /* Ignore malformed optional signals. */ }
        };
        this.ws.onclose = () => { this.stopPing(); this.ws = null; if (!this.manuallyClosed) this.scheduleReconnect(); };
        this.ws.onerror = () => this.ws?.close();
      })
      .catch(() => this.scheduleReconnect())
      .finally(() => { this.connecting = false; });
  }

  private scheduleReconnect(): void {
    if (this.manuallyClosed || this.reconnectAttempts >= this.maxReconnectAttempts || this.reconnectTimeout) return;
    this.reconnectAttempts += 1;
    this.reconnectTimeout = setTimeout(() => { this.reconnectTimeout = null; this.connect(); }, Math.min(1000 * 2 ** (this.reconnectAttempts - 1), 30000));
  }
  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ type: 'ping' })); }, 30000);
  }
  private stopPing(): void { if (this.pingTimer) clearInterval(this.pingTimer); this.pingTimer = null; }
  subscribe(handler: WsMessageHandler): () => void {
    this.manuallyClosed = false; this.handlers.add(handler); this.connect();
    return () => { this.handlers.delete(handler); if (!this.handlers.size) this.disconnect(); };
  }
  send(message: unknown): void { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(message)); }
  disconnect(): void {
    this.manuallyClosed = true; this.stopPing();
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
    this.reconnectTimeout = null; this.ws?.close(); this.ws = null;
  }
  isConnected(): boolean { return this.ws?.readyState === WebSocket.OPEN; }
}

export const wsClient = new WebSocketClient();
