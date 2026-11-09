// M-Pesa Till / Paybill matching — the SERVER side of feature 12.
//
// ## THE SHAPE OF IT
//
// A customer pays to the shop's Till over the counter. M-Pesa tells the
// BACKEND (the one public path in this file); the tills then list, claim,
// and reconcile against sales. Two rules above all:
//
//   1. The transaction code is the truth, and the truth arrives more than
//      once — the confirmation callback re-delivers on retries — so storing
//      is IDEMPOTENT by the code. A payment row exists exactly once on the
//      whole server, whatever the webhook does.
//   2. A payment funds exactly ONE sale. The claim is an ATOMIC count-move —
//      the row updates only while it is still `unclaimed` — so two phones
//      tapping the same payment produce exactly one winner and one clean
//      409 for the loser, with who won and when.
//
// The payer label is masked in this file, at the entry point: a first name
// and the last three digits. A till phone therefore can never leak a full
// paying number, because it never holds one (spec 12.6.4).

import express from 'express';
import { randomBytes, timingSafeEqual } from 'crypto';
import type { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { asyncHandler, HttpError, requireUser } from '../lib/http';
import { log } from '../lib/observability';

let mpesaPaymentNotifier: (() => void) | null = null;

export function setMpesaPaymentNotifier(notifier: (() => void) | null): void {
  mpesaPaymentNotifier = notifier;
}

/** Fields a QUEUED list hands a till: minimal, masked, no claim secrets. */
export const mpesaIncomingListSelect = {
  remoteId: true,
  transId: true,
  amount: true,
  payerLabel: true,
  billRef: true,
  receivedAt: true,
  status: true,
} as const;

/** What a claimed row names, so a losing device can read the conflict. */
export const mpesaClaimedFields = {
  status: true,
  claimedByDevice: true,
  claimedSaleUuid: true,
  claimedAt: true,
} as const;

/**
 * The masked label the server keeps instead of a payer's phone number: the
 * first name and the LAST THREE digits of the paying number (spec 12.3).
 * Both inputs come from the callback; neither a full name nor anything past
 * the last three digits of the number surfaces here.
 */
export function maskPayerLabel(name: unknown, phone: unknown): string {
  const text = typeof name === 'string' ? name.trim() : '';
  const first = text === '' ? '?' : text.split(/\s+/)[0].slice(0, 20);
  const digits = typeof phone === 'string' ? phone.replace(/\D/g, '') : '';
  const lastThree = digits.length >= 3 ? digits.slice(-3) : '***';
  return `${first} ···${lastThree}`;
}

/** The callback's shared secret, when the deployment configured one. */
function callbackKeyBytes(): Buffer | undefined {
  const key = process.env.MPESA_CALLBACK_KEY;
  if (!key) return undefined;
  return Buffer.from(key, 'utf8');
}

/** Constant-time compare, so a wrong key costs the same as a right one. */
export function callbackKeyMatches(header: unknown): boolean {
  const secret = callbackKeyBytes();
  if (secret === undefined) {
    // No key configured: the surface CANNOT be public safely, so nothing is
    // accepted — a loud refusal beats a silent open webhook.
    return false;
  }
  const given =
    typeof header === 'string' && header.trim() !== ''
      ? Buffer.from(header.trim(), 'utf8')
      : undefined;
  if (given === undefined || given.length !== secret.length) {
    // Compare anyway, against the secret, so the timing does not say length.
    timingSafeEqual(secret, secret);
    return false;
  }
  return timingSafeEqual(secret, given);
}

/**
 * The public C2B surface.
 *
 * Mounted OUTSIDE the OIDC wall (a callback has no user to authenticate), and
 * instead checked by the shared callback key. Both handlers answer 200 on
 * VALIDATION — Daraja expects the route alive on validation — and reject
 * everything else by the key alone.
 */
export const mpesaWebhookRoutes = express.Router();

/**
 * POST /validation — Daraja's "may this transaction proceed?". Accept the
 * transaction; the matching decision belongs to the SHOP, whose amounts on
 * screen and on invoice live there. The callback key still applies.
 */
mpesaWebhookRoutes.post('/validation', (req, res) => {
  if (!callbackKeyMatches(req.headers['x-callback-key'])) {
    res.status(401).json({ error: 'Not accepted' });
    return;
  }
  res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
});

/**
 * POST /confirmation — the money has moved; record it, idempotently.
 *
 * The payload shape comes from Safaricom's confirmation body; whatever else
 * it carries is ignored, because the fields the app needs are the code, the
 * amount, the payer, the account reference and the time.
 */
mpesaWebhookRoutes.post(
  '/confirmation',
  asyncHandler(async (req, res): Promise<void> => {
    if (!callbackKeyMatches(req.headers['x-callback-key'])) {
      res.status(401).json({ error: 'Not accepted' });
      return;
    }
    const body = (req.body ?? {}) as Record<string, unknown>;
    const transId = typeof body.TransID === 'string' ? body.TransID.trim() : '';
    const amount = Number(body.TransAmount);
    const tenantId =
      // The tenant is decided by the ACCOUNT the money paid into: the Till
      // number maps to one shop. A deployment names the map here; the stub
      // below keys on the bill reference when the deployment has told us its
      // shortcode-to-tenant binding through the environment, and refuses
      // everything else rather than guess.
      resolveTenantForCallback(body);

    if (transId === '') {
      res.status(400).json({ error: 'TransID required' });
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      res.status(400).json({ error: 'TransAmount must be a positive number' });
      return;
    }
    if (tenantId === undefined) {
      res.status(400).json({ error: 'No tenant for this payment' });
      return;
    }

    const receivedAt = readCallbackTime(body.TransTime);

    const prior = await prisma.mpesaIncoming.findUnique({ where: { transId } });
    const payment = await prisma.mpesaIncoming.upsert({
      where: { transId },
      create: {
        tenantId,
        remoteId: `c2b-${transId}`,
        transId,
        amount,
        payerLabel:
          maskPayerLabel(body.FirstName ?? body.payer, body.MSISDN ?? body.payer ?? body.PhoneNumber),
        billRef:
          typeof body.BillRefNumber === 'string' && body.BillRefNumber.trim() !== ''
            ? body.BillRefNumber.trim()
            : null,
        receivedAt,
      },
      // A duplicate delivery changes NOTHING: the first sighting is the
      // fact, and a second one saying it again is the same fact.
      update: {},
    });

    log('info', 'mpesa.c2b.recorded', { transId, tenantId });
    if (!prior) mpesaPaymentNotifier?.();

    res.json({ ResultCode: 0, ResultDesc: 'Accepted', stored: payment.status });
  }),
);

/**
 * Which shop this payment belongs to, from the callback's account reference.
 *
 * An unbound callback is refused rather than filed under a guess: a payment
 * credited to the WRONG shop is worse than an uncredited one, because only
 * one of those is a reconciliation gap and the other is a wrong ledger.
 */
export function resolveTenantForCallback(body: Record<string, unknown>):
  | string
  | undefined {
  const mapRaw = process.env.MPESA_TILL_TENANTS;
  if (!mapRaw) return undefined;
  const reference =
    typeof body.BillRefNumber === 'string' ? body.BillRefNumber.trim() : '';
  const shortcode =
    typeof body.BusinessShortCode === 'string' ? body.BusinessShortCode.trim() : '';
  const pairs = mapRaw
    .split(',')
    .map((pair) => pair.trim())
    .filter((pair) => pair !== '');
  for (const pair of pairs) {
    const [shortcodeKey, tenantId] = pair.split('=').map((part) => part.trim());
    if (shortcodeKey === shortcode && tenantId !== '') return tenantId;
  }
  // A Paybill shop keys on the customer's account reference prefix, which
  // the deployment names the same way (`TENANTPREFIX:tenant-id`).
  for (const pair of pairs) {
    const [prefixKey, tenantId] = pair.split('=').map((part) => part.trim());
    if (prefixKey.startsWith('ref:') && tenantId !== '' &&
        reference.startsWith(prefixKey.slice(4))) {
      return tenantId;
    }
  }
  return undefined;
}

/** The callback's time: Safaricom's `yyMMddHHmmss`, to an ISO instant. */
export function readCallbackTime(raw: unknown): Date {
  const digits = typeof raw === 'string' ? raw.replace(/\D/g, '') : '';
  if (digits.length === 14) {
    const year = Number(`20${digits.slice(0, 2)}`);
    const month = Number(digits.slice(2, 4)) - 1;
    const day = Number(digits.slice(4, 6));
    const hour = Number(digits.slice(6, 8));
    const minute = Number(digits.slice(8, 10));
    const second = Number(digits.slice(10, 12));
    const parsed = new Date(Date.UTC(year, month, day, hour, minute, second));
    if (!Number.isNaN(parsed.valueOf())) return parsed;
  }
  return new Date();
}

/** The authenticated tills' surface. */
export const mpesaRoutes = express.Router();

/**
 * GET /api/mpesa/incoming?since=<remoteId>&status=<status>
 *
 * The list the payment sheet reads inside its match window, newest first,
 * and the Sync Center's unclaimed count. `since` is the REMOTE id of the
 * last row the device saw — cursored, so a phone that was offline for an
 * hour catches every payment it missed exactly once, oldest to newest,
 * instead of whatever the newest pull happened to hand it (spec P0-15's
 * lesson, applied to this stream).
 */
mpesaRoutes.get(
  '/incoming',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    const status =
      typeof req.query.status === 'string' &&
      ['unclaimed', 'claimed', 'ignored', 'expired'].includes(req.query.status)
        ? req.query.status
        : 'unclaimed';
    const since = typeof req.query.since === 'string' ? req.query.since : null;
    const limit = Math.min(Number(req.query.limit ?? 200) || 200, 500);

    // Cursor by creation order: rows beyond the cursor, in the direction the
    // pull walks (newest for the live list; oldest-to-newest for the catch-up
    // is the same SQL — the caller orders its rendering).
    const where: Prisma.MpesaIncomingWhereInput = {
      tenantId: user.tenantId,
      status,
      createdAt: since
        ? { gt: (await prisma.mpesaIncoming.findUnique({ where: { remoteId: since } }))
              ?.createdAt ?? new Date(0) }
        : undefined,
    };
    const rows = await prisma.mpesaIncoming.findMany({
      where,
      select: mpesaIncomingListSelect,
      orderBy: { receivedAt: 'desc' },
      take: limit,
    });
    res.json({
      status: 'ok',
      cursor:
        rows.length > 0
          ? [...rows].sort((a, b) =>
              a.receivedAt.getTime() < b.receivedAt.getTime() ? 1 : -1,
            )[0].remoteId
          : since,
      payments: rows,
    });
  }),
);

