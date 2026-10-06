# Superseded: Auth0 integration guide

This document is retained only as historical migration context. The app now uses self-hosted OIDC with Keycloak and `flutter_appauth`. Follow [KEYCLOAK_DEPLOYMENT.md](KEYCLOAK_DEPLOYMENT.md) instead.

This guide shows how to replace Supabase Auth with Auth0 in your Flutter app.

## Why Auth0?

- ✓ Production-ready authentication (no security holes)
- ✓ Free tier: 7,000 active users/month
- ✓ Built-in OAuth (Google, Facebook)
- ✓ Multi-factor authentication
- ✓ Perfect for multi-tenant apps
- ✓ PKCE support for mobile apps

## Setup Auth0

1. Create account at [auth0.com](https://auth0.com)
2. Create **Native Application** (for Flutter)
3. Note your:
   - Domain: `your-tenant.auth0.com`
   - Client ID: `abc123...`

## Add Dependencies

Update `pubspec.yaml`:

```yaml
dependencies:
  # Replace supabase_flutter with:
  auth0_flutter: ^1.4.0
  dio: ^5.4.0  # For API calls
  
  # Keep these:
  flutter_secure_storage: ^9.0.0
  shared_preferences: ^2.2.2
```

## Create Auth Service

Create `lib/services/auth0_service.dart`:

```dart
import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Auth0Service {
  static const _storage = FlutterSecureStorage();
  static const _domain = 'YOUR-AUTH0-DOMAIN'; // e.g., dev-xyz.auth0.com
  static const _clientId = 'YOUR-CLIENT-ID';
  
  static late final Auth0 _auth0;
  static Credentials? _credentials;
  
  static void init() {
    _auth0 = Auth0(_domain, _clientId);
  }
  
  // Check if user has valid token
  static Future<bool> get isAuthenticated async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return false;
    
    // Check if expired (optional, Auth0 SDK handles refresh)
    return true;
  }
  
  // Login with email/password
  static Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final creds = await _auth0.api.login(
      username: email,
      password: password,
      connectionOrRealm: 'Username-Password-Authentication',
    );
    
    await _storeCredentials(creds);
  }
  
  // Sign up new user
  static Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    await _auth0.api.signup(
      email: email,
      password: password,
      connection: 'Username-Password-Authentication',
      userMetadata: {'name': name},
    );
    
    // Auto-login after signup
    await loginWithEmail(email: email, password: password);
  }
  
  // Login with Google
  static Future<void> loginWithGoogle() async {
    final creds = await _auth0.webAuthentication(scheme: 'dukapos').login(
      redirectUrl: 'dukapos://callback',
    );
    
    await _storeCredentials(creds);
  }
  
  // Logout
  static Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'refresh_token');
    _credentials = null;
    
    await _auth0.webAuthentication(scheme: 'dukapos').logout(
      redirectUrl: 'dukapos://callback',
    );
  }
  
  // Get current token
  static Future<String?> get accessToken async {
    return await _storage.read(key: 'auth_token');
  }
  
  // Get user ID
  static Future<String?> get userId async {
    return _credentials?.user.sub;
  }
  
  // Store credentials securely
  static Future<void> _storeCredentials(Credentials creds) async {
    _credentials = creds;
    await _storage.write(key: 'auth_token', value: creds.accessToken);
    if (creds.refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: creds.refreshToken!);
    }
  }
}
```

## Update Backend Service

Replace `lib/services/backend_service.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'auth0_service.dart';

const backendUrl = 'https://your-api.com/api';

class BackendService {
  static final _dio = Dio();
  static bool _initialized = false;
  
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    
    final token = await Auth0Service.accessToken;
    if (token != null) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = 'Bearer $token';
          return handler.next(options);
        },
      ));
    }
    _initialized = true;
  }
  
  static Future<String?> get tenantId async =>
      (await SharedPreferences.getInstance()).getString('tenant_id');
  
  static Future<bool> get isBackendLinked async => (await tenantId) != null;
  
  // Provision tenant (replaces Supabase version)
  static Future<void> linkShopToBackend({
    required String email,
    required String password,
    required String shopName,
    required String ownerName,
  }) async {
    await ensureInitialized();
    
    // Login via Auth0
    await Auth0Service.loginWithEmail(email: email, password: password);
    
    // Provision tenant via API
    final response = await _dio.post('$backendUrl/tenant/provision', data: {
      'shop_name': shopName,
      'owner_name': ownerName,
    });
    
    final tid = response.data['tenant_id'];
    if (tid != null) {
      await (await SharedPreferences.getInstance()).setString('tenant_id', tid);
    }
  }
  
  // Product sync (same logic, HTTP instead of Supabase)
  static Future<void> syncProductsToBackend() async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return;
    
    // Get from local DB
    final products = await DatabaseHelper.instance.getProducts(activeOnly: false);
    
    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': products.map((p) => {
        'id': p.id,
        'remoteId': p.remoteId,
        'name': p.name,
        'category': p.category,
        'costPrice': p.costPrice,
        'sellPrice': p.sellPrice,
        'stockQty': p.stockQty,
        'reorderLevel': p.reorderLevel,
        'active': p.active,
      }).toList(),
    });
    
    // Update local IDs with remote IDs
    for (final synced in response.data['synced']) {
      if (synced['remoteId'] != null) {
        await DatabaseHelper.instance.setProductRemoteId(
          synced['localId'], 
          synced['remoteId']
        );
      }
    }
  }
  
  // M-Pesa payment (same logic, HTTP instead of Supabase)
  static Future<String> initiatePayment({
    required List<Map<String, dynamic>> items,
    required String phoneNumber,
    required String staffName,
    String? customerName,
  }) async {
    await ensureInitialized();
    
    final response = await _dio.post('$backendUrl/payments/initiate', data: {
      'items': items,
      'phone_number': phoneNumber,
      'staff_name': staffName,
      if (customerName != null) 'customer_name': customerName,
    });
    
    return response.data['reference'];
  }
  
  static Future<PaymentOutcome> pollPaymentStatus(
    String reference, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await ensureInitialized();
    final deadline = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(deadline)) {
      final response = await _dio.get('$backendUrl/payments/status', 
        queryParameters: {'reference': reference}
      );
      
      final status = response.data['status'];
      if (status == 'SUCCESS') return PaymentOutcome.success;
      if (status == 'FAILED') return PaymentOutcome.failed;
      
      await Future.delayed(const Duration(seconds: 3));
    }
    
    return PaymentOutcome.timedOut;
  }
}
```

## Update main.dart

Add to `lib/main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Auth0
  Auth0Service.init();
  
  // Rest of your existing code...
  await DatabaseHelper.instance.database;
  
  runApp(const DukaPOSApp());
}
```

## Android Setup

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name="com.auth0.android.provider.RedirectActivity">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="dukapos" android:host="callback" />
    </intent-filter>
</activity>
```

## iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>none</string>
        <key>CFBundleURLName</key>
        <string>auth0</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>dukapos</string>
        </array>
    </dict>
</array>
```

## Migration Steps

1. ✅ Backend is already created (`duka_pos_backend/`)
2. Replace `supabase_flutter` with `auth0_flutter` in `pubspec.yaml`
3. Create `auth0_service.dart` (code above)
4. Replace `backend_service.dart` with HTTP version (code above)
5. Add Auth0 credentials from your dashboard
6. Test login flow

## Auth0 Dashboard Config

In Auth0 Dashboard > Application Settings:

- **Allowed Callback URLs**: `dukapos://callback`
- **Allowed Logout URLs**: `dukapos://callback`
- **Grant Types**: Enable "Password", "Refresh Token", "Authorization Code"

## Benefits vs Supabase

| Feature | Supabase | Auth0 |
|---------|----------|-------|
| Auth | ✅ Built-in | ✅ Purpose-built |
| Security | ✅ Good | ✅✅ Enterprise-grade |
| MFA | ⚠️ Manual setup | ✅ Built-in |
| Social login | ✅ OAuth | ✅ 40+ providers |
| Multi-tenant | ✅ Via RLS | ✅ Via metadata |
| Rate limiting | ❌ | ✅ Built-in |
| Anomaly detection | ❌ | ✅ Built-in |

Your existing PIN-based local auth stays the same. Auth0 is only for backend API access (M-Pesa).
