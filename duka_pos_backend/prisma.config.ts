/**
 * Prisma's configuration.
 *
 * ## WHY THE LOCAL SQLITE URL IS HERE AND NOT IN THE SCHEMA
 *
 * Prisma 7 took the datasource URL out of `schema.prisma`. Prisma CLI
 * operations use a disposable local SQLite database; deployed Workers access
 * D1 through the `DB` binding and Wrangler migrations, never through this URL.
 *
 * Keeping this URL separate from the legacy `DATABASE_URL` prevents a local
 * Prisma command from accidentally targeting a PostgreSQL service.
 */
import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations-d1',
  },
  datasource: {
    url: process.env.D1_LOCAL_DATABASE_URL ?? 'file:./prisma/local.db',
  },
});
