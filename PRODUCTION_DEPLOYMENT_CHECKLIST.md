# Production Deployment Checklist

> This checklist now uses self-hosted Keycloak/OIDC. Older Auth0 wording below is historical; follow [KEYCLOAK_DEPLOYMENT.md](KEYCLOAK_DEPLOYMENT.md) for the active identity configuration.

Complete guide to making Duka POS production-ready for both backend and mobile app.

## ✅ Completed Items

**Backend (Custom TypeScript + Auth0)**
- ✅ Express API with JWT authentication
- ✅ Prisma ORM with PostgreSQL schema
- ✅ Auth0 integration (battle-tested auth service)
- ✅ Tenant isolation via application code
- ✅ PayHero M-Pesa integration
- ✅ All API routes implemented

**Mobile App (Flutter)**
- ✅ Auth0 service for backend auth
- ✅ Backend service with HTTP client
- ✅ PIN auth with lockout and secure storage
- ✅ Sell screen with search and cart
- ✅ M-Pesa payment flow
- ✅ Core database tests

---

## 🔴 MUST FIX BEFORE LAUNCH

### 1. Environment Configuration

**Backend (.env):**
```bash
# Copy from duka_pos_backend/.env.example and fill in:
- OIDC_ISSUER_URL=https://id.example.com/realms/duka
- OIDC_AUDIENCE=duka-api
- OIDC_JWKS_URI=https://id.example.com/realms/duka/protocol/openid-connect/certs
- DATABASE_URL=postgresql://...
- PAYHERO_AUTH_TOKEN=Basic ...
```

**Flutter (compile-time variables):**
```bash
# Build with Keycloak/OIDC settings:
flutter build apk --dart-define=OIDC_ISSUER_URL=https://id.example.com/realms/duka --dart-define=OIDC_CLIENT_ID=duka-pos-mobile --dart-define=OIDC_REDIRECT_URL=dukapos://callback --dart-define=BACKEND_URL=https://your-api.com/api
```

**Or create `lib/env.dart`:**
```dart
class Env {
  static const oidcIssuerUrl = String.fromEnvironment('OIDC_ISSUER_URL');
  static const oidcClientId = String.fromEnvironment('OIDC_CLIENT_ID');
  static const backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:3000/api');
}
```

### 2. Deploy Backend (Choose One)

**Option A: Railway.app (Easiest)**
```bash
cd duka_pos_backend
npm install
railway init
railway add postgresql
railway run -- npm run db:push
railway up
```

**Option B: AWS**
- RDS PostgreSQL database
- Deploy to App Runner or EC2 with Docker
- Set environment variables in AWS console

**Option C: DigitalOcean**
- Managed PostgreSQL
- App Platform deployment

### 3. Configure Auth0

1. Create Auth0 account (free tier: 7,000 users/month)
2. Create **Native Application** for Flutter
3. Create **API** with identifier: `https://duka-pos-api.example.com`
4. Add to Dashboard:
   - **Allowed Callback URLs:** `dukapos://callback`
   - **Allowed Logout URLs:** `dukapos://callback`
   - **Grant Types:** Enable Password, Refresh Token, Authorization Code

### 4. Database Migrations

```bash
cd duka_pos_backend
npm run db:push  # Creates all tables
```

### 5. Input Validation (All Forms)

Add validation to ALL input fields:

**Products:**
```dart
// In product form screen
if (name.trim().isEmpty) {
  return 'Product name required';
}
if (costPrice < 0 || sellPrice < 0) {
  return 'Price cannot be negative';
}
if (stockQty < 0) {
  return 'Stock cannot be negative';
}
if (sellPrice < costPrice) {
  // Warn but allow
  showDialog(...);
}
```

**Staff PIN:**
```dart
if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
  return 'PIN must be exactly 4 digits';
}
```

### 6. Concurrent Edit Protection

Already implemented in sell_screen.dart:
- ✅ `_processingPayment` flag prevents double-submit
- ✅ Button disabled during payment
- Add to inventory forms:
```dart
bool _saving = false;
// ... in submit button
onPressed: _saving ? null : _submit,
```

### 7. Error Messages (User-Friendly)

Replace ALL errors with actionable messages:

**Bad:** `SqliteException: constraint failed`
**Good:** `Couldn't save - product name already exists`

