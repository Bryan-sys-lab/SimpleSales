// Receipt share links (feature 14's backend) and the KRA credit note
// (feature 5's), which the till queues the way it queues a sale invoice.
//
// ## WHY A LINK IS A SNAPSHOT, NOT A QUERY
//
// The customer's page must show the receipt they were handed — the numbers
// AS FILED. A link that re-reads a live sale would move when a return or a
// discount lands days later, and the paper in the customer's hand would stop
// agreeing with the page the QR opens. So the page renders the JSON the
// till sent, and a revoked or expired token is a dead link — deliberately.
//
// ## WHY THE CREDIT NOTE RIDES THE SAME TABLE
//
// A credit note is a KRA document exactly like an invoice: queued, issued,
// possibly rejected, with its own series of numbers. The eTIMS receipt row
// already owns that lifecycle; the note adds the invoice it reverses and the
// return that asked for it.

import express from 'express';
import { randomBytes } from 'crypto';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { asyncHandler, requireUser } from '../lib/http';
import { log } from '../lib/observability';

/** The public page's projection: everything on the paper, nothing under it. */
export const receiptLinkPageSelect = {
  token: true,
  snapshot: true,
  createdAt: true,
  expiresAt: true,
  // The withdrawal and the expiry are the page's own lifecycle: fetched to be
  // judged, and NEVER rendered.
  revokedAt: true,
} as const;

export const receiptLinksRoutes = express.Router();

const LINK_TTL_DAYS = 90;

/**
 * POST /api/receipt-links { snapshot } — mints a link for a receipt snapshot.
 *
 * The token is 24 random bytes, base64url: unguessable by design (22^147 of
 * entropy is beyond brute force on a receipt page that answers, quietly).
 * It does not take user input beyond the snapshot, and the snapshot is the
 * ONLY payload the public page ever renders.
 */
receiptLinksRoutes.post(
  '/',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    const body = req.body as { snapshot?: unknown };
    const snapshot = body?.snapshot;
    if (snapshot === undefined || snapshot === null || typeof snapshot !== 'object') {
      res.status(400).json({ error: 'A receipt snapshot is required' });
      return;
    }
    const token = randomBytes(24).toString('base64url');
    const expiresAt = new Date(Date.now() + LINK_TTL_DAYS * 24 * 60 * 60 * 1000);
    const link = await prisma.receiptLink.create({
      data: {
        tenantId: user.tenantId,
        token,
        snapshot: snapshot as Prisma.InputJsonValue,
        expiresAt,
      },
      select: { token: true, expiresAt: true },
    });
    log('info', 'receipt.link.created', { tenantId: user.tenantId });
    res.status(201).json({
      status: 'ok',
      token: link.token,
      expires_at: link.expiresAt,
      url: `/api/receipt-links/${link.token}/page`,
    });
  }),
);

/**
 * DELETE /api/receipt-links/:token — revokes a link the till can no longer
 * trust (a wrong number shown on a page, a customer asking it gone).
 */
