# Cloudflare Workers Paid deployment budget

`duka_pos_backend/docker-compose.yml` remains the complete local verification
stack. It runs PostgreSQL, Keycloak, Keycloak initialization, local S3 storage,
migrations, and the API together so the full app can be tested with one
command. It is not the production topology for the $5/month Workers Paid
allowance.

`duka_pos_backend/docker-compose.cloudflare.yml` is the production-shaped
origin. It runs only migrations and the stateless API, using externally supplied
PostgreSQL, OIDC, and Cloudflare R2 endpoints.

## Production boundary

- Cloudflare Workers: edge routing, TLS, rate limiting, and small request
  orchestration only. Do not put report generation, PDF creation, Prisma, or
  large backup payloads in a Worker invocation.
- Cloudflare R2: profile images and encrypted backup objects. PostgreSQL stores
  only object keys/URLs and metadata; never store image bytes in PostgreSQL.
- External managed PostgreSQL: the source of truth for tenants, sales,
  inventory, credits, audit records, and analytics aggregates.
- External OIDC provider: Keycloak may be used locally and in a separately
  sized production service. It must not be started beside the API container on
  the included container allowance. Cloudflare D1 is SQLite-based and is not a
  drop-in database for this Prisma/PostgreSQL schema or Keycloak.
- One stateless API container: use `standard-1` (0.5 vCPU / 4 GiB) as the
  starting profile. Scale to zero when idle and keep a second system's budget
  available rather than running separate containers per shop.

## Budget guardrails

The supplied allowance is 375 vCPU-minutes, 25 GiB-hours memory, and 200
GB-hours disk per month. Treat 40% as the maximum planned usage for this app:

| Resource | App budget | Why |
| --- | ---: | --- |
| CPU | 150 vCPU-minutes/month | Leaves room for a second system and bursts |
| Memory | 10 GiB-hours/month | API is scale-to-zero; DB/OIDC are external |
| Disk | 80 GB-hours/month | Local container disk is scratch only |
| Worker requests | 5M/month target | Leaves half of the 10M included requests |
| Worker CPU | 15M ms/month target | Leaves half of the 30M included CPU |
| R2 storage | 5 GB target | Leaves half of the 10 GB included storage |

These are operational targets, not hard Cloudflare limits. Alert at 70% of
each target and stop background jobs before an overage can become a surprise.

## Required production settings

Set `DATABASE_URL`, `OIDC_ISSUER_URL`, `OIDC_JWKS_URI`, `FRONTEND_URL`, and the
R2 variables from the deployment secret store. The compose defaults are local
only. Keep the Prisma URL's `connection_limit` low (start at 5 per API
instance) and increase it only after measuring the managed database pool.

Run only bounded, paginated sync/report requests. Generate PDFs on the device
for local export, and upload encrypted backups as one R2 object rather than
streaming them through a Worker. Never cache tenant-specific API responses at
the edge.

## Verification

```sh
docker compose -f duka_pos_backend/docker-compose.yml config --quiet
docker compose -f duka_pos_backend/docker-compose.yml up -d
docker compose -f duka_pos_backend/docker-compose.yml --profile verify run --rm tests
docker compose -f duka_pos_backend/docker-compose.yml down
```

For the Cloudflare-shaped origin, provide all required secrets first, then run:

```sh
docker compose -f duka_pos_backend/docker-compose.cloudflare.yml config --quiet
docker compose -f duka_pos_backend/docker-compose.cloudflare.yml up -d
```

The final `down` is required for local cleanup. Production deployments should
use an external Postgres/OIDC service and deploy only the API container; do not
copy the local `db`, `keycloak`, or `storage` services into the paid runtime.
