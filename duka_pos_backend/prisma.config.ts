/**
 * Prisma's configuration.
 *
 * ## WHY THE CONNECTION STRING IS HERE AND NOT IN THE SCHEMA
 *
 * Prisma 7 took the datasource URL out of `schema.prisma`. The schema says
 * WHAT it is talking to — Postgres — and this file says WHERE, which is the
 * right way round: the URL is a property of the deployment, and a schema
 * that carries it is a schema that has to be edited to move between
 * environments.
 *
 * The CLI reads it from here. The service does not: it builds an ADAPTER
 * (`@prisma/adapter-pg`) and hands that to the client, so the service
 * connects the same way whether it is talking to Postgres, to a pooler, or to
 * something else that speaks the protocol.
 *
 * The URL is read from the environment, and the environment says it: nothing
 * here has a default that could send a development machine at a production
 * database.
 */
import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: process.env.DATABASE_URL ?? '',
  },
});
