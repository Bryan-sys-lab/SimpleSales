# Duka POS - Production-Ready Implementation

> Authentication note: the current implementation uses self-hosted Keycloak/OIDC with PKCE. Older Auth0 references in this historical document are superseded; use [KEYCLOAK_DEPLOYMENT.md](KEYCLOAK_DEPLOYMENT.md) for current setup.

Complete POS system with custom TypeScript backend, Auth0 authentication, M-Pesa payments, and offline-first Flutter app.

## What's Implemented

### ✅ Backend (duka_pos_backend/)
- Express.js + TypeScript API
- Prisma ORM with PostgreSQL
- Auth0 JWT authentication
- Multi-tenant architecture
- PayHero M-Pesa integration
- All REST endpoints

### ✅ Mobile App (duka_pos_app/)
- Auth0 integration for backend auth
- PIN-based local authentication
- Offline-first SQLite database
- M-Pesa payment flow
- Product search and cart management
- Error handling and user-friendly messages

### ✅ Documentation
- Production deployment checklist
- Auth0 integration guide
- Backend setup instructions
- Testing procedures

---

## Quick Start

### 1. Setup Backend

```bash
cd duka_pos_backend

# Install dependencies
npm install

# Setup PostgreSQL database (choose one)
# Option A: Local PostgreSQL
createdb duka_pos
# Option B: Use Railway/AWS/DigitalOcean managed PostgreSQL

# Copy and configure environment
cp .env.example .env
# Edit .env with your credentials:
# - DATABASE_URL
# - OIDC_ISSUER_URL
# - OIDC_AUDIENCE
# - OIDC_JWKS_URI
# - PAYHERO_AUTH_TOKEN

# Run database migrations
npm run db:push

# Start development server
npm run dev

# Test endpoints
curl http://localhost:3000/health
```

### 2. Setup Auth0

