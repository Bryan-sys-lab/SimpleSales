# Duka POS Backend Security Audit

## Executive Summary

This document covers the security review of the Duka POS backend API, including authentication, authorization, input validation, transport security, and production hardening.

## 1. Transport Security

### HTTPS Enforcement
- **Status**: ✅ Implemented
- **Details**: `index.js` rejects startup in production if `PUBLIC_API_URL` is not an HTTPS URL:
  ```javascript
  if (process.env.NODE_ENV === 'production' && !process.env.PUBLIC_API_URL?.startsWith('https://')) {
    throw new Error('PUBLIC_API_URL must be an https URL in production');
  }
  ```
- **HSTS**: Helmet's `hsts` middleware is available and should be enabled in production via `helmet.default.hsts({ maxAge: 31536000, includeSubDomains: true, preload: true })`.

### TLS Configuration
- Production deployments MUST use TLS 1.2 or higher
- Certificates MUST be valid and issued by a trusted CA
- Forward secrecy MUST be enabled

## 2. Security Headers (Helmet)

All responses include the following security headers:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME-type sniffing |
| `X-Frame-Options` | `DENY` | Prevents clickjacking via iframes |
| `Content-Security-Policy` | Restrictive | Prevents XSS and injection attacks |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limits referrer information leakage |
| `X-Request-ID` | UUID | Request tracing for audit logs |
| `X-Powered-By` | Removed | Hides server technology |

### Verification
```bash
curl -sI https://api.duka-pos.example.com/health
```
Should return all security headers listed above.

## 3. Authentication & Authorization

### OIDC / Keycloak Integration
- **Provider**: Self-hosted Keycloak (OIDC/OAuth2)
- **Token Validation**: RS256-signed JWTs verified via JWKS endpoint
- **Middleware**: `express-jwt` with `jwks-rsa` for key rotation
- **Audience/Issuer**: Strictly validated against configured values

### Role-Based Access Control (RBAC)
| Role | Can Access |
|------|-----------|
| `admin` (shop owner) | All tenant-level operations, staff management, settings |
| `manager` | Product sync, reports, settings (read-only for some) |
| `cashier` | Sales, inventory view, own profile |

### Endpoint Protection Matrix
| Endpoint | Method | Required Role | Auth Type |
|----------|--------|---------------|-----------|
| `/health` | GET | None | None |
| `/ready` | GET | None | None |
| `/api/auth/*` | POST | None | App challenge flow |
| `/api/etims/*` | GET/POST | Any authenticated | OIDC JWT |
| `/api/tenant/*` | GET/POST/PATCH/DELETE | Role-dependent | OIDC JWT |
| `/api/payments/*` | GET/POST | Any authenticated | OIDC JWT |
| `/api/products/*` | GET/POST | Manager+ | OIDC JWT |
| `/api/reports/*` | GET | Any authenticated | OIDC JWT |
| `/api/system/*` | GET/PATCH | System admin | OIDC JWT + allowlist |
| `/api/app/latest` | GET | None | None (manifest) |

### Multi-Tenancy
- Tenant isolation enforced via `x-tenant-id` header
- `authMiddleware` loads user profile and verifies tenant membership
- Cross-tenant access rejected with 403/409
- Row-level security via `remote_id` scope validation

## 4. Input Validation (Zod)

All request bodies are validated against strict Zod schemas:

### Key Schemas
- **provisionSchema**: shop name, owner name, email (validated format)
- **settingsSchema**: boolean flags, positive channel ID (max 2M)
- **productSyncSchema**: Array of products with UUID remote IDs, bounded prices
- **paymentSchema**: Items array, phone number regex, duplicate product check
- **staffSyncSchema**: Array of staff with cashier/manager roles only
- **authLinkSchema**: Email, PIN (4-8 chars), shop/owner names
- **authVerifySchema**: Email, PIN, 6-digit code
- **etimsReceiptSchema**: Flexible payload + optional device ID
- **stockAdjustSchema**: UUID product ID, bounded delta (-1M to 1M)

### Validation Benefits
- Type coercion prevented (strict mode on critical schemas)
- SQL injection prevented (Prisma parameterized queries)
- Duplicate submission detected (payment superRefine)
- Role enum restricted (cashier/manager only)

## 5. Rate Limiting

