# Duka POS data protection and operations

## Current guarantees

- Exported automatic backups and the explicit `.duka` backup flow use AES-256-GCM. The key is stored in Android Keystore/iOS Keychain through `flutter_secure_storage`; it is not written into the backup file.
- A local cryptographic-erasure action deletes the local backup key and generated `.duka` files. This makes those local encrypted backups unrecoverable from this installation.
- Backend requests have a bounded request ID, response `x-request-id`, structured JSON request logs, duration/status metrics, generic client errors, and `/health` plus database-backed `/ready` probes.
- Backend payment attribution is derived from the active profile in the tenant. A staff token cannot submit a sale under another cashier profile.
- `/api/reports/sales` is tenant-scoped and role-protected for owner/staff reporting.
- Sentry is opt-in via `SENTRY_DSN`; release traces are sampled at 10%, profiling is disabled, and errors do not include request bodies or tokens.

## Important limits before production approval

The current Flutter database still uses `sqflite`, which is not SQLCipher. Therefore the SQLite file itself is not yet encrypted at rest. The encrypted backup path protects exported files, not a stolen live database while the app is unlocked. Before calling “all local user data encrypted,” migrate the database layer to a maintained SQLCipher-compatible driver, test Android/iOS migrations, and perform a restore test on real devices.

The backend PostgreSQL data is application-queryable plaintext by design. Production must use encrypted database/storage volumes, encrypted provider backups, TLS, secret-manager/KMS storage for PayHero and OIDC secrets, and a documented retention policy. Do not store a database dump and its encryption key in the same backup location.

Local key deletion cannot erase copies already exported to cloud drives, messaging apps, other tills, or provider backups. Full cryptographic erasure requires per-tenant envelope keys in a KMS, destruction of the relevant key version, backup restore filtering using the deletion ledger, and verification that replicas/archives obey the retention policy.

## Operational checks

1. Alert on `/ready` failures, 5xx rate, payment callback failures, stock-conflict rate, and backup age.
2. Keep authorization headers, PINs, phone numbers, payment references, cart snapshots, and access/refresh tokens out of logs and crash reports.
3. Keep deletion-ledger records immutable enough for audit, while anonymizing personal labels in financial records rather than deleting accounting history.
4. Run dependency scanning, Prisma migrations, encrypted-backup restore tests, database restore tests, and Android/iOS release builds in CI.

## Roles and platform administration

Shop roles are `admin` (the owner account created during app setup), `manager`, and `cashier`. Managers can operate inventory/reporting workflows; cashiers are restricted to their own sales reporting and own sale attribution. Only shop admins can manage staff or shop settings.

An OIDC owner may belong to multiple tenants. The API selects the shop using the `x-tenant-id` header and only accepts IDs belonging to that identity; `/api/tenant/shops` lists the available shops. The mobile client persists the selected tenant ID for API scoping.

Products support full, half, and quarter servings. Inventory stock is stored in bottle units with decimal precision, while each product stores bottle millilitres and optional configured portion prices. The server recalculates portion price and stock consumption instead of trusting client prices.

Platform system administration is separate. Set `SYSTEM_ADMIN_SUBJECTS` to a comma-separated allowlist of Keycloak/OIDC subject IDs. Only those subjects can call `/api/system/users`, `/api/system/analytics`, and `/api/system/tenants/:tenantId/settings`. Never derive this privilege from a shop role or an email claim.

Existing deployments must run `prisma/ROLE_MIGRATION.sql` during a controlled migration to translate legacy `owner`/`staff` enum values.