1. Create Auth0 account at (auth0.com)[https://auth0.com] (free tier: 7,000 users/month)
2. Create **Native Application** (for Flutter)
   - Note: Domain and Client ID
3. Create **API** 
   - Identifier: `https://duka-pos-api.example.com`
   - Algorithm: RS256
4. Configure Application Settings:
   - Allowed Callback URLs: `dukapos://callback`
   - Allowed Logout URLs: `dukapos://callback`
5. Update backend `.env`:
   ```
   AUTH0_DOMAIN=your-tenant.auth0.com
   AUTH0_AUDIENCE=https://duka-pos-api.example.com
   ```

### 3. Setup Mobile App

```bash
cd duka_pos_app

# Install dependencies
flutter pub get

# Run tests
flutter test

# Build with Auth0 credentials
flutter build apk \
  --dart-define=AUTH0_DOMAIN=your-tenant.auth0.com \
  --dart-define=AUTH0_CLIENT_ID=your-client-id \
  --dart-define=BACKEND_URL=http://your-backend-url/api

# Or create lib/env.dart for local development:
# See PRODUCTION_DEPLOYMENT_CHECKLIST.md
```

### 4. Deploy Backend

**Railway.app (Recommended):**
```bash
railway init
railway add postgresql
railway run -- npm run db:push
railway up
```

**AWS:**
- RDS for PostgreSQL
- App Runner or EC2 for API
- Set environment variables in console

**DigitalOcean:**
- Managed PostgreSQL
- App Platform deployment

---

## Architecture

```
┌─────────────────┐
│   Flutter App   │
│  - Local SQLite │
│  - PIN auth     │
│  - Offline 1st  │
└────────┬────────┘
         │
         ├──────────────┐
         │              │
         ▼              ▼
┌─────────────┐  ┌──────────────┐
│   Auth0     │  │   Express    │
│  (JWT)      │  │   Backend    │
└─────────────┘  └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │  PostgreSQL  │
                 │  (Prisma)    │
                 └──────────────┘
```

### Authentication Flow

**Local (Staff):** 
- 4-digit PIN (hashed, secure storage)
- Lockout after 5 failed attempts
- Works fully offline

**Backend (Owner):**
- Auth0 email/password or OAuth
- JWT tokens for API access
- Only needed for M-Pesa features

### Multi-Tenant Isolation

- Each shop = one tenant
- Tenant ID stored in JWT profile
- All API queries filtered by tenant
- Enforced in application code (no RLS)

---

## Key Features

### Offline-First
- SQLite is source of truth
- Cash sales work without internet
- M-Pesa requires connectivity
- Automatic sync when online

### M-Pesa Integration
- STK push via PayHero
- Real-time payment polling
- Stock management
- Transaction logging

### Security
- Auth0 for backend auth
- Per-install PIN salt in secure storage
- JWT tokens with automatic refresh
- Tenant isolation

---

## Production Readiness Checklist

See [PRODUCTION_DEPLOYMENT_CHECKLIST.md](PRODUCTION_DEPLOYMENT_CHECKLIST.md) for:

- ✅ Environment configuration
- ✅ Backend deployment steps
- ✅ Auth0 setup details
- ✅ Input validation requirements
- ✅ Error message guidelines
- ✅ Testing procedures
- ✅ KRA eTIMS compliance
- ✅ Security checklist
- ⚠️ Known limitations

**Must-fix before launch:**
1. Fill in all environment variables
2. Deploy backend to production
3. Configure Auth0 credentials
4. Run full QA checklist
5. Test on low-end Android device
6. Confirm KRA eTIMS requirements

---

## Development

### Local Development

**Backend:**
```bash
cd duka_pos_backend
npm run dev
# Runs on http://localhost:3000
```

**Mobile:**
```bash
cd duka_pos_app
flutter run
# Uses default env values from code
```

### Testing

**Backend:**
```bash
npm test  # Not implemented yet
```

**Mobile:**
```bash
flutter test
# Tests: database operations, stock management, checkout transaction
```

### Database Changes

```bash
cd duka_pos_backend

# Edit prisma/schema.prisma
# Then:
npm run db:push  # Development
# Or:
npm run db:migrate  # Production migrations
```

---

## API Endpoints

**Auth required for all `/api/*` routes**

### Tenant
- `POST /api/tenant/provision` - Register new shop
- `GET /api/tenant/settings` - Get tenant config
- `PATCH /api/tenant/settings` - Update settings (owner only)
- `POST /api/tenant/staff` - Add staff member (owner only)

### Products
- `POST /api/products/sync` - Bulk sync from app
- `GET /api/products` - List all products

### Payments
- `POST /api/payments/initiate` - Start M-Pesa payment
- `GET /api/payments/status?reference=xxx` - Check status

### Webhooks
- `POST /webhooks/payhero-callback` - PayHero callback (no auth)

---

## Environment Variables

### Backend (.env)
```bash
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://user:pass@host:5432/db
OIDC_ISSUER_URL=https://id.example.com/realms/duka
OIDC_AUDIENCE=duka-api
OIDC_JWKS_URI=https://id.example.com/realms/duka/protocol/openid-connect/certs
PAYHERO_AUTH_TOKEN=Basic xxx
PAYHERO_BASE_URL=https://backend.payhero.co.ke/api/v2
FRONTEND_URL=https://your-frontend.com
```

### Mobile (compile-time)
```bash
OIDC_ISSUER_URL=https://id.example.com/realms/duka
OIDC_CLIENT_ID=duka-pos-mobile
OIDC_REDIRECT_URL=dukapos://callback
BACKEND_URL=https://your-api.com/api
```

---

## Known Limitations

1. **Product sync delay** - Local products not M-Pesa sellable until synced
2. **No barcode scanning** - Manual product selection only
3. **eTIMS not integrated** - Internal tracking only, not tax invoices
4. **Multiple shop workspaces** - Each shop on one device uses a separate local SQLite workspace; linked backend shops must be set up on the device before switching offline data
5. **No offline M-Pesa** - Requires internet
6. **Shared device auth** - One backend account per till, not per staff

---

## Troubleshooting

### Backend won't start
- Check DATABASE_URL connection
- Verify Auth0 domain/audience
- Run `npm run db:push`

### Mobile app crashes
- Check Auth0 credentials
- Verify backend URL is accessible
- Review Firebase Crashlytics logs

### M-Pesa payments fail
- Confirm PayHero credentials
- Check products are synced (have remoteId)
- Verify tenant has M-Pesa enabled
- Check phone number format

### Auth errors
- Clear app data and re-login
- Verify Auth0 Application settings
- Check JWT token expiry

---

## Support

**Documentation:**
- [PRODUCTION_DEPLOYMENT_CHECKLIST.md](PRODUCTION_DEPLOYMENT_CHECKLIST.md)
- [AUTH0_INTEGRATION.md](AUTH0_INTEGRATION.md)
- [duka_pos_backend/README.md](duka_pos_backend/README.md)

**External Resources:**
- Auth0 Docs: https://auth0.com/docs
- Prisma Docs: https://prisma.io/docs
- PayHero Docs: https://docs.payhero.co.ke/
- KRA eTIMS: https://itax.kra.go.ke/

---

## Next Steps

1. Set up Auth0 account
2. Deploy backend to Railway/AWS
3. Configure environment variables
4. Test M-Pesa flow end-to-end
5. Run production checklist
6. Pilot with one shop
7. Train staff
8. Launch!

---

## License

Proprietary - All rights reserved.

---

## Changelog

### v1.0.0 (Current)
- Custom TypeScript backend replacing Supabase
- Auth0 integration for secure authentication
- M-Pesa payment integration via PayHero
- Complete production documentation
- User-friendly error messages
- Input validation framework
- Comprehensive testing guide