### Global Rate Limiter
- **Window**: 60 seconds
- **Limit**: 120 requests per window
- **Headers**: `ratelimit-limit`, `ratelimit-remaining`, `ratelimit-reset` (draft-7)

### PayHero Webhook Rate Limiter
- **Window**: 60 seconds
- **Limit**: 30 requests per window
- **Purpose**: Prevent webhook flooding

### Testing
```bash
# Should return 429 after 120 requests in 60 seconds
for i in $(seq 1 130); do
  curl -s -o /dev/null -w "%{http_code} " http://localhost:3000/health
done
```

## 6. Secrets Management

### Environment Variables
| Variable | Purpose | Required |
|----------|---------|----------|
| `DATABASE_URL` | PostgreSQL connection string | Yes |
| `OIDC_ISSUER_URL` | Keycloak issuer URL | Yes |
| `OIDC_AUDIENCE` | JWT audience | Yes |
| `OIDC_JWKS_URI` | JWKS endpoint | Auto-derived from issuer |
| `PAYHERO_AUTH_TOKEN` | PayHero API token | Yes (for payments) |
| `PUBLIC_API_URL` | Public API URL (HTTPS in prod) | Yes |
| `FRONTEND_URL` | Allowed CORS origins | Yes |
| `SYSTEM_ADMIN_SUBJECTS` | System admin OIDC subjects | Yes |
| `SMTP_HOST` | Email SMTP host | Optional (for codes) |
| `SMTP_PORT` | Email SMTP port | Optional |
| `SMTP_USER` | SMTP username | Optional |
| `SMTP_PASS` | SMTP password | Optional |

### Secret Storage
- Secrets MUST be stored in environment variables, never in code
- Production deployments MUST use a secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.)
- `.env` files MUST NOT be committed to version control

## 7. Database Security

### Prisma ORM
- All queries use parameterized statements (no SQL injection)
- Connection pooling configured
- SSL/TLS required for production database connections

### Row-Level Security
- `remote_id` scope validation prevents cross-tenant writes
- Tenant ID validated on every request via `x-tenant-id` header
- Staff deletion uses tombstones (preserves referential integrity)

## 8. Audit Logging

### Request Logging
- Every request logged with: timestamp, level, event, requestId, method, path, status, duration
- JSON format for log aggregation
- Request IDs propagated via `X-Request-ID` header

### Error Logging
- Errors logged with status code and message
- 5xx errors logged as `error` level
- 4xx errors logged as `warn` level

## 9. Deployment Security

### Docker Configuration
- Non-root user (`nodejs`, UID 1001)
- Read-only root filesystem where possible
- Health checks on `/health` endpoint
- Resource limits recommended (CPU, memory)

### Docker Compose Security
- PostgreSQL: Non-root, dedicated user/password
- Keycloak: Admin credentials via environment variables
- Backend: No secrets in image, all via environment

### Production Checklist
- [ ] HTTPS enforced with valid certificates
- [ ] `PUBLIC_API_URL` set to HTTPS URL
- [ ] `FRONTEND_URL` restricted to known origins
- [ ] Database password is strong and unique
- [ ] Keycloak admin credentials changed from defaults
- [ ] System admin subjects list populated
- [ ] SMTP configured for email codes
- [ ] PayHero credentials configured
- [ ] Rate limiting tested
- [ ] Security headers verified
- [ ] Log aggregation configured
- [ ] Regular dependency updates scheduled

## 10. Known Limitations

1. **In-memory telemetry/events**: Single-server only; Redis recommended for multi-server
2. **In-memory eTIMS queue**: Should be moved to Prisma tables for production
3. **In-memory auth sessions**: Should be moved to Redis/Prisma for multi-server
4. **No refresh token rotation detection**: Replayed refresh tokens accepted until expiry
5. **Email codes logged in development**: SMTP must be configured for production

## 11. Penetration Testing Recommendations

1. Test for SQL injection (should be blocked by Prisma)
2. Test for XSS (should be blocked by CSP)
3. Test for IDOR on tenant-scoped endpoints
4. Test rate limiting effectiveness
5. Test CORS misconfiguration
6. Test JWT bypass (expired tokens, wrong signature)
7. Test file upload limits (256KB JSON body limit)
8. Test for information disclosure in error messages