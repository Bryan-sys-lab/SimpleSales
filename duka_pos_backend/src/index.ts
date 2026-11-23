/**
 * Duka POS backend — Express application.
 *
 * Mounts all route modules with the appropriate middleware:
 *   /api/system         — platform administration (system admin allowlist)
 *   /api/auth           — app verification flow (no OIDC, app's own challenge flow)
 *   /api/etims          — KRA tax compliance (OIDC guarded)
 *   /api/tenant         — shop provisioning, settings, staff, portfolio (OIDC guarded)
 *   /api/payments       — M-Pesa via PayHero and optional Safaricom QR (OIDC guarded)
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
import membershipRoutes from './routes/membership';
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
import adminAuthRoutes from './routes/admin_auth';
import adminMembershipRoutes from './routes/admin_membership';
import adminOrgRoutes from './routes/admin_org';
import { setPlatformAnnouncementNotifier } from './routes/admin';
import salesRoutes from './routes/sales';
import backupRoutes from './routes/backup';
import creditRoutes from './routes/credit';
import operationalSyncRoutes from './routes/operational_sync';
import evidenceRoutes from './routes/evidence';
import productVariantRoutes from './routes/product-variants';
import costPoolRoutes from './routes/cost-pools';
import ownerTransactionRoutes from './routes/owner-transactions';
import businessContextRoutes from './routes/business_context';
import commercialConsentRoutes from './routes/commercial_consent';
import commercialContributionsRoutes from './routes/commercial_contributions';
import saleEvidenceRoutes from './routes/sale_evidence';
import { verifyAccessToken } from './lib/jwt';
import { addLiveClient, broadcastAll, broadcastTenantChange, removeLiveClient } from './services/live_broker';
import { addAdminLiveClient, broadcastAdmin, removeAdminLiveClient } from './services/admin_live_broker';
import { consumeAdminWebSocketTicket } from './services/admin_ws_tickets';
import { adminLiveInvalidationFor } from './services/admin_live_invalidation';

if (typeof module !== 'undefined') { dotenv.config(); }

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
const isNode = typeof module !== 'undefined';
if (isNode) {
  app.use(rateLimit({
    windowMs: 60000,
    limit: Number(process.env.RATE_LIMIT_LIMIT ?? 300),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skip: (req) => req.path === '/health' || req.path === '/ready',
  }));
}

// ---------------------------------------------------------------------------
// Health / readiness
// ---------------------------------------------------------------------------

app.get('/health', (_req, res) => {
  const rawVersionCode = process.env.BACKEND_VERSION_CODE;
  const versionCode = rawVersionCode === undefined ? 0 : Number(rawVersionCode);
  if (
    (rawVersionCode !== undefined && !/^(0|[1-9]\d*)$/.test(rawVersionCode)) ||
    !Number.isSafeInteger(versionCode)
  ) {
    res.status(500).json({ status: 'error', error: 'Backend build version is misconfigured' });
    return;
  }
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    backend_version_name: process.env.BACKEND_VERSION_NAME ?? '2.0.0',
    backend_version_code: versionCode,
    backend_commit_sha: process.env.BACKEND_COMMIT_SHA ?? 'local',
  });
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

const webhookLimiter = isNode ? rateLimit({ windowMs: 60000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false }) : (_req: any, _res: any, next: any) => next();
app.post(
  '/webhooks/payhero-callback',
  webhookLimiter,
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

type PublishedAppRelease = {
  versionName: string;
  versionCode: number;
  downloadUrl: string;
  notes: string;
};

type GitHubReleasePayload = {
  tag_name?: unknown;
  body?: unknown;
  draft?: unknown;
  prerelease?: unknown;
  assets?: unknown;
};

let appReleaseCache: { expiresAt: number; value: PublishedAppRelease } | null = null;

/**
 * Resolve the update channel from the release that CI published.
 *
 * The app must never need a second deployment just because a new APK was
 * published. GitHub's public latest-release endpoint is therefore the source
 * of truth; APP_* remains a deliberate fallback for local/offline deployments
 * and while GitHub is temporarily unavailable.
 */