**Bad:** `DioError: 401`
**Good:** `Session expired - please login again`

Create `lib/utils/error_utils.dart`:
```dart
class ErrorUtils {
  static String userMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401) {
        return 'Session expired - login again';
      }
      if (error.type == DioExceptionType.connectionTimeout) {
        return 'No internet - check your connection';
      }
    }
    if (error is StateError) {
      return 'Something went wrong - try again';
    }
    return 'Error: ${error.toString()}';
  }
}
```

### 8. Crash Reporting

**Firebase Crashlytics:**

1. Create Firebase project at console.firebase.google.com
2. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
3. Run: `flutterfire configure`
4. Uncomment in `main.dart`:
```dart
const firebaseConfigured = true; // Set to true
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

### 9. Testing & QA

**Manual Testing Checklist (RUN BEFORE EVERY RELEASE):**

Run through ALL these scenarios:

**Core Flows:**
- [ ] Create owner account
- [ ] Login with correct PIN
- [ ] Login with wrong PIN (verify lockout)
- [ ] Add product
- [ ] Edit product
- [ ] Complete cash sale (1 item)
- [ ] Complete cash sale (5+ items)
- [ ] Try selling more than stock (should fail)
- [ ] Adjust stock
- [ ] Export backup
- [ ] Import backup

**M-Pesa (if enabled):**
- [ ] Register backend
- [ ] Sync products
- [ ] Initiate M-Pesa payment
- [ ] Get STK push
- [ ] Complete payment
- [ ] Cancel payment
- [ ] Check payment timeout

**Edge Cases:**
- [ ] Force-close app mid-checkout → verify DB intact
- [ ] Weak or no internet → verify offline fallback
- [ ] Low battery warning during sale
- [ ] Phone call during sale

**Device Testing:**
- [ ] Test on LOW-END Android device (2GB RAM)
- [ ] Test on different screen sizes
- [ ] Test with poor network connectivity

**Automated Tests:**
```bash
cd duka_pos_app
flutter test
```

### 10. KRA eTIMS Compliance (CRITICAL)

**This app is NOT eTIMS certified yet!**

Before using as primary POS:
1. Confirm if shop is VAT-registered
2. If yes, either:
   - Integrate with KRA eTIMS API (separate project)
   - Use this app for internal tracking + KRA's free eTIMS app for tax invoices

**Do NOT launch without answering this question!**

### 11. App Signing Key Management

```bash
# Generate signing key ONCE, BACKUP SECURELY
keytool -genkey -v -keystore duka-pos-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias duka-pos

# Store in secure location (NOT in git):
# - Password manager
# - Encrypted cloud storage
# - Multiple backups

# Build signed APK:
flutter build apk --release
```

### 12. Staff Training Document

Create one-page guide:
```
DUKA POS - Quick Start Guide
=============================

LOGIN
- 4-digit PIN
- Ask owner for your PIN

SELLING
1. Tap product to add to cart
2. Adjust quantity with +/- 
3. Tap CASH or M-PESA
4. Complete sale

COMMON ISSUES
- "Not enough stock": Check inventory
- "Payment failed": Retry or use cash
- App frozen: Close and reopen

SUPPORT
Call/WhatsApp: +254 XXX XXX XXX
```

Print and laminate for counter.

---

## 🟡 SHOULD FIX SOON

### 13. Update Distribution (If Sideloading)

Without app store, you need in-app update checker:

```dart
// lib/services/update_service.dart
class UpdateService {
  static const currentVersion = '1.0.0';
  
  static Future<String?> checkForUpdate() async {
    final response = await Dio().get(
      'https://api.github.com/repos/yourname/duka-pos/releases/latest',
    );
    
    final latestVersion = response.data['tag_name'];
    if (latestVersion != currentVersion) {
      return response.data['assets'][0]['browser_download_url'];
    }
    return null;
  }
}
```

### 14. Corrupted Database Recovery

Add to `main.dart`:
```dart
try {
  await DatabaseHelper.instance.database;
} catch (e) {
  // Show recovery dialog
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Database corrupted'),
      content: Text('Restore from backup?'),
      actions: [
        TextButton(onPressed: restoreBackup, child: Text('Restore')),
      ],
    ),
  );
}
```

### 15. Locale & Currency

Ensure all amounts show as:
- KSh 12,500 (not 12499.99 or 12500.0000)
- Consistent across ALL screens

Add to `pubspec.yaml`:
```yaml
dependencies:
  intl: ^0.18.1
