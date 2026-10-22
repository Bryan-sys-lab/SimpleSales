/**
 * The Prisma client, and the one instance of it.
 *
 * ## THE ADAPTER
 *
 * Prisma 7 does not read a connection string out of the environment by
 * itself. The service says how it connects — an adapter — and the adapter
 * says where. So the URL is read HERE, in one place, and the client is
 * built with it.
 *
 * `@prisma/adapter-pg` speaks the Postgres protocol directly, over the
 * `pg` driver. There is no native engine, no OpenSSL to detect, and no
 * binary to be the wrong shape for the image it is running in — which is
 * what the old setup kept breaking on.
 *
 * ## WHY ONE CLIENT
 *
 * The client holds a connection pool, and a pool per request is a pool that
 * runs out. So the instance is kept on `globalThis` in development, where the
 * module is reloaded on every change and a fresh pool would be opened each
 * time.
 */
import { PrismaPg } from '@prisma/adapter-pg';

import { PrismaClient } from '../generated/prisma/client.js';

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

function createClient(): PrismaClient {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error('DATABASE_URL is not set');
  }
  return new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
  });
}

export const prisma = globalForPrisma.prisma ?? createClient();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
