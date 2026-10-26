/**
 * Duka POS backend — Express application.
 *
 * Mounts all route modules with the appropriate middleware:
 *   /api/system         — platform administration (system admin allowlist)
 *   /api/auth           — app verification flow (no OIDC, app's own challenge flow)
 *   /api/etims          — KRA tax compliance (OIDC guarded)
 *   /api/tenant         — shop provisioning, settings, staff, portfolio (OIDC guarded)
 *   /api/payments       — M-Pesa via PayHero (OIDC guarded)
 *   /api/products       — catalogue sync + stock adjustment (OIDC guarded)
 *   /api/reports        — sales reports (OIDC guarded)
 *   /api/app/latest     — update manifest for the till app
 *   /webhooks/payhero-callback — PayHero webhook (no auth)
 *   /health, /ready     — liveness / readiness probes
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { WebSocketServer } from 'ws';
import { asyncHandler, errorHandler } from './lib/http';
import {
  expireOldUnclaimed,
  mpesaRoutes,
  mpesaWebhookRoutes,
  setMpesaPaymentNotifier,
} from './routes/mpesa';
import { creditNoteRoutes, receiptLinksRoutes } from './routes/receipt_links';
import { systemAdminMiddleware, authMiddleware } from './middleware/auth';
import tenantRoutes from './routes/tenant';
import paymentRoutes from './routes/payment';
import productRoutes from './routes/product';
import { handlePayheroCallback } from './routes/payhero-callback';
import { requestContext, log } from './lib/observability';
import rateLimit from 'express-rate-limit';
import { prisma } from './lib/prisma';
import reportRoutes from './routes/report';
import systemRoutes from './routes/system';
import authRoutes from './routes/auth';
import etimsRoutes from './routes/etims';
import profileRoutes from './routes/profile';
import telemetryRoutes from './routes/telemetry';
import adminRoutes from './routes/admin';
import { setPlatformAnnouncementNotifier } from './routes/admin';
import salesRoutes from './routes/sales';
import backupRoutes from './routes/backup';
import creditRoutes from './routes/credit';
import operationalSyncRoutes from './routes/operational_sync';
import evidenceRoutes from './routes/evidence';

dotenv.config();

if (process.env.NODE_ENV === 'production' && !process.env.PUBLIC_API_URL?.startsWith('https://')) {
  throw new Error('PUBLIC_API_URL must be an https URL in production');
}

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet({ frameguard: { action: 'deny' } }));
app.use(requestContext);

const allowedOrigins = (process.env.FRONTEND_URL || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : false }));

// Full workspace backups are already encrypted client-side and can contain a
// busy shop's history; the route still validates and caps the payload at 8 MB.
app.use(express.json({ limit: '8mb' }));
app.use(rateLimit({
  windowMs: 60000,
  limit: Number(process.env.RATE_LIMIT_LIMIT ?? 120),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  // Liveness/readiness probes must keep working during a traffic burst;
  // application and webhook routes remain behind the limiter below.
  skip: (req) => req.path === '/health' || req.path === '/ready',
}));

// ---------------------------------------------------------------------------
// Health / readiness
// ---------------------------------------------------------------------------

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/ready', async (_req, res, next) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ready' });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// PayHero webhook (no auth required — called by PayHero)
// ---------------------------------------------------------------------------

app.post(
  '/webhooks/payhero-callback',
  rateLimit({ windowMs: 60000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false }),
  handlePayheroCallback,
);

// ---------------------------------------------------------------------------
// Platform administration (system admin allowlist)
// ---------------------------------------------------------------------------

app.use('/api/system', systemAdminMiddleware, systemRoutes);

// ---------------------------------------------------------------------------
// Public routes (no auth required) - mounted BEFORE auth middleware
// ---------------------------------------------------------------------------

app.use('/api/auth', authRoutes);
app.get('/api/app/latest', asyncHandler(async (_req, res) => {
  // These are injected at build/release time via environment variables.
  // A release pipeline sets them to the current build's values.
  const versionName = process.env.APP_VERSION_NAME ?? '2.0.0';
  const versionCode = Number(process.env.APP_VERSION_CODE ?? '23');
  const downloadUrl = process.env.APP_DOWNLOAD_URL ?? '';
  const required = process.env.APP_UPDATE_REQUIRED ?? 'false';
  const releaseNotes = process.env.APP_RELEASE_NOTES ?? 'No release notes published.';
  let announcement: { id: string; title: string; body: string } | null = null;
  try {
    const announcementRows = await prisma.systemSettings.findMany({
      where: { key: { in: ['platform_announcement_id', 'platform_announcement_title', 'platform_announcement_body', 'platform_announcement_active'] } },
    });
    const announcementValues = Object.fromEntries(announcementRows.map((row) => [row.key, row.value]));
    if (announcementValues.platform_announcement_active === 'true' && announcementValues.platform_announcement_id) {
      announcement = {
        id: announcementValues.platform_announcement_id,
        title: announcementValues.platform_announcement_title ?? '',
        body: announcementValues.platform_announcement_body ?? '',
      };
    }
  } catch {
    // The update manifest remains available during a database interruption;
    // only the optional platform announcement is omitted.
  }

  return res.json({
    // The mobile manifest uses camelCase; retain the legacy snake_case aliases
    // for older clients that may still be in the field.
    build: versionCode,
    version: versionName,
    downloadUrl,
    notes: releaseNotes,
    required: required === 'true',
    version_name: versionName,
    version_code: versionCode,
    download_url: downloadUrl,
    release_notes: releaseNotes,
    announcement,
  });
}));

// ---------------------------------------------------------------------------
// M-Pesa C2B callbacks (public, key-guarded in the route) and the receipt
// share links (one public page, the rest behind the JWT wall).
// ---------------------------------------------------------------------------

app.use('/callback/mpesa', mpesaWebhookRoutes);

// ---------------------------------------------------------------------------
// Protected routes (require OIDC JWT)
// ---------------------------------------------------------------------------

app.use('/api', authMiddleware);
app.use('/api/mpesa', mpesaRoutes);
app.use('/api/tenant', tenantRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/products', productRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/sales', salesRoutes);
app.use('/api/backups/full', backupRoutes);
app.use('/api/evidence', evidenceRoutes);
app.use('/api/credit', creditRoutes);
app.use('/api/shifts', operationalSyncRoutes);
app.use('/api/shot-cups', operationalSyncRoutes);
app.use('/api/returns', operationalSyncRoutes);
app.use('/api/purchases', operationalSyncRoutes);
app.use('/api/expenses', operationalSyncRoutes);
app.use('/api/till-movements', operationalSyncRoutes);
app.use('/api/stock-movements', operationalSyncRoutes);
app.use('/api/drawer-events', operationalSyncRoutes);
app.use('/api/laybys', operationalSyncRoutes);
app.use('/api/exchanges', operationalSyncRoutes);
app.use('/api/reorder', operationalSyncRoutes);

// ---------------------------------------------------------------------------
// eTIMS KRA tax compliance (OIDC guarded)
// ---------------------------------------------------------------------------

app.use('/api/etims', etimsRoutes);
app.use('/api/etims/credit-note', creditNoteRoutes);
app.use('/api/receipt-links', receiptLinksRoutes);

// ---------------------------------------------------------------------------
// Profile photos (OIDC guarded)
// ---------------------------------------------------------------------------

app.use('/api/profile', profileRoutes);

app.use('/api/telemetry', telemetryRoutes);
app.use('/api/admin', adminRoutes);

// ---------------------------------------------------------------------------

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

app.use(errorHandler);

if (require.main === module) {
  const server = app.listen(PORT, () =>
    log('info', 'server.started', { port: PORT, environment: process.env.NODE_ENV ?? 'development' }),
  );
  const wss = new WebSocketServer({ server, path: '/api/live' });
  const liveClients = new Set<import('ws').WebSocket>();
  wss.on('connection', (ws) => {
    liveClients.add(ws);
    ws.once('close', () => liveClients.delete(ws));
    ws.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
  });
  setMpesaPaymentNotifier(() => {
    const message = JSON.stringify({ type: 'mpesa_incoming' });
    for (const client of liveClients) {
      if (client.readyState === client.OPEN) client.send(message);
    }
  });
  setPlatformAnnouncementNotifier((announcement) => {
    const message = JSON.stringify({
      type: announcement.id ? 'platform_announcement' : 'platform_announcement_cleared',
      ...(announcement.id ? { announcement } : {}),
    });
    for (const client of liveClients) {
      if (client.readyState === client.OPEN) client.send(message);
    }
  });
  // Reap rows that crossed the 24-hour boundary while this container was
  // asleep or scaled to zero before starting the recurring sweep.
  void expireOldUnclaimed().catch((error) =>
    log('warn', 'mpesa.expiry_failed', {
      message: error instanceof Error ? error.message : 'unknown',
    }),
  );
  const mpesaExpiryTimer = setInterval(() => {
    void expireOldUnclaimed().catch((error) =>
      log('warn', 'mpesa.expiry_failed', {
        message: error instanceof Error ? error.message : 'unknown',
      }),
    );
  }, 24 * 60 * 60 * 1000);
  const shutdown = (signal: string) => {
    log('info', 'server.shutdown', { signal });
    clearInterval(mpesaExpiryTimer);
    setMpesaPaymentNotifier(null);
    setPlatformAnnouncementNotifier(null);
    server.close(() => void prisma.$disconnect());
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));
  process.on('unhandledRejection', (reason: any) =>
    log('error', 'process.unhandled_rejection', { message: reason instanceof Error ? reason.message : 'unknown' }),
  );
  process.on('uncaughtException', (error: Error) => {
    log('error', 'process.uncaught_exception', { message: error.message, stack: error.stack });
    shutdown('uncaughtException');
  });
}

export default app;
