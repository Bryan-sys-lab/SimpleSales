# Reusable Keycloak Worker

This is intentionally separate from `cloudflare/`, so the same OIDC issuer can
serve the SimpleSales API and other applications. Keycloak uses Neon PostgreSQL
for durable state; the container filesystem is not used for realm persistence.

Required Worker secrets:

- `KC_DB_URL`: Neon JDBC URL, for example `jdbc:postgresql://.../keycloak`
- `KC_DB_USERNAME`
- `KC_DB_PASSWORD`
- `KC_HOSTNAME`: the public HTTPS hostname used in issuer URLs
- `KEYCLOAK_ADMIN`
- `KEYCLOAK_ADMIN_PASSWORD`

The public issuer is:

`https://<KC_HOSTNAME>/realms/<realm>`

Create the realm and clients through Keycloak administration or the deployment
bootstrap process. Do not commit realm exports or credentials.
