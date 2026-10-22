/**
 * Duka POS backend — Express application.
 *
 * Mounts all route modules with the appropriate middleware:
 *   /api/system         — platform administration (system admin allowlist)
 *   /api/auth           — the verify flow (no token yet: it mints the account)
 *   /api/etims/verify   — the public eTIMS device check
 *   /api/etims          — KRA tax compliance (OIDC guarded)
 *   /api/tenant         — shop provisioning, settings, staff, portfolio (OIDC guarded)
 *   /api/payments       — M-Pesa via PayHero (OIDC guarded)
 *   /api/products       — catalogue sync + stock adjustment (OIDC guarded)
 *   /api/reports        — sales reports (OIDC guarded)
 *   /api/sales          — the till's ledger, pushed from the phone (OIDC guarded)
 *   /api/shifts         — the till's drawers, pushed from the phone (OIDC guarded)
 *   /api/returns        — returns and credit notes (OIDC guarded)
 *   /api/purchases      — stock received, and what it cost (OIDC guarded)
 *   /api/shot-cups      — named servings poured from a drink (OIDC guarded)
 *   /api/profile        — profile photos (OIDC guarded)
 *   /api/telemetry      — device telemetry (OIDC guarded)
 *   /api/admin          — shop administration (OIDC guarded)
 *   /admin              — the operator dashboard
 *   /api/app/latest     — the update manifest for the till app
 *   /webhooks/payhero-callback — PayHero webhook (no auth)
 *   /health, /ready     — liveness / readiness probes
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { systemAdminMiddleware, authMiddleware } from './middleware/auth';
import tenantRoutes from './routes/tenant';
import paymentRoutes from './routes/payment';
import productRoutes from './routes/product';
import { handlePayheroCallback } from './routes/payhero-callback';
import { requestContext, log } from './lib/observability';
import rateLimit from 'express-rate-limit';
import { prisma } from './lib/prisma';
import reportRoutes from './routes/report';
import { attachLiveChannel } from './routes/live';
import systemRoutes from './routes/system';
import etimsRoutes, { publicEtimsRouter } from './routes/etims';
import authRoutes from './routes/auth';
import appReleaseRoutes from './routes/app-release';
import dashboardRoutes from './routes/dashboard';
import saleRoutes from './routes/sale';
import shiftRoutes from './routes/shift';
import returnRoutes from './routes/return';
import purchaseRoutes from './routes/purchase';
import shotCupRoutes from './routes/shotcup';
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

// The eTIMS device check: the till asks whether its device is registered
// before it may file a receipt, and it asks BEFORE it has a token.
app.use('/api/etims/verify', publicEtimsRouter);

// The verify flow, and the only endpoints in the service that authenticate by
// content instead of by token — they run *before* a shop has a token, because
// the first one has to work for an account that does not exist yet. Mounted
// ahead of `authMiddleware` for that reason, rate-limited per address inside.
//
// What it does NOT do is mint a credential. It creates the Keycloak account,
// proves the address with an emailed code, activates the account, and links
// the shop. The credential is Keycloak's, and the till signs in to Keycloak
// for it.
app.use('/api/auth', authRoutes);

// The operator dashboard: a hand-built page, served from this origin so it
// cannot drift from the API it reads. Sits outside `/api` and carries no
// authentication of its own — every read it makes is an authenticated call to
// `/api/system/*`, which is where the allowlist is enforced.
app.use('/admin', dashboardRoutes);

// The release manifest, unauthenticated: a shop that has never signed in still
// needs to be able to update. Mounted here rather than under `/api` so it is
// outside `authMiddleware` entirely — see the note in the route file.
app.use('/', appReleaseRoutes);

// Protected routes (require OIDC JWT)
// ---------------------------------------------------------------------------

app.use('/api', authMiddleware);
app.use('/api/tenant', tenantRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/products', productRoutes);
app.use('/api/reports', reportRoutes);

// The till's own records: the ledger, the drawers, the returns, the
// deliveries and the shot cups. All written on the phone and pushed here.
app.use('/api/sales', saleRoutes);
app.use('/api/shifts', shiftRoutes);
app.use('/api/returns', returnRoutes);
app.use('/api/purchases', purchaseRoutes);
app.use('/api/shot-cups', shotCupRoutes);

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

// The live channel lives on its own path because it is the one route that is
// not a request/response: the upgrade is handled by the HTTP server, not by
// Express, so attaching a listener here is what makes /live exist at all. It
// must be attached before the first connection, and it must see the same
// server the app listens on.
if (require.main === module) {
  const server = app.listen(PORT, () => log('info', 'server.started', { port: PORT, environment: process.env.NODE_ENV ?? 'development' }));
  const live = attachLiveChannel(server);
  const shutdown = (signal: string) => {
    log('info', 'server.shutdown', { signal });
    // Close the streams before the server: a till left holding a socket the
    // process has abandoned reconnects and gets a clean 1001 rather than a
    // half-read frame.
    live.close();
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
