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

app.use(express.json({ limit: '256kb' }));
app.use(
  rateLimit({ windowMs: 60000, limit: 120, standardHeaders: 'draft-7', legacyHeaders: false }),
);

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

  return res.json({
    version_name: versionName,
    version_code: versionCode,
    download_url: downloadUrl,
    required: required === 'true',
    release_notes: releaseNotes,
  });
}));

// ---------------------------------------------------------------------------
// Protected routes (require OIDC JWT)
// ---------------------------------------------------------------------------

app.use('/api', authMiddleware);
app.use('/api/tenant', tenantRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/products', productRoutes);
app.use('/api/reports', reportRoutes);

// ---------------------------------------------------------------------------
// eTIMS KRA tax compliance (OIDC guarded)
// ---------------------------------------------------------------------------

app.use('/api/etims', etimsRoutes);

// ---------------------------------------------------------------------------
// Profile photos (OIDC guarded)
// ---------------------------------------------------------------------------

app.use('/api/profile', profileRoutes);

app.use('/api/telemetry', telemetryRoutes);
app.use('/api/admin', adminRoutes);

// ---------------------------------------------------------------------------

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

import { errorHandler } from './lib/http';
app.use(errorHandler);

if (require.main === module) {
  const server = app.listen(PORT, () =>
    log('info', 'server.started', { port: PORT, environment: process.env.NODE_ENV ?? 'development' }),
  );
  const wss = new WebSocketServer({ server, path: '/api/live' });
  wss.on('connection', (ws) => {
    ws.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
  });
  const shutdown = (signal: string) => {
    log('info', 'server.shutdown', { signal });
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