/**
 * POST /api/mpesa/incoming/:remoteId/claim { sale_uuid }
 *
 * ONE payment, ONE sale. The update predicate carries `status = 'unclaimed'`
 * INSIDE the query, so the race between two devices resolves at the
 * database, not at whoever is later: exactly one caller sees count === 1,
 * the other reads a conflict and is told who holds the money and since when.
 *
 * Re-claiming the SAME sale is a no-op success (the device retrying after a
 * drop), per the spec's idempotency rule 5.
 */
mpesaRoutes.post(
  '/incoming/:id/claim',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    const remoteId = String(req.params.id ?? '');
    const saleUuid = String((req.body as { sale_uuid?: unknown }).sale_uuid ?? '');
    if (remoteId === '' || saleUuid === '') {
      res.status(400).json({ error: 'Remote id and sale uuid are required' });
      return;
    }
    const existing = await prisma.mpesaIncoming.findUnique({
      where: { remoteId },
    });
    if (!existing || existing.tenantId !== user.tenantId) {
      res.status(404).json({ error: 'No such payment' });
      return;
    }
    if (existing.status === 'claimed' && existing.claimedSaleUuid === saleUuid) {
      // The SAME device asking again after its request died in flight.
      res.json({ status: 'ok', claimed: true, payment: existing });
      return;
    }
    if (existing.status !== 'unclaimed') {
      res.status(409).json({
        error: 'This payment has already been taken',
        how: 'conflict',
        claimed_by: existing.claimedByDevice,
        claimed_at: existing.claimedAt,
        claimed_sale: existing.claimedSaleUuid,
      });
      return;
    }
    const claimed = await prisma.mpesaIncoming.updateMany({
      where: { remoteId, status: 'unclaimed' },
      data: {
        status: 'claimed',
        claimedByDevice: (req.body as { device?: string }).device ??
          'unknown-device',
        claimedSaleUuid: saleUuid,
        claimedAt: new Date(),
      },
    });
    if (claimed.count !== 1) {
      // Lost the race between the read and the write.
      const state = await prisma.mpesaIncoming.findUnique({
        where: { remoteId },
        select: mpesaClaimedFields,
      });
      res.status(409).json({
        error: 'This payment has already been taken',
        how: 'conflict-race',
        claimed_by: state?.claimedByDevice,
        claimed_at: state?.claimedAt,
        claimed_sale: state?.claimedSaleUuid,
      });
      return;
    }
    const payment = await prisma.mpesaIncoming.findUnique({ where: { remoteId } });
    res.json({ status: 'ok', claimed: true, payment });
  }),
);

