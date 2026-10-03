import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { authMiddleware, systemAdminMiddleware } from './middleware/auth';
import tenantRoutes from './routes/tenant';
import paymentRoutes from './routes/payment';
import productRoutes from './routes/product';
import { handlePayheroCallback } from './routes/payhero-callback';
import { errorHandler } from './lib/http';
import rateLimit from 'express-rate-limit';
import { prisma } from './lib/prisma';
import { requestContext, log } from './lib/observability';
import reportRoutes from './routes/report';
import systemRoutes from './routes/system';

dotenv.config();

if (process.env.NODE_ENV === 'production' && !process.env.PUBLIC_API_URL?.startsWith('https://')) {
  throw new Error('PUBLIC_API_URL must be an https URL in production');
}

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(requestContext);
const allowedOrigins = (process.env.FRONTEND_URL || '').split(',').map((origin) => origin.trim()).filter(Boolean);
app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : false }));
app.use(express.json({ limit: '256kb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 120, standardHeaders: 'draft-7', legacyHeaders: false }));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});
app.get('/ready', async (req, res, next) => {
  try { await prisma.$queryRaw`SELECT 1`; res.json({ status: 'ready', requestId: req.requestId }); }
  catch (error) { next(error); }
});

// PayHero callback (no auth required - called by PayHero)
app.post('/webhooks/payhero-callback', rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false }), handlePayheroCallback);

// Platform administration is not tenant administration and uses an explicit
// OIDC-subject allowlist. Mount before tenant auth because system admins do
// not need a shop profile to inspect the platform.
app.use('/api/system', systemAdminMiddleware, systemRoutes);

// Protected routes (require OIDC JWT)
app.use('/api', authMiddleware);
app.use('/api/tenant', tenantRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/products', productRoutes);
app.use('/api/reports', reportRoutes);

app.use((req, res) => res.status(404).json({ error: 'Not found', requestId: req.requestId }));
app.use(errorHandler);

if (require.main === module) {
  const server = app.listen(PORT, () => log('info', 'server.started', { port: PORT, environment: process.env.NODE_ENV ?? 'development' }));
  const shutdown = (signal: string) => { log('info', 'server.shutdown', { signal }); server.close(() => void prisma.$disconnect()); };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));
  process.on('unhandledRejection', (reason) => log('error', 'process.unhandled_rejection', { message: reason instanceof Error ? reason.message : 'unknown' }));
  process.on('uncaughtException', (error) => { log('error', 'process.uncaught_exception', { message: error.message, stack: error.stack }); shutdown('uncaughtException'); });
}

export default app;
