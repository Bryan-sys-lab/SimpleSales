# Self-hosted identity with Keycloak

Duka POS uses local PIN authentication for the till. Keycloak is only the online identity provider for backend registration, M-Pesa, and optional cloud sync. A shop can sell cash and manage inventory without internet or Keycloak for as long as local storage remains available.

## Keycloak setup

1. Run Keycloak with PostgreSQL in production; do not use the development H2 database.
2. Create a realm named `duka` and expose its issuer as `https://id.example.com/realms/duka`.
3. Create a public OpenID Connect client named `duka-pos-mobile`.
4. Enable Authorization Code flow, require PKCE with `S256`, and do not create a client secret.
5. Register `dukapos://callback` as the exact Android/iOS redirect URI and logout redirect URI.
6. Add the `offline_access` optional client scope only if long-lived online re-authentication is wanted. It is not required for offline sales.
7. Create an API audience/scope for the backend, for example `duka-api`, and configure the client to request it.

Build the app with:

```bash
flutter build apk --release \
  --dart-define=OIDC_ISSUER_URL=https://id.example.com/realms/duka \
  --dart-define=OIDC_CLIENT_ID=duka-pos-mobile \
  --dart-define=OIDC_API_SCOPE=duka-api \
  --dart-define=OIDC_REDIRECT_URL=dukapos://callback \
  --dart-define=BACKEND_URL=https://api.example.com/api
```

The backend requires:

```dotenv
OIDC_ISSUER_URL=https://id.example.com/realms/duka
OIDC_AUDIENCE=duka-api
OIDC_JWKS_URI=https://id.example.com/realms/duka/protocol/openid-connect/certs
```

Use HTTPS for Keycloak and the API, keep the Keycloak administration host private, use PostgreSQL backups, and rotate signing/backup credentials under an incident procedure. The reverse proxy must overwrite forwarded headers and only Keycloak should be reachable from that proxy.

Changing identity providers does not create offline authorization for the backend: an access token cannot authorize an API request while the server is unreachable. That is intentional. Offline cash sales, local PIN access, SQLite storage, reports, and Excel backups do not call the backend.

If an existing deployment already used Auth0, do not switch providers without an identity migration plan. Keycloak subjects are not automatically equal to Auth0 subjects; import/map users first or provision a controlled account-linking flow before changing `OIDC_ISSUER_URL`.

Backend profiles use an internal profile ID plus an optional `oidcSubject`; sales, payments, and stock adjustments reference the internal profile. Apply the Prisma migration and populate `oidcSubject` for existing owners before enabling the new issuer.

## One authoritative identity

Duka POS has exactly **one** online identity: the Keycloak/OIDC account. There
is no second credential system.

| Concern | Authority | Works offline? |
|---|---|---|
| Who may sell / manage the till | Local 4-digit PIN (salted SHA-256, per-install salt in the OS keystore) | Yes |
| Who the shop belongs to online | Keycloak OIDC account (`sub` + verified `email`) | No |
| Tenant/shop membership | `profiles.oidc_subject` → `tenant_id` | No |
| Cash sales, inventory, reports, backups | Local SQLite (per-shop workspace) | Yes |

The local PIN is a device-bound *unlock* for the till, not an online identity.
It is never sent to the backend and never grants API access.

### Account creation collects

- Shop name
- Owner/admin name
- Owner email — the email that must match the Keycloak account
- 4-digit local admin PIN

The app never collects or stores an online password; Keycloak owns that in the
system browser via Authorization Code + PKCE.

### How the link is established

1. Offline: the shop is created locally with the name, email, and PIN. The shop
   is immediately fully usable — no internet required.
2. When connectivity is available, the app requests a Keycloak token.
3. The backend requires the **verified email in the token to equal** the email
   captured during local setup (`isVerifiedEmailMatch` in `src/lib/identity.ts`).
   A mismatch or an unverified email is rejected with `403`, so an app cannot
   claim a shop it does not own.
4. On success the tenant id is stored locally and the shop's workspace is
   registered against that tenant.
5. Until then, Settings shows an "Online identity not linked yet" notice with a
   **Verify** action. This is a reminder only; it never blocks selling.

Keycloak must be configured to assert `email` and `email_verified` in the
access token (add the `email` mapper to the client scope). If a realm omits
`email_verified`, the backend treats absence as verified but an explicit
`false` always fails.