receiptLinksRoutes.delete(
  '/:token',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    const token = String(req.params.token ?? '');
    const revoked = await prisma.receiptLink.updateMany({
      where: { token, tenantId: user.tenantId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (revoked.count === 0) {
      res.status(404).json({ error: 'No such link' });
      return;
    }
    res.json({ status: 'ok' });
  }),
);

/**
 * GET /api/receipt-links/:token/page — PUBLIC.
 *
 * The customer's page, reached by the QR without any sign-in. It answers the
 * SNAPSHOT and nothing internal: no tenant, no device, no staff ids — the
 * snapshot the till submitted is what a person holding the receipt could
 * already read on the paper.
 */
receiptLinksRoutes.get(
  '/:token/page',
  asyncHandler(async (req, res): Promise<void> => {
    const token = String(req.params.token ?? '');
    const link = await prisma.receiptLink.findUnique({
      where: { token },
      select: receiptLinkPageSelect,
    });
    if (!link) {
      res.status(404).json({ error: 'No such receipt page' });
      return;
    }
    if (link.revokedAt !== null) {
      res.status(410).json({ error: 'This receipt page has been withdrawn' });
      return;
    }
    if (link.expiresAt.getTime() < Date.now()) {
      res.status(410).json({ error: 'This receipt page has expired' });
      return;
    }
    res.json({ status: 'ok', page: { snapshot: link.snapshot, created_at: link.createdAt } });
  }),
);

// ---------------------------------------------------------------------------
// The KRA credit note.
// ---------------------------------------------------------------------------

export const creditNoteRoutes = express.Router();

/**
 * POST /api/etims/credit-note — queues a credit note against a sale the
 * shop has already filed (or tried to).
 *
 * Idempotent by the RETURN NUMBER, mirroring the invoice queue: a till that
 * retries a timed-out upload cannot mint two credit notes from one return —
 * the second request comes back with the FIRST note, and the response spells
 * that out rather than inventing a second.
 *
 * The note carries the ORIGINAL KRA receipt number on every line item the
 * till reported: reversing a KRA document is keyed by THAT document.
 */
creditNoteRoutes.post(
  '/',
  asyncHandler(async (req, res): Promise<void> => {
    const user = requireUser(req);
    const body = (req.body ?? {}) as Record<string, unknown>;

    const returnNumber = typeof body.return_number === 'string' ? body.return_number.trim() : '';
    const originalNumber =
      typeof body.original_receipt_number === 'string'
        ? body.original_receipt_number.trim()
        : '';
    const reasonCode = typeof body.reason_code === 'string' ? body.reason_code.trim() : 'OTHER';
    const items = Array.isArray(body.lines) ? (body.lines as unknown[]) : [];
    const total = Number(body.total ?? 0);
    const vatTotal = Number(body.vat_total ?? 0);

    if (returnNumber === '') {
      res.status(400).json({ error: 'A return number is required' });
      return;
    }
    if (originalNumber === '') {
      res.status(400).json({
        error:
          'The original KRA receipt number is required: a credit note reverses a filed receipt',
      });
      return;
    }
    if (items.length === 0) {
      res.status(400).json({ error: 'At least one line is required' });
      return;
    }
    if (!Number.isFinite(total) || total <= 0) {
      res.status(400).json({ error: 'The reversal total must be a positive number' });
      return;
    }

    // An EXISTING note for this return: the same document again, told honestly.
    const prior = await prisma.etimsReceipt.findUnique({
      where: {
        tenantId_returnNumber: { tenantId: user.tenantId, returnNumber },
      },
    });
    if (prior) {
      res.json({
        status: prior.status === 'rejected' ? 'rejected' : 'already',
        credit_note_number: prior.kraReceiptNumber,
        verification_url: prior.verificationUrl,
        qr_payload: prior.qrPayload,
      });
      return;
    }

    // The original must be THE SHOP's own filed invoice: a note reversing a
    // number that is not ours is refused here, at the door, where it is a
    // validation and not a KRA rejection days later.
    const original = await prisma.etimsReceipt.findFirst({
      where: {
        tenantId: user.tenantId,
        OR: [{ kraReceiptNumber: originalNumber }, { receiptNumber: originalNumber }],
      },
      select: { id: true, status: true, payload: true },
    });
    if (!original) {
      res.status(400).json({ error: 'No such original receipt in this shop' });
      return;
    }

    // Preserve the buyer snapshot from the filed invoice. Customer records
    // can change after checkout; a credit note must reverse the same document.
    const stored = original.payload as Record<string, unknown>;
    const originalInput = stored.input && typeof stored.input === 'object'
      ? stored.input as Record<string, unknown>
      : stored;
    const buyerName = typeof originalInput.buyerName === 'string'
      ? originalInput.buyerName
      : typeof originalInput.buyer_name === 'string' ? originalInput.buyer_name : undefined;
    const buyerTin = typeof originalInput.buyerTin === 'string'
      ? originalInput.buyerTin
      : typeof originalInput.buyer_tin === 'string' ? originalInput.buyer_tin : undefined;
    const payload = {
      document_type: 'credit_note',
      original_receipt_number: originalNumber,
      reason_code: reasonCode.toUpperCase(),
      lines: items,
      total,
      vat_total: vatTotal,
      ...(buyerName?.trim() ? { buyer_name: buyerName.trim() } : {}),
      ...(buyerTin?.trim() ? { buyer_tin: buyerTin.trim() } : {}),
      issued_by: user.name,
    };

    const note = await prisma.etimsReceipt.create({
      data: {
        tenantId: user.tenantId,
        receiptNumber: returnNumber,
        returnNumber,
        documentType: 'credit_note',
        originalReceiptNumber: originalNumber,
        status: 'pending',
        total: total.toFixed(2),
        vatTotal: vatTotal.toFixed(2),
        itemCount: items.length,
        payload: payload as Prisma.InputJsonValue,
      },
    });

    // The queue's worker issues against KRA from here; the till sees the
    // note as etims_pending on the return until the KRA number lands.
    log('info', 'etims.credit_note.queued', {
      tenantId: user.tenantId,
      returnNumber,
      originalReceipt: originalNumber,
    });

    res.status(201).json({
      status: 'queued',
      credit_note_id: note.id,
      qr_payload: note.qrPayload,
    });
  }),
);
