/**
 * Telemetry routes.
 *
 * Mounted at /api/telemetry, protected by the OIDC auth middleware mounted at
 * /api in index.ts. Every read/write is scoped to the caller's tenant
 * (req.user.tenantId).
 */
import { Request, Response, Router } from 'express';
import { asyncHandler } from '../lib/http.js';
import { parseBody } from '../lib/validation.js';
import { ingestTelemetrySchema, telemetryQuerySchema, churnSnapshotSchema, ingestSupportSchema } from '../lib/validation.js';
import { prisma } from '../lib/prisma.js';

const router = Router();

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
      tenantId,
      deviceId: event.deviceId ?? null,
      name: event.name,
      at: event.at ? new Date(event.at) : defaultAt,
      route: event.route ?? null,
      detail: event.detail ?? null,
    }));
    const result = await prisma.telemetryEvent.createMany({ data });
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
    return res.status(201).json({ ingested: result.count });
  })
);

export default router;

