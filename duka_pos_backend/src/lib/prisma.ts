import { PrismaD1 } from '@prisma/adapter-d1';
import { PrismaClient } from '../generated/prisma/client';

type D1DatabaseBinding = ConstructorParameters<typeof PrismaD1>[0];
type D1WorkerDatabase = Extract<D1DatabaseBinding, { prepare: unknown; batch: unknown }>;

const globalForPrisma = globalThis as typeof globalThis & {
  prisma?: PrismaClient;
  d1?: D1DatabaseBinding;
};

export function setD1DatabaseBinding(binding: D1DatabaseBinding | undefined): void {
  if (binding && !globalForPrisma.d1) globalForPrisma.d1 = binding;
}

export function getD1DatabaseBinding(): D1WorkerDatabase {
  const binding = globalForPrisma.d1;
  if (!binding || !('prepare' in binding) || !('batch' in binding)) {
    throw new Error('Cloudflare D1 binding "DB" is unavailable.');
  }
  return binding;
}

function createPrisma(): PrismaClient {
  return new PrismaClient({ adapter: new PrismaD1(getD1DatabaseBinding()) });
}

// The Worker sets the D1 binding before dispatching each request.
export const prisma: PrismaClient = new Proxy({} as PrismaClient, {
  get(_target, prop) {
    if (!globalForPrisma.prisma) {
      globalForPrisma.prisma = createPrisma();
    }
    return Reflect.get(globalForPrisma.prisma, prop, globalForPrisma.prisma);
  },
}) as PrismaClient;
