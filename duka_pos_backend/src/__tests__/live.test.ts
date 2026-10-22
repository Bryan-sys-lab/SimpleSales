// The change bus behind the live channel.
//
// The bus is where a write becomes a signal, so the properties under test are
// the ones a shop depends on: a signal arrives, a signal for a shop the
// listener does not run does not, a listener that throws does not take the
// channel down with it, and a listener that goes away stops being called.

import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  announceChange,
  concerns,
  createLiveEventBus,
  isLiveReason,
  liveBus,
  LIVE_REASONS,
  type LiveEvent,
} from '../lib/live.js';

describe('the bus', () => {
  it('delivers an event to every listener', () => {
    const bus = createLiveEventBus();
    const first: LiveEvent[] = [];
    const second: LiveEvent[] = [];
    bus.subscribe((event) => first.push(event));
    bus.subscribe((event) => second.push(event));
    bus.emit({ tenantIds: ['t1'], reason: 'sales' });
    expect(first).toHaveLength(1);
    expect(second).toHaveLength(1);
    expect(first[0]).toMatchObject({ tenantIds: ['t1'], reason: 'sales' });
  });

  it('stamps every event with the server clock', () => {
    const bus = createLiveEventBus(() => new Date('2026-10-10T12:00:00.000Z'));
    const seen: LiveEvent[] = [];
    bus.subscribe((event) => seen.push(event));
    bus.emit({ tenantIds: ['t1'], reason: 'sales' });
    // So a client can tell a fresh signal from one it has already acted on.
    expect(seen[0].at).toBe('2026-10-10T12:00:00.000Z');
  });

  it('carries no business data, only which tenant and why', () => {
    const bus = createLiveEventBus();
    const seen: LiveEvent[] = [];
    bus.subscribe((event) => seen.push(event));
    bus.emit({ tenantIds: ['t1'], reason: 'stock' });
    // The figures come from the read the signal triggers. A bus that carried
    // payloads would be a second copy of the ledger to keep honest.
    expect(Object.keys(seen[0]).sort()).toEqual(['at', 'reason', 'tenantIds']);
  });

  it('stops calling a listener that has unsubscribed', () => {
    const bus = createLiveEventBus();
    const seen: LiveEvent[] = [];
    const unsubscribe = bus.subscribe((event) => seen.push(event));
    unsubscribe();
    bus.emit({ tenantIds: ['t1'], reason: 'sales' });
    expect(seen).toHaveLength(0);
    expect(bus.listenerCount()).toBe(0);
  });

  it('does nothing at all with no listeners, which is the common case', () => {
    // The warm-up path: a shop syncing with nobody streaming must not pay for
    // fan-out it cannot use.
    const bus = createLiveEventBus();
    expect(() => bus.emit({ tenantIds: ['t1'], reason: 'sales' })).not.toThrow();
  });

  it('survives a listener that throws', () => {
    const bus = createLiveEventBus();
    const after: LiveEvent[] = [];
    bus.subscribe(() => {
      throw new Error('socket went away mid-write');
    });
    bus.subscribe((event) => after.push(event));
    // A dead stream is the most likely failure there is, and it must not take
    // the next listener — a live till — with it.
    expect(() => bus.emit({ tenantIds: ['t1'], reason: 'sales' })).not.toThrow();
    expect(after).toHaveLength(1);
  });

  it('counts its listeners for the log line that says a channel is alive', () => {
    const bus = createLiveEventBus();
    expect(bus.listenerCount()).toBe(0);
    bus.subscribe(() => {});
    bus.subscribe(() => {});
    expect(bus.listenerCount()).toBe(2);
  });
});

describe('tenant scoping', () => {
  const of = (...ids: string[]) => new Set(ids);

  it('matches a listed tenant exactly', () => {
    expect(concerns({ tenantIds: ['t1', 't2'], reason: 'sales', at: '' }, of('t2'))).toBe(true);
    expect(concerns({ tenantIds: ['t1', 't2'], reason: 'sales', at: '' }, of('t3'))).toBe(false);
  });

  it('treats an empty tenant list as platform-wide', () => {
    // A settings change applies to every till, so every stream is told.
    expect(concerns({ tenantIds: [], reason: 'settings', at: '' }, of('t1'))).toBe(true);
  });

  it('does not match a tenant the listener never subscribed to', () => {
    expect(concerns({ tenantIds: ['t1'], reason: 'sales', at: '' }, of())).toBe(false);
  });
});

describe('reasons', () => {
  it('is a closed set, so the phone never meets a reason it has not seen', () => {
    // The set grew when the till started writing its own records: a drawer
    // that was counted, a sale that came back, a delivery that arrived and a
    // cup that was set up are all changes the phone has a screen for.
    expect([...LIVE_REASONS].sort()).toEqual([
      'products',
      'purchases',
      'returns',
      'sales',
      'settings',
      'shifts',
      'shot-cups',
      'stock',
    ]);
    expect(isLiveReason('sales')).toBe(true);
    expect(isLiveReason('everything')).toBe(false);
    expect(isLiveReason(7)).toBe(false);
  });

  it('refuses to guess a reason out of a string that is not one', () => {
    // The signal is what the client's telemetry counts; a reason that came
    // from nowhere is worse than no reason.
    expect(isLiveReason('')).toBe(false);
  });
});

describe('the shared bus routes use', () => {
  beforeEach(() => {
    // The route tests inject their own bus; the shared one must not accumulate
    // listeners across files.
  });

  it('announces onto the one bus the channel subscribes to', () => {
    const seen: LiveEvent[] = [];
    const unsubscribe = liveBus.subscribe((event) => seen.push(event));
    try {
      announceChange(['t1'], 'sales');
      expect(seen).toHaveLength(1);
      expect(seen[0]).toMatchObject({ tenantIds: ['t1'], reason: 'sales' });
    } finally {
      unsubscribe();
    }
    expect(seen).toHaveLength(1);
  });

  it('lets a route emit without importing a spy', () => {
    const spy = vi.fn();
    const unsubscribe = liveBus.subscribe(spy);
    announceChange(['t9'], 'stock');
    unsubscribe();
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0][0]).toMatchObject({ tenantIds: ['t9'], reason: 'stock' });
  });
});
