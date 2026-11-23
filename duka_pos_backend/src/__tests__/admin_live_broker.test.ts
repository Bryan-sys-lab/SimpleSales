import { describe, expect, it, vi } from 'vitest';
import {
  addAdminLiveClient,
  broadcastAdmin,
  removeAdminLiveClient,
  withAdminLivePublisher,
} from '../services/admin_live_broker';
import type { WebSocket } from 'ws';

describe('admin live publisher context', () => {
  it('publishes events within their request context without leaking between requests', async () => {
    const publish = vi.fn(async (_message: string) => undefined);

    await withAdminLivePublisher(publish, async () => {
      await broadcastAdmin({ type: 'session_activity' });
    });
    await broadcastAdmin({ type: 'outside_request' });

    expect(publish).toHaveBeenCalledOnce();
    expect(publish).toHaveBeenCalledWith('{"type":"session_activity"}');
  });

  it('delivers scoped events only to clients with the matching permission', async () => {
    const permittedSocket = { readyState: 1, OPEN: 1, send: vi.fn() } as unknown as WebSocket;
    const otherSocket = { readyState: 1, OPEN: 1, send: vi.fn() } as unknown as WebSocket;
    const permitted = { socket: permittedSocket, isSuperAdmin: false, permissions: ['sessions:read'] };
    const other = { socket: otherSocket, isSuperAdmin: false, permissions: ['analytics:read'] };
    addAdminLiveClient(permitted);
    addAdminLiveClient(other);

    await broadcastAdmin({
      type: 'telemetry_event_ingested',
      requiredPermission: 'sessions:read',
    });

    expect(permittedSocket.send).toHaveBeenCalledOnce();
    expect(otherSocket.send).not.toHaveBeenCalled();
    removeAdminLiveClient(permitted);
    removeAdminLiveClient(other);
  });
});
