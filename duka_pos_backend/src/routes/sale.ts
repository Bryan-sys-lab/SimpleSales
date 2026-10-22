/**
 * The ledger: the sales a till took, pushed from the phone.
 *
 * ## WHY THIS ENDPOINT EXISTS
 *
 * The till writes its sales OFFLINE, on the phone, and that is the whole
 * point of it: a shop with no signal still sells, still takes the money and
 * still knows what it sold.
 *
 * But the server had no way to learn about any of it. The only rows that ever
 * reached the `sales` table were the M-Pesa ones, written by the payment
 * callback — so CASH SALES, which are most of a shop's sales, never left the
 * phone. The owner's account, the reports and the all-shops view were reading
 * a ledger with holes in it.
 *
 * So the till pushes its ledger, and this is where it lands.
 *
 * ## WHY THE PUSH IS IDEMPOTENT
 *
 * A phone that was offline pushes the same sales again the next time it is
 * online — that is the whole mechanism. The server has to be able to tell a
 * re-push from a new sale, or a week's takings become two weeks of takings
 * the moment the signal comes back.
 *
 * `localId` is the till's own id for the sale, and it is unique WITHIN a
 * shop. The server upserts on it: the same sale arriving twice updates the
 * row it already has rather than making a second one.
 */
import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma.js';
import { asyncHandler } from '../lib/http.js';
import { parseBody, saleSyncSchema } from '../lib/validation.js';
import { requireRole } from '../middleware/auth.js';
import { announceChange } from '../lib/live.js';
import { majorFromMinor, minorFromMajor } from '../lib/money.js';
import { mergeByLocalId } from '../lib/till_records.js';

const router = Router();

// ---------------------------------------------------------------------------
// Push the till's ledger
// ---------------------------------------------------------------------------

router.post('/sync', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const { sales } = parseBody(saleSyncSchema, req.body);
  const tenantId = req.user!.tenantId;

  // Which of these the server already has.
  //
  // One lookup for the whole batch rather than a findFirst per sale: a busy
  // till pushes a day of sales at once, and a query per sale is a query per
  // sale.
  const localIds = sales.map((sale) => sale.localId);
  const existing = await prisma.sale.findMany({
    where: { tenantId, localId: { in: localIds } },
    select: { id: true, localId: true },
  });
  const existingByLocalId = new Map<number, string>();
  for (const sale of existing) {
    if (sale.localId !== null) existingByLocalId.set(sale.localId, sale.id);
  }

  const decisions = mergeByLocalId(sales, new Set(existingByLocalId.keys()));
  const decisionByLocalId = new Map(decisions.map((d) => [d.localId, d]));

  const synced = await prisma.$transaction(async (tx) => {
    const result: Array<{ localId: number; remoteId: string }> = [];
    for (const sale of sales) {
      const knownId = existingByLocalId.get(sale.localId);
      const isUpdate = decisionByLocalId.get(sale.localId)?.isUpdate === true;

      const data = {
        staffName: sale.staffName,
        // The profile is optional: a till that has not synced its roster yet
        // still has sales, and a sale is not lost because the person who rang
        // it is not on the server yet. The NAME is on the sale either way,
        // which is what the reports read.
        staffId: sale.staffProfileId ?? null,
        paymentMethod: sale.paymentMethod,
        paymentReference: sale.paymentReference ?? null,
        total: majorFromMinor(sale.total),
        profit: majorFromMinor(sale.profit),
        createdAt: new Date(sale.createdAt),
      };

      const saved = knownId && isUpdate
        ? await tx.sale.update({ where: { id: knownId }, data })
        : await tx.sale.create({
            data: { ...data, tenantId, localId: sale.localId },
          });

      // The items are the sale's detail, and a sale with no items is a total
      // nobody can take apart. They are replaced wholesale: the phone is the
      // authority on what the sale WAS, and a re-push with a corrected line
      // should not leave the old line behind.
      await tx.saleItem.deleteMany({ where: { saleId: saved.id } });
      for (const item of sale.items) {
        await tx.saleItem.create({
          data: {
            tenantId,
            saleId: saved.id,
            // A product the server has never seen — one the till created and
            // has not pushed yet — is left empty rather than invented. The
            // name is on the line, so the report still says what was sold.
            productId: item.productId ?? null,
            productName: item.productName,
            qty: item.qty,
            unitPrice: majorFromMinor(item.unitPrice),
            unitCost: majorFromMinor(item.unitCost),
            portion: item.portion,
            portionMl: item.portionMl,
          },
        });
      }

      result.push({ localId: sale.localId, remoteId: saved.id });
    }
    return result;
  });

  // After the write, and only because it succeeded: a stream told about a
  // ledger that failed to save is a stream chasing a change that never
  // happened. See lib/live.ts.
  announceChange([tenantId], 'sales');

  return res.json({ synced });
}));

// ---------------------------------------------------------------------------
// Read the ledger back
// ---------------------------------------------------------------------------

router.get('/', requireRole('admin', 'manager', 'cashier'), asyncHandler(async (req: Request, res: Response) => {
  const from = typeof req.query.from === 'string' ? new Date(req.query.from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const to = typeof req.query.to === 'string' ? new Date(req.query.to) : new Date();
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
    return res.status(400).json({ error: 'Invalid report date range' });
  }
  const limit = Math.min(Math.max(Number(req.query.limit) || 500, 1), 500);

  const sales = await prisma.sale.findMany({
    where: {
      tenantId: req.user!.tenantId,
      // A cashier reads their own takings. The same rule the app applies
      // locally, and for the same reason: "how am I doing" is not a question
      // anyone else gets to audit from the till.
      ...(req.user!.role === 'cashier' ? { staffName: req.user!.name } : {}),
      createdAt: { gte: from, lte: to },
    },
    select: {
      id: true,
      localId: true,
      total: true,
      profit: true,
      paymentMethod: true,
      staffName: true,
      createdAt: true,
      saleItems: {
        select: {
          productName: true,
          qty: true,
          unitPrice: true,
          unitCost: true,
          portion: true,
          portionMl: true,
        },
      },
    },
    orderBy: { createdAt: 'asc' },
    take: limit,
  });

  return res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    // MINOR UNITS, because that is what the app reads. The stored figures are
    // major units, and the app's ledger is in minor ones: answering in the
    // app's own unit is the difference between a portfolio that works and one
    // that is a hundred times out.
    sales: sales.map((sale) => ({
      remoteId: sale.id,
      localId: sale.localId,
      total: minorFromMajor(sale.total),
      profit: minorFromMajor(sale.profit),
      paymentMethod: sale.paymentMethod,
      staffName: sale.staffName,
      createdAt: sale.createdAt.toISOString(),
      items: sale.saleItems.map((item) => ({
        productName: item.productName,
        qty: Number(item.qty),
        unitPrice: minorFromMajor(item.unitPrice),
        unitCost: minorFromMajor(item.unitCost),
        portion: item.portion,
        portionMl: item.portionMl,
      })),
    })),
  });
}));

export default router;
