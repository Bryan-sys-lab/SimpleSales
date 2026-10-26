# SimpleSales repository map

This map records the current implementation locations used by the expansion
plan. It is deliberately a map of the existing system, not a replacement
architecture.

## Flutter app

- Workspace/account lifecycle: `duka_pos_app/lib/services/workspace_service.dart`,
  `duka_pos_app/lib/services/app_state.dart`, and the entry/setup screens.
- Shop-local persistence and migrations: `duka_pos_app/lib/db/database_helper.dart`.
- Shared sale/product/inventory models: `duka_pos_app/lib/models/models.dart`.
- Profile layer: `duka_pos_app/lib/profile/`.
- Shared sales UI: `duka_pos_app/lib/widgets/sell_page.dart` and
  `duka_pos_app/lib/screens/sell_screen.dart`.
- Shared analytics: `duka_pos_app/lib/services/analytics.dart` and the
  dashboard/analytics screens.
- Shared expenses and till movements: `duka_pos_app/lib/screens/cash_control_sheets.dart`,
  `duka_pos_app/lib/screens/expenses_screen.dart`, and the expense methods in
  `database_helper.dart`.
- Shop-scoped transaction timeline: `duka_pos_app/lib/screens/transactions_screen.dart`.
- Cross-shop reporting: `duka_pos_app/lib/services/local_portfolio_service.dart`,
  `duka_pos_app/lib/services/portfolio_kpis.dart`, and
  `duka_pos_app/lib/screens/portfolio_screen.dart`.
- Backup/restore and sync: `duka_pos_app/lib/services/encrypted_backup_service.dart`,
  `database_helper.dart`, and `backend_service.dart`.

## Backend

- Express entry/authentication: `duka_pos_backend/src/index.ts` and
  `duka_pos_backend/src/middleware/`.
- Tenant provisioning/settings/portfolio: `duka_pos_backend/src/routes/tenant.ts`.
- Shared validation contracts: `duka_pos_backend/src/lib/validation.ts`.
- Sales, product, payment, credit, operational and backup routes:
  `duka_pos_backend/src/routes/`.
- System-admin API: `duka_pos_backend/src/routes/admin.ts` and
  `duka_pos_backend/src/routes/system.ts`.
- Canonical server schema and migrations: `duka_pos_backend/prisma/schema.prisma`
  and `duka_pos_backend/prisma/migrations/`.

## Admin console status

The admin console is now present on `main` under `duka_pos_admin/`. It is a
Next.js App Router application with OIDC/PKCE login, protected middleware,
dashboard, churn, sales, sessions, tenants, support and audit views. Its API
client consumes the protected backend `/api/admin` routes, including profile
visibility/counts. The source was recovered from the local `admin` branch
without merging that branch's unrelated Flutter/backend history.

Admin verification:

- `npm run lint` passes with no warnings or errors.
- `next build` passes for all 13 routes.
- The backend build, lint and test suite passes with 125 tests.

## Verification baseline

- Flutter analyzer passes.
- Flutter serial regression passes with 1,647 tests.
- Backend build, lint and serial test suite passes with 125 tests.
- Lifecycle/profile focused tests cover setup, switching, persistence,
  rollback, preview and capability navigation.
- Group C slice adds `duka_pos_app/lib/models/financial_event.dart` and the
  schema-v67 `financial_events` table; sale, expense and expense-void writers
  emit hash-chained UTC events atomically. Focused assertions are in
  `test/database_helper_test.dart`; Flutter analyzer plus database/migration
  verification passes with 160 tests, and the full serial regression passes
  with 1,647 tests.

## Open foundation questions

- Keep tax/legal rules disabled or explicitly review-gated where the plan marks
  them as requiring current KRA/accountant approval.
