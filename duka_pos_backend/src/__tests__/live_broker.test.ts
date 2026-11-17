import { describe, expect, it } from 'vitest';
import {
  addLiveClient,
  broadcastTenantChange,
  removeLiveClient,
} from '../services/live_broker';

function socket() {
  const sent: string[] = [];
  return {
    sent,
    OPEN: 1,
    readyState: 1,
    send(value: string) { sent.push(value); },
  } as any;
}

describe('tenant live broker', () => {
  it('does not deliver one shop change to another shop', () => {
    const shopA = socket();
    const shopB = socket();
    const clientA = { socket: shopA, tenantId: 'shop-a' };
    const clientB = { socket: shopB, tenantId: 'shop-b' };
    addLiveClient(clientA);
    addLiveClient(clientB);

    try {
      broadcastTenantChange('shop-a', ['sales']);

      expect(shopA.sent).toHaveLength(1);
      expect(JSON.parse(shopA.sent[0])).toMatchObject({
        type: 'snapshot',
        reasons: ['sales'],
      });
      expect(shopB.sent).toHaveLength(0);
    } finally {
      removeLiveClient(clientA);
      removeLiveClient(clientB);
    }
  });

  it('skips sockets that have already closed', () => {
    const closed = socket();
    closed.readyState = 3;
    const client = { socket: closed, tenantId: 'shop-a' };
    addLiveClient(client);
    try {
      broadcastTenantChange('shop-a');
      expect(closed.sent).toHaveLength(0);
    } finally {
      removeLiveClient(client);
    }
  });
});

