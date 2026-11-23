import { AsyncLocalStorage } from 'node:async_hooks';
import type { WebSocket } from 'ws';

export type AdminLiveClient = { socket: WebSocket };
export type AdminLivePublisher = (message: string) => Promise<void>;

const clients = new Set<AdminLiveClient>();
const publisherStorage = new AsyncLocalStorage<AdminLivePublisher>();

export function withAdminLivePublisher<T>(publisher: AdminLivePublisher, callback: () => T): T {
  return publisherStorage.run(publisher, callback);
}

export function addAdminLiveClient(client: AdminLiveClient): void {
  clients.add(client);
}

export function removeAdminLiveClient(client: AdminLiveClient): void {
  clients.delete(client);
}

export async function broadcastAdmin(message: unknown): Promise<void> {
  const encoded = JSON.stringify(message);
  for (const client of clients) {
    if (client.socket.readyState === client.socket.OPEN) {
      client.socket.send(encoded);
    }
  }
  const publishToWorkerClients = publisherStorage.getStore();
  if (publishToWorkerClients) {
    try {
      await publishToWorkerClients(encoded);
    } catch (error) {
      console.error('admin live broadcast failed', error);
    }
  }
}
