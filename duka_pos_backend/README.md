# Duka POS Backend - Custom TypeScript API

Production-ready TypeScript backend replacing Supabase with Express + Prisma + self-hosted OIDC.

## Why This Approach?

**Keycloak/OIDC for Authentication** instead of building from scratch because:
- ✓ Battle-tested security (JWT handling, session management, password hashing)
- ✓ Built-in OAuth providers (Google, Facebook)
- ✓ Multi-factor authentication
- ✓ Password reset, email verification
- ✓ Free tier: 7,000 active users/month
- ✓ Claims-based auth works perfectly with multi-tenant architecture

**Custom TypeScript Backend** vs Supabase:
- ✓ Full control over business logic
- ✓ Easier to debug and extend
- ✓ No vendor lock-in
- ✓ Can deploy anywhere (AWS, DigitalOcean, Railway)

## Quick Start

```bash
# Install dependencies
npm install

# Setup PostgreSQL database
createdb duka_pos

# Copy environment variables
cp .env.example .env

# Run Prisma migrations
npm run db:push

# Start development server
npm run dev
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│   Keycloak/OIDC  │────▶│  PostgreSQL DB  │
│                 │     │   (JWT Tokens)   │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                                ▲
         │                                                │
         └────────────────────────────────────────────────┘
                     Express API (Protected)
                     - Tenant management
                     - Product sync
                     - Payment orchestration
```

## Self-hosted Keycloak/OIDC setup

1. Create the Keycloak realm and public mobile client described in `../KEYCLOAK_DEPLOYMENT.md`.
2. Use Authorization Code + PKCE for the Android/iOS client; do not embed a client secret in Flutter.
3. Add `.env` variables:
   ```env
   OIDC_ISSUER_URL=https://id.example.com/realms/duka
   OIDC_AUDIENCE=duka-api
   OIDC_JWKS_URI=https://id.example.com/realms/duka/protocol/openid-connect/certs
   PUBLIC_API_URL=https://api.example.com
   ```

4. Prepare the database:
```bash
npm run db:generate
npm run db:deploy
```

For an existing owner/staff deployment, take a verified backup and run `npm run db:deploy` as normal. The chain is additive and re-runnable: `20260929220000_reconcile_legacy_roles` maps the legacy `('owner','staff')` role vocabulary to `('admin','manager','cashier')` and adds every column, table and index the old schema is missing (`deletion_ledger`, the `profiles` OIDC columns, the portion prices and decimal stock).

`npm run db:migrate:roles` is retained for runbooks that reference it, but it only reconciles the role column — prefer the full chain.

## Database Schema

Same as your existing Supabase schema:
- `tenants` - Multi-tenant shops
- `profiles` - Users with shop roles (admin/manager/cashier)
- `products` - Product catalog
- `sales` - Sales records
- `payments` - M-Pesa payment tracking

Prisma enforces tenant isolation in application code instead of PostgreSQL RLS.

Platform administration is separate from shop administration. Set `SYSTEM_ADMIN_SUBJECTS` for the small, audited set of Keycloak subjects allowed to use `/api/system/users`, `/api/system/analytics`, and cross-tenant backend configuration. Shop admins cannot grant this privilege.

## API Endpoints

### Tenant Management
- `POST /api/tenant/provision` - Register new shop
- `GET /api/tenant/settings` - Get tenant config
- `GET /api/tenant/shops` - List shops available to the authenticated OIDC owner
- `PATCH /api/tenant/settings` - Update settings (owner only)
- `POST /api/tenant/staff` - Add staff member (owner only)

### Products
- `POST /api/products/sync` - Bulk sync from app
- `GET /api/products` - List all products

### Platform system administration
- `GET /api/system/users` - Active users across all shops (system-admin allowlist only)
- `GET /api/system/analytics` - Cross-tenant aggregate analytics and per-tenant payment breakdowns
- `PATCH /api/system/tenants/:tenantId/settings` - Configure a tenant backend integration

### Payments
- `POST /api/payments/initiate` - Start M-Pesa payment
- `GET /api/payments/status?reference=xxx` - Check payment status

### Webhooks
- `POST /webhooks/payhero-callback` - PayHero callback (no auth)

## Flutter Integration

Replace `backend_service.dart` with:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackendService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://your-api.com/api',
  ));
  
  static const _storage = FlutterSecureStorage();
  
  static Future<void> setAuthToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    _dio.interceptors.clear();
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      }
    ));
  }
  
  // Everything else stays the same, just HTTP calls instead of Supabase SDK
}
```

## Deploy to Production

### Option 1: Railway.app (Easiest)
```bash
railway init
railway add postgresql
railway run -- npm run db:push
railway up
```

### Option 2: AWS
- Use AWS RDS for PostgreSQL
- Deploy to AWS App Runner or EC2
- Set environment variables in AWS console

### Option 3: DigitalOcean
- Use Managed PostgreSQL
- Deploy to App Platform

## Security

- ✓ JWT verification via OIDC JWKS
- ✓ Tenant isolation enforced in application code
- ✓ SQL injection prevention via Prisma
- ✓ CORS configured
- ✓ Helmet.js for HTTP headers
- ✓ Runtime request validation and bounded JSON bodies
- ✓ Rate limits on API and PayHero webhook traffic
- ✓ PayHero secrets never exposed to client

### PostgreSQL RLS and mobile workspace isolation

Tenant isolation is currently enforced **in the application layer**: the
`x-tenant-id` header is validated against the caller's OIDC profile memberships
on every protected request, and every query is filtered by that tenant id.

`prisma/ENABLE_RLS.sql` is an **optional, manual** defence-in-depth script. It
is deliberately NOT part of `prisma/migrations/`, because the API does not yet
set a transaction-local tenant context and the platform system-admin endpoints
intentionally perform cross-tenant reads. Applying it today would return zero
rows for every tenant query. The file documents the required wiring (non-superuser
role, `set_config('app.tenant_id', tenantId, true)` inside the same transaction,
and a dedicated role or policy for system-admin reads) before it should be run.

SQLite has no native RLS. The mobile equivalent is file-level isolation: every
shop uses its own `duka_pos_<workspace>.db`; the original `duka_pos.db` remains
the legacy first-shop workspace. Workspace selection happens before any local
repository access.

SQLite has no native RLS. The mobile equivalent is file-level isolation: every
shop uses its own `duka_pos_<workspace>.db`; the original `duka_pos.db` remains
the legacy first-shop workspace. Workspace selection happens before any local
repository access.

The PayHero callback is not OIDC-protected because PayHero calls it. It re-checks transaction status with PayHero, accepts only references generated by this API, and finalizes a sale inside a database transaction. Add PayHero signature verification before launch if it is available for your account.

## Next Steps

1. Set up the Keycloak realm and get OIDC issuer/audience values
2. Provision PostgreSQL database
3. Update `.env` with your credentials
4. Run `npm run db:push` to create tables
5. Build Flutter with the Keycloak OIDC issuer and public client ID
6. Replace `backend_service.dart` with HTTP calls
7. Deploy backend

## Migration from Supabase

Your Flutter app already has the right architecture:
- Local SQLite is the source of truth
- Backend is optional (only for M-Pesa)
- Product sync happens on-demand

Just replace Supabase SDK calls with HTTP calls to this API.