async function publishedAppRelease(): Promise<PublishedAppRelease> {
  const fallback: PublishedAppRelease = {
    versionName: process.env.APP_VERSION_NAME ?? '2.0.0',
    versionCode: Number(process.env.APP_VERSION_CODE ?? '1'),
    downloadUrl: process.env.APP_DOWNLOAD_URL ?? '',
    notes: process.env.APP_RELEASE_NOTES ?? 'No release notes published.',
  };

  if (appReleaseCache && appReleaseCache.expiresAt > Date.now()) {
    return appReleaseCache.value;
  }

  const repository = process.env.APP_RELEASE_REPOSITORY ?? 'Bryan-sys-lab/SimpleSales';
  const manifestUrl = process.env.APP_RELEASE_MANIFEST_URL ?? 'https://pub-304b56b967d4462f8ca28cdb5a6fc43a.r2.dev/current.json';
  try {
    // Prefer the R2-backed manifest served by the website, so a build uploaded
    // to storage becomes the update the handset sees without a GitHub release.
    try {
      const manifestResponse = await fetch(manifestUrl, {
        headers: { accept: 'application/json', 'user-agent': 'SimpleSales-backend-update-channel' },
        signal: AbortSignal.timeout(5000),
      });
      if (manifestResponse.ok) {
        const manifest = (await manifestResponse.json()) as {
          build?: unknown;
          version?: unknown;
          downloadUrl?: unknown;
          download_url?: unknown;
          notes?: unknown;
          release_notes?: unknown;
        };
        const build = typeof manifest.build === 'number' ? manifest.build : Number(manifest.build);
        const version = typeof manifest.version === 'string' ? manifest.version.trim() : '';
        const downloadUrl =
          typeof manifest.downloadUrl === 'string'
            ? manifest.downloadUrl.trim()
            : typeof manifest.download_url === 'string'
              ? manifest.download_url.trim()
              : '';
        const notes =
          typeof manifest.notes === 'string'
            ? manifest.notes.trim()
            : typeof manifest.release_notes === 'string'
              ? manifest.release_notes.trim()
              : fallback.notes;
        if (Number.isInteger(build) && build > 0 && version && downloadUrl) {
          const resolved: PublishedAppRelease = {
            versionName: version,
            versionCode: build,
            downloadUrl,
            notes,
          };
          appReleaseCache = { expiresAt: Date.now() + 60_000, value: resolved };
          return resolved;
        }
      }
    } catch {
      // Fall through to GitHub.
    }

    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      headers: {
        accept: 'application/vnd.github+json',
        'user-agent': 'SimpleSales-backend-update-channel',
      },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return fallback;

    const payload = (await response.json()) as GitHubReleasePayload;
    if (payload.draft === true || payload.prerelease === true || typeof payload.tag_name !== 'string') {
      return fallback;
    }

    const match = /^v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)$/.exec(payload.tag_name);
    const assets = Array.isArray(payload.assets) ? payload.assets : [];
    const apk = assets.find((asset): asset is { name?: unknown; browser_download_url?: unknown } => {
      if (!asset || typeof asset !== 'object') return false;
      const candidate = asset as { name?: unknown; browser_download_url?: unknown };
      return typeof candidate.name === 'string'
          && candidate.name === `SimpleSales-${payload.tag_name}.apk`
          && typeof candidate.browser_download_url === 'string';
    });
    if (!match || !apk || typeof apk.browser_download_url !== 'string') return fallback;

    const resolved: PublishedAppRelease = {
      versionName: match[1],
      versionCode: Number(match[2]),
      downloadUrl: apk.browser_download_url,
      notes: typeof payload.body === 'string' ? payload.body : fallback.notes,
    };
    if (!Number.isSafeInteger(resolved.versionCode) || resolved.versionCode <= 0) return fallback;

    appReleaseCache = { expiresAt: Date.now() + 60_000, value: resolved };
    return resolved;
  } catch {
    return fallback;
  }
}