```

Use:
```dart
final formatted = NumberFormat.currency(symbol: 'KSh ', decimalDigits: 0).format(amount);
```

### 16. Real-Device Testing

Test on actual budget Android phone (2GB RAM, cheap device):
- Performance
- Storage limits
- Screen size
- Touch responsiveness
- Battery drain

### 17. Search All Lists

Add search to:
- ✅ Sell screen (product catalog)
- Inventory screen
- Reports screen

### 18. Support Channel

Create WhatsApp Business or email for support:
- Add to settings screen
- Add to staff training doc
- Set realistic response time expectations

---

## 🟢 BACKLOG (v2)

- Android auto-backup configuration
- Barcode scanning (camera)
- Receipt customization
- Accessibility (font scaling, screen reader)
- Multi-shop support
- Staff offboarding nudges
- eTIMS API integration
- Multi-till LAN sync

---

## Deployment Order

**Week 1: Backend**
1. ✅ Setup PostgreSQL database
2. ✅ Configure Auth0 account
3. ✅ Deploy TypeScript API
4. ✅ Test API endpoints with Postman
5. ✅ Configure PayHero credentials

**Week 2: Mobile App**
1. ✅ Add Auth0 credentials
2. ✅ Test auth flow
3. ✅ Test M-Pesa on test device
4. ✅ Run full QA checklist
5. ✅ Build signed release APK

**Week 3: Pilot**
1. ✅ Deploy to ONE shop
2. ✅ Train staff
3. ✅ Stand by for support (2 weeks)
4. ✅ Fix issues as they arise
5. ✅ Collect feedback

**Week 4+: Rollout**
1. ✅ If pilot successful, expand to more shops
2. ✅ Document lessons learned
3. ✅ Plan v2 features

---

## Quick Deployment Commands

**Backend:**
```bash
cd duka_pos_backend
npm install
cp .env.example .env  # Edit with real values
npm run db:push
npm run build
npm start
```

**Mobile:**
```bash
cd duka_pos_app
flutter pub get
flutter test
flutter build apk --release --dart-define=AUTH0_DOMAIN=... --dart-define=AUTH0_CLIENT_ID=... --dart-define=BACKEND_URL=...
```

**Test backend locally:**
```bash
cd duka_pos_backend
npm run dev  # Starts on localhost:3000
```

---

## Security Checklist

- ✅ Auth0 handles JWT (industry standard)
- ✅ PINs hashed with per-install salt
- ✅ Secure storage (Keystore/Keychain)
- ✅ No credentials in source code
- ✅ HTTPS for backend
- ✅ Tenant isolation in API
- ✅ PayHero secrets server-side only
- ⚠️ Backup files unencrypted (warn users)
- ⚠️ No rate limiting (add to backend)
- ⚠️ No webhook signature verification (verify with PayHero)

---

## Known Limitations

1. **Product sync delay**: Products added locally aren't M-Pesa sellable until synced
2. **No barcode scanning**: Manual product selection only
3. **eTIMS not integrated**: App is for internal tracking, not tax invoices
4. **Single till per install**: Multi-shop needs separate installs
5. **No offline M-Pesa**: Requires internet for payment processing
6. **PayHero webhook security**: Re-verify with PayHero's current signing options
7. **No real-time sync**: Stock can drift between phone and backend

---

## Support Resources

- **Backend README:** `duka_pos_backend/README.md`
- **Auth0 Setup:** `AUTH0_INTEGRATION.md`
- **Production Checklist:** This file
- **KRA eTIMS:** https://itax.kra.go.ke/
- **PayHero Docs:** https://docs.payhero.co.ke/
- **Auth0 Docs:** https://auth0.com/docs

---

## Success Criteria

A shop is production-ready when:
1. ✅ Owner can login and manage products
2. ✅ Staff can complete cash sales
3. ✅ M-Pesa payments work end-to-end (if enabled)
4. ✅ Daily backups are being created
5. ✅ Staff have been trained
6. ✅ Owner understands recovery process
7. ✅ Support channel is active
8. ✅ All 🔴 items above completed