/**
 * POST /api/mpesa/incoming/:remoteId/ignore { reason }
 *
 * Managers only. A payment that will not attach to a sale — a wrong amount,
 * a customer who changed their mind — is set aside WITH the reason, so the
 * shop's books can say what happened to money M-Pesa says arrived.
 */
mpesaRoutes.post(
  '/incoming/:id/ignore',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    if (user.role !== 'manager' && user.role !== 'admin') {
      throw new HttpError(403, 'Only a manager can set a payment aside');
    }
    const remoteId = String(req.params.id ?? '');
    const reason = String((req.body as { reason?: unknown }).reason ?? '').trim();
    if (reason === '') {
      res.status(400).json({ error: 'A reason is required' });
      return;
    }
    const ignored = await prisma.mpesaIncoming.updateMany({
      where: { remoteId, tenantId: user.tenantId, status: 'unclaimed' },
      data: { status: 'ignored', ignoreReason: reason.slice(0, 280), ignoredAt: new Date() },
    });
    if (ignored.count === 0) {
      const state = await prisma.mpesaIncoming.findUnique({
        where: { remoteId },
        select: { status: true, tenantId: true },
      });
      if (!state || state.tenantId !== user.tenantId) {
        res.status(404).json({ error: 'No such payment' });
        return;
      }
      res.status(409).json({ error: 'This payment is no longer unclaimed' });
      return;
    }
    res.json({ status: 'ok' });
  }),
);

/**
 * Retires unclaimed payments past their day (spec 12.6.3). The daily
 * scheduler calls it; a caller in a hurry reaps on list.
 */
export async function expireOldUnclaimed(): Promise<number> {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const result = await prisma.mpesaIncoming.updateMany({
    where: { status: 'unclaimed', receivedAt: { lt: cutoff } },
    data: { status: 'expired' },
  });
  return result.count;
}

/** A generated token, for tests to assert shape. */
export function newToken(): string {
  return randomBytes(24).toString('base64url');
}
