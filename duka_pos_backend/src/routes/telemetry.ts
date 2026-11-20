/**
 * Telemetry routes.
 *
 * Mounted at /api/telemetry, protected by the OIDC auth middleware mounted at
 * /api in index.ts. Every read/write is scoped to the caller's tenant
 * (req.user.tenantId).
 */
import { Request, Response, Router } from 'express';
import crypto from 'node:crypto';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { ingestTelemetrySchema, telemetryQuerySchema, churnSnapshotSchema, ingestSupportSchema } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { broadcastAll } from '../services/live_broker';
import { broadcastAdmin } from '../services/admin_live_broker';

const router = Router();

function safeReplayRoute(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const pathname = raw.split(/[?#]/, 1)[0];
  return pathname.split('/').map((segment) => {
    if (!segment) return segment;
    if (segment.includes('@') || /^\+?\d{6,}$/.test(segment) || /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(segment) || segment.length > 48) return ':id';
    return segment;
  }).join('/').slice(0, 200);
}

// ---------------------------------------------------------------------------
// POST /api/telemetry/events — ingest a batch of device telemetry events
// ---------------------------------------------------------------------------

router.post(
  '/events',
  asyncHandler(async (req: Request, res: Response) => {
    const { events } = parseBody(ingestTelemetrySchema, req.body);
    const tenantId = req.user!.tenantId;
    const defaultAt = new Date();
    const data = events.map((event: any) => ({
      clientEventId: event.clientEventId ?? null,
      tenantId,
      deviceId: event.deviceId ? crypto.createHash('sha256').update(`${tenantId}\0${event.deviceId}`).digest('hex') : null,
      sessionJti: req.auth?.jti ?? null,
      name: event.name,
      at: event.at ? new Date(event.at) : defaultAt,
      route: safeReplayRoute(event.route),
      // Details may contain free text on older clients. Keep the admin replay
      // limited to names and routes, never user-entered content.
      detail: null,
    }));
    const result = await prisma.telemetryEvent.createMany({ data, skipDuplicates: true });
    if (result.count > 0) broadcastAdmin({ type: 'session_activity', tenantId, at: new Date().toISOString() });
    return res.status(201).json({ ingested: result.count });
  })
);

// ---------------------------------------------------------------------------
// GET /api/telemetry/events — list telemetry events for the caller's tenant
// ---------------------------------------------------------------------------

router.get(
  '/events',
  asyncHandler(async (req: Request, res: Response) => {
    const { from, to, name, deviceId, limit } = parseBody(telemetryQuerySchema, req.query);
    const tenantId = req.user!.tenantId;

    const dateFilter: Record<string, unknown> = {};
    if (from) dateFilter.gte = from;
    if (to) dateFilter.lte = to;

    const where: Record<string, unknown> = { tenantId };
    if (Object.keys(dateFilter).length > 0) where.at = dateFilter;
    if (name) where.name = name;
    if (deviceId) where.deviceId = deviceId;

    const found = await prisma.telemetryEvent.findMany({
      where,
      orderBy: { at: 'desc' },
      take: limit,
    });
    return res.json({ events: found, count: found.length });
  })
);

// ---------------------------------------------------------------------------
// POST /api/telemetry/churn — upsert a churn snapshot for the caller's tenant
// ---------------------------------------------------------------------------

router.post(
  '/churn',
  asyncHandler(async (req: Request, res: Response) => {
    const { deviceId, date, streakDays, daysSinceLastActive, totalSessions, risk, score } = parseBody(
      churnSnapshotSchema,
      req.body,
    );
    const tenantId = req.user!.tenantId;
    const snapshotDate = new Date(date);

    const existing = await prisma.churnSnapshot.findFirst({
      where: { tenantId, deviceId, date: snapshotDate },
    });

    if (existing) {
      await prisma.churnSnapshot.update({
        where: { id: existing.id },
        data: {
          streakDays,
          daysSinceLastActive,
          totalSessions,
          risk,
          score,
          computedAt: new Date(),
        },
      });
    } else {
      await prisma.churnSnapshot.create({
        data: {
          tenantId,
          deviceId,
          date: snapshotDate,
          streakDays,
          daysSinceLastActive,
          totalSessions,
          risk,
          score,
        },
      });
    }

    return res.json({ upserted: true });
  })
);


// ---------------------------------------------------------------------------
// POST /api/telemetry/support — ingest a batch of support tickets / requests
// ---------------------------------------------------------------------------

router.post(
  '/support',
  asyncHandler(async (req: Request, res: Response) => {
    const { items } = parseBody(ingestSupportSchema, req.body);
    const tenantId = req.user!.tenantId;
    const result = await prisma.supportTicket.createMany({
      data: items.map((item: any) => ({
        tenantId,
        deviceId: item.deviceId ?? null,
        type: item.type,
        title: item.title,
        description: item.description,
        status: item.status,
      })),
    });
    if (items.some((item: any) => item.type === 'request' &&
        item.title.toLowerCase().includes('subscription'))) {
      broadcastAll({
        type: 'subscription_quote_requested',
        tenantId,
        at: new Date().toISOString(),
      });
      broadcastAdmin({
        type: 'subscription_quote_requested',
        tenantId,
        at: new Date().toISOString(),
      });
    }
    return res.status(201).json({ ingested: result.count });
  })
);

export default router;

