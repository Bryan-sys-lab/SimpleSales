// The change signal behind the live channel.
//
// WS replaces polling for exactly one thing: knowing WHEN to read. Everything
// else still happens over HTTP. So this file is a signal, not a transport —
// it carries "something in this tenant changed, go and read it", never the
// changed data itself. Keeping the payload out of the bus is what keeps it
// cheap, and it is also why a stale notification is harmless: the reader
// re-reads the truth, and the notification was only ever a hint.
//
// Deliberately NOT persisted and deliberately NOT cross-process. When the
// deployment grows past one instance this becomes a Redis channel with the
// same three functions, and nothing above this file changes.

/** One "go and look again" signal. */
export type LiveEvent = {
  /** The shops the change belongs to. A write that touches one shop signals
   * one shop, and a client subscribed to another never hears about it. */
  tenantIds: string[];
  /** Why the read is worth doing, for the log and for the client's own
   * telemetry. Never user data. */
  reason: string;
  /** Server clock, so a client can tell a fresh signal from a replay. */
  at: string;
};

export type LiveSubscriber = (event: LiveEvent) => void;

/**
 * A one-way, in-process fan-out.
 *
 * Listeners are matched per tenant at emit time rather than at subscribe
 * time, so a shop that gains a second till does not have to re-subscribe for
 * it to be included — and, more importantly, so a listener cannot "forget" to
 * handle a shop it was subscribed to.
 */
export interface LiveEventBus {
  subscribe(listener: LiveSubscriber): () => void;
  emit(event: Omit<LiveEvent, 'at'>): void;
  /** How many listeners are attached. Asserted in tests, and useful in a log
   * line when a stream that should be alive is not. */
  listenerCount(): number;
}

export function createLiveEventBus(clock: () => Date = () => new Date()): LiveEventBus {
  const listeners = new Set<LiveSubscriber>();
  return {
    subscribe(listener: LiveSubscriber) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    emit(event) {
      if (listeners.size === 0) return;
      const stamp: LiveEvent = { ...event, at: clock().toISOString() };
      for (const listener of [...listeners]) {
        try {
          listener(stamp);
        } catch {
          // A listener that throws (a socket that died mid-write) must not
          // take the bus with it, and must not stop the signal reaching the
          // listener after it.
        }
      }
    },
    listenerCount() {
      return listeners.size;
    },
  };
}

/**
 * The shared bus.
 *
 * A route emits onto this after its write; the live channel subscribes to it.
 * Both sides talk to the same instance rather than to a singleton that one of
 * them cannot replace in a test — the channel accepts an injected bus, so the
 * routes are the only side that needs this one.
 */
export const liveBus: LiveEventBus = createLiveEventBus();

/**
 * Signals that a shop's data changed and its streams should re-read.
 *
 * Cheap by design: no payload, so a write pays one small fan-out and the
 * readers decide what the change means. Called by a route AFTER its write
 * lands — the same "after the fact" rule the audit rows follow, and for the
 * same reason: a stream told about a write that failed is a stream chasing a
 * change that never happened.
 */
export function announceChange(tenantIds: string[], reason: LiveReason): void {
  liveBus.emit({ tenantIds, reason });
}

/**
 * Whether an event concerns a shop a subscriber is watching.
 *
 * An event with no tenant ids is a platform-wide signal — a settings change
 * that applies everywhere — and every subscriber is told. An event with ids is
 * matched exactly.
 */
export function concerns(event: LiveEvent, tenantIds: ReadonlySet<string>): boolean {
  if (event.tenantIds.length === 0) return true;
  return event.tenantIds.some((id) => tenantIds.has(id));
}

/** The reasons a client may be told to re-read. A closed set, so the phone's
 * UI never has to guess at a string nobody has seen before.
 *
 * `shifts`, `returns`, `purchases` and `shot-cups` are here because the till
 * now writes all four: a drawer that was counted, a sale that came back, a
 * delivery that arrived, and a cup that was set up. Each is a change the
 * phone has a screen for, so each is a reason to re-read. */
export const LIVE_REASONS = [
  'products',
  'stock',
  'sales',
  'settings',
  'shifts',
  'returns',
  'purchases',
  'shot-cups',
] as const;

export type LiveReason = (typeof LIVE_REASONS)[number];

export function isLiveReason(value: unknown): value is LiveReason {
  return typeof value === 'string' && (LIVE_REASONS as readonly string[]).includes(value);
}