app.get('/api/app/latest', asyncHandler(async (_req, res) => {
  const release = await publishedAppRelease();
  const versionName = release.versionName;
  const versionCode = release.versionCode;
  const downloadUrl = release.downloadUrl;
  const required = process.env.APP_UPDATE_REQUIRED ?? 'false';
  const releaseNotes = release.notes;
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

// Admin routes authenticate their own credential domain. Mount them before
// shop-profile auth so the platform token is never treated as a till user.
if (isNode) {
  app.use('/api', (req, res, next) => {
    const invalidation = adminLiveInvalidationFor(req.method, req.originalUrl);
    if (invalidation) {
      res.once('finish', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) return;
        void broadcastAdmin({
          type: 'admin_data_changed',
          ...invalidation,
          at: new Date().toISOString(),
        }).catch((error) => console.error('admin data invalidation publish failed', error));
      });
    }
    next();
  });
}
app.use('/api/admin/auth', adminAuthRoutes);
app.use('/api/admin/org', adminOrgRoutes);
app.use('/api/admin/membership', adminMembershipRoutes);
app.use('/api/admin', adminRoutes);

app.use('/api', authMiddleware);
// Every successful authenticated mutation is a change signal for the active
// tenant. This covers catalogue, stock, sales, finance, staff and settings
// routes without requiring every route implementation to remember a second
// notifier call. Reads stay silent, and the client re-reads the authoritative
// endpoint after receiving the signal.
app.use('/api', (req, res, next) => {
  res.once('finish', () => {
    if (req.method === 'GET' || res.statusCode < 200 || res.statusCode >= 300) return;
    const tenantId = req.user?.tenantId;
    if (tenantId) broadcastTenantChange(tenantId);
  });
  next();
});
app.use('/api/mpesa', mpesaRoutes);
app.use('/api/tenant/business-context', businessContextRoutes);
app.use('/api/tenant/commercial-consent', commercialConsentRoutes);
app.use('/api/tenant/commercial-contributions', commercialContributionsRoutes);
app.use('/api/tenant/membership', membershipRoutes);
app.use('/api/tenant', tenantRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/products', productRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/sales', salesRoutes);
app.use('/api/backups/full', backupRoutes);
app.use('/api/evidence', evidenceRoutes);
app.use('/api/sale-evidence', authMiddleware, saleEvidenceRoutes);
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
app.use('/api/product-variants', productVariantRoutes);
app.use('/api/cost-pools', costPoolRoutes);
app.use('/api/owner-transactions', ownerTransactionRoutes);

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

// ---------------------------------------------------------------------------

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

app.use(errorHandler);

if (isNode && require.main === module) {
  const server = app.listen(PORT, () =>
    log('info', 'server.started', { port: PORT, environment: process.env.NODE_ENV ?? 'development' }),
  );
  const wss = new WebSocketServer({ server, path: '/api/live' });
  wss.on('connection', async (ws, request) => {
    const token = request.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
    const tenantId = request.headers['x-tenant-id'];
    const claims = token ? verifyAccessToken(token) : null;
    if (!claims || typeof tenantId !== 'string' || tenantId.trim() === '') {
      ws.close(1008, 'Authentication required');
      return;
    }
    const profile = await prisma.profile.findFirst({
      where: { userId: claims.sub, tenantId, active: true, deletedAt: null },
      select: { id: true },
    }).catch(() => null);
    if (!profile) {
      ws.close(1008, 'Tenant access denied');
      return;
    }
    const client = { socket: ws, tenantId };
    addLiveClient(client);
    ws.once('close', () => removeLiveClient(client));
    ws.on('message', (raw) => {
      try {
        const message = JSON.parse(raw.toString()) as { type?: unknown };
        if (message.type === 'read' && ws.readyState === ws.OPEN) {
          ws.send(JSON.stringify({
            type: 'snapshot',
            reasons: [],
            at: new Date().toISOString(),
          }));
        }
      } catch {
        // Unknown/malformed frames are ignored; the HTTP API remains the
        // source of truth and a bad optional signal must not kill the socket.
      }
    });
    ws.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
  });

  const adminWss = new WebSocketServer({ server, path: '/api/admin/live' });
  adminWss.on('connection', async (ws, request) => {
    const requestUrl = new URL(request.url ?? '/', 'http://localhost');
    const ticket = requestUrl.searchParams.get('ticket') ?? '';
    const expectedOrigin = process.env.ADMIN_APP_ORIGIN;
    const origin = request.headers.origin;
    const access = consumeAdminWebSocketTicket(ticket);
    if ((expectedOrigin && origin !== expectedOrigin) || !access) {
      ws.close(1008, 'System administrator access required');
      return;
    }
    const client = { socket: ws, ...access };
    addAdminLiveClient(client);
    ws.once('close', () => removeAdminLiveClient(client));
    ws.on('message', (raw) => {
      try {
        const message = JSON.parse(raw.toString()) as { type?: unknown };
        if (message.type === 'read' && ws.readyState === ws.OPEN) {
          ws.send(JSON.stringify({ type: 'snapshot', reasons: [], at: new Date().toISOString() }));
        }
      } catch {
        // ignore
      }
    });
    ws.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
  });

  setMpesaPaymentNotifier(() => {
    broadcastAll({ type: 'mpesa_incoming' });
  });
  setPlatformAnnouncementNotifier((announcement) => {
    broadcastAll({
      type: announcement.id ? 'platform_announcement' : 'platform_announcement_cleared',
      ...(announcement.id ? { announcement } : {}),
    });
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
