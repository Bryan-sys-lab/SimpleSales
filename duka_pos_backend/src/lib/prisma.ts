import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import { Pool } from 'pg';

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

function createPrisma(): PrismaClient {
  const url = process.env.DATABASE_URL || '';
  const pool = new Pool({ connectionString: url });
  const adapter = new PrismaPg(pool);
  return new PrismaClient({ adapter });
}

// Lazy proxy: client is created on first use, after the Worker has populated
// process.env.DATABASE_URL from the Hyperdrive binding.
export const prisma: PrismaClient = new Proxy({} as PrismaClient, {
  get(_target, prop) {
    if (!globalForPrisma.prisma) {
      globalForPrisma.prisma = createPrisma();
    }
    return (globalForPrisma.prisma as any)[prop];
  },
}) as PrismaClient;
