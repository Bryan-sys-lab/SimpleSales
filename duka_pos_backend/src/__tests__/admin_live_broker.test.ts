import { describe, expect, it, vi } from 'vitest';
import { broadcastAdmin, withAdminLivePublisher } from '../services/admin_live_broker';

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
});
