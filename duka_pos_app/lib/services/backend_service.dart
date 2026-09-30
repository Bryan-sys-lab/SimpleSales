import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'oidc_service.dart';
import 'workspace_service.dart';

/// Backend API service using self-hosted OIDC tokens instead of Supabase.
/// Keeps the same interface as the old backend_service.dart so the
/// rest of the app doesn't need changes.
class BackendService {
  static bool _initialized = false;
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await OidcService.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final selectedTenant =
            (await SharedPreferences.getInstance()).getString('tenant_id');
        if (selectedTenant != null) {
          options.headers['x-tenant-id'] = selectedTenant;
        }
        options.headers['Content-Type'] = 'application/json';
        return handler.next(options);
      },
      onError: (error, handler) async {
        // Handle 401 - token expired
        if (error.response?.statusCode == 401) {
          // Try to re-authenticate
          // Force online re-authentication on the next protected request.
          await OidcService.logout();
        }
        return handler.next(error);
      },
    ));

    _initialized = true;
  }

  static Future<String?> get tenantId async =>
      (await SharedPreferences.getInstance()).getString('tenant_id');

  static Future<bool> get isBackendLinked async => (await tenantId) != null;

  static Future<List<Map<String, dynamic>>> listMyShops() async {
    await ensureInitialized();
    final response = await _dio.get('$backendUrl/tenant/shops');
    return (response.data['shops'] as List? ?? const [])
        .whereType<Map>()
        .map((shop) => Map<String, dynamic>.from(shop))
        .toList();
  }

  static Future<void> switchShop(String selectedTenantId) async {
    if (selectedTenantId.trim().isEmpty) {
      throw ArgumentError.value(selectedTenantId, 'selectedTenantId');
    }
    final existing =
        await WorkspaceService.workspaceForTenant(selectedTenantId);
    if (existing == null) {
      throw StateError('This shop is not set up on this device yet');
    }
    await (await SharedPreferences.getInstance())
        .setString('tenant_id', selectedTenantId);
    await WorkspaceService.setActiveWorkspace(existing);
  }

  /// Platform backend configuration is restricted to the explicit system
  /// administrator allowlist; shop admins manage only their own shop data.
  static Future<void> requireSystemAdmin() async {
    if (!await OidcService.isAuthenticated && !await OidcService.login()) {
      throw StateError('System administrator authentication required');
    }
    await ensureInitialized();
    await _dio.get('$backendUrl/system/access');
  }

  static Future<void> configureTenantAsSystemAdmin(
      {required String tenantId, required int channelId}) async {
    await requireSystemAdmin();
    await _dio.patch('$backendUrl/system/tenants/$tenantId/settings',
        data: {'mpesaEnabled': true, 'payheroChannelId': channelId});
  }

  /// One-time backend registration after the owner completes OIDC login.
  static Future<void> linkShopToBackend({
    required String shopName,
    required String ownerName,
    String email = '',
  }) async {
    if (!await OidcService.isAuthenticated && !await OidcService.login()) {
      throw StateError('Could not authenticate with backend');
    }
    await ensureInitialized();

    // Provision tenant via API
    try {
      final response = await _dio.post('$backendUrl/tenant/provision', data: {
        'shopName': shopName,
        'ownerName': ownerName,
        'email': email,
      });

      final tid = response.data['tenant_id'];
      if (tid != null) {
        await (await SharedPreferences.getInstance())
            .setString('tenant_id', tid);
        final workspace = await WorkspaceService.activeWorkspaceKey();
        await WorkspaceService.register(
            workspaceKey: workspace, tenantId: tid, shopName: shopName);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // The OIDC account may already be linked from an earlier attempt.
        // Preserve the server's tenant ID so the app does not look unlinked.
        final existingTenantId =
            e.response?.data is Map ? e.response?.data['tenant_id'] : null;
        if (existingTenantId is String && existingTenantId.isNotEmpty) {
          await (await SharedPreferences.getInstance())
              .setString('tenant_id', existingTenantId);
          await WorkspaceService.register(
              workspaceKey: await WorkspaceService.activeWorkspaceKey(),
              tenantId: existingTenantId,
              shopName: shopName);
          return;
        }
      }
      throw StateError('Could not register shop: ${e.message}');
    }
  }

  /// Enable/disable M-Pesa payments
  static Future<void> setMpesaEnabled(bool enabled, {int? channelId}) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) throw StateError('Shop is not linked to backend');

    await _dio.patch('$backendUrl/tenant/settings', data: {
      'mpesaEnabled': enabled,
      if (channelId != null) 'payheroChannelId': channelId,
    });
  }

  /// Enable/disable eTIMS flag
  static Future<void> setEtimsEnabled(bool enabled) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) throw StateError('Shop is not linked to backend');

    await _dio.patch('$backendUrl/tenant/settings', data: {
      'etimsEnabled': enabled,
    });
  }

  /// Sync local products to backend (bulk upsert)
  static Future<void> syncProductsToBackend() async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return;

    final products =
        await DatabaseHelper.instance.getProducts(activeOnly: false);

    if (products.isEmpty) return;

    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': products
          .map((p) => {
                'id': p.id,
                'remoteId': p.remoteId,
                'name': p.name,
                'category': p.category,
                'costPrice': p.costPrice,
                'sellPrice': p.sellPrice,
                'stockQty': p.stockQty,
                'reorderLevel': p.reorderLevel,
                'bottleMl': p.bottleMl,
                'halfPrice': p.halfPrice,
                'quarterPrice': p.quarterPrice,
                'exciseStampBatch': p.exciseStampBatch,
                'active': p.active,
              })
          .toList(),
    });

    // Update local DB with remote IDs
    final synced = response.data['synced'] as List?;
    if (synced != null) {
      for (final item in synced) {
        final localId = item['localId'];
        final remoteId = item['remoteId'];
        if (localId != null &&
            remoteId != null &&
            localId is int &&
            remoteId is String) {
          await DatabaseHelper.instance.setProductRemoteId(localId, remoteId);
        }
      }
    }
  }

  static Future<void> syncStaffToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    final tombstones =
        await DatabaseHelper.instance.getStaffDeletionTombstones();
    for (final tombstone in tombstones) {
      final remoteId = tombstone['remote_id'];
      final localId = tombstone['staff_id'];
      if (remoteId is String && localId is int) {
        try {
          await _dio.delete('$backendUrl/tenant/staff/$remoteId',
              data: {'reason': 'Cashier deletion requested on till'});
        } on DioException catch (error) {
          if (error.response?.statusCode != 404) rethrow;
        }
        await DatabaseHelper.instance.clearStaffDeletionTombstone(localId);
      } else if (localId is int) {
        await DatabaseHelper.instance.clearStaffDeletionTombstone(localId);
      }
    }
    final deletedIds =
        tombstones.map((row) => row['staff_id']).whereType<int>().toSet();
    final staff = (await DatabaseHelper.instance.getStaff(activeOnly: false))
        .where((s) => s.id == null || !deletedIds.contains(s.id))
        .toList();
    final response = await _dio.post('$backendUrl/tenant/staff/sync', data: {
      'staff': staff
          .map((s) => {
                'localId': s.id,
                'remoteId': s.remoteId,
                'name': s.name,
                'role': s.role,
                'active': s.active,
              })
          .toList(),
    });
    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    for (final item in synced) {
      final localId = item['localId'];
      final remoteId = item['remoteId'];
      if (localId is int && remoteId is String) {
        await DatabaseHelper.instance.setStaffRemoteId(localId, remoteId);
      }
    }
  }

  /// Initiate M-Pesa STK push payment
  static Future<String> initiatePayment({
    required List<Map<String, dynamic>> items,
    required String phoneNumber,
    required String staffName,
    String? customerName,
    String? staffProfileId,
  }) async {
    await ensureInitialized();

    final result = await _dio.post('$backendUrl/payments/initiate', data: {
      'items': items,
      'phone_number': phoneNumber,
      'staff_name': staffName,
      if (staffProfileId != null) 'staff_profile_id': staffProfileId,
      if (customerName != null) 'customer_name': customerName,
    });

    final reference = result.data['reference'];
    if (reference == null) {
      throw StateError('No payment reference returned');
    }

    return reference as String;
  }

  /// Poll payment status until resolved or timeout
  static Future<PaymentOutcome> pollPaymentStatus(
    String reference, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await ensureInitialized();
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final result = await _dio.get(
          '$backendUrl/payments/status',
          queryParameters: {'reference': reference},
        );

        final status = result.data['status'];
        if (status == 'SUCCESS') return PaymentOutcome.success;
        if (status == 'FAILED') return PaymentOutcome.failed;

        await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        // Continue polling on network errors
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    return PaymentOutcome.timedOut;
  }
}

enum PaymentOutcome { success, failed, timedOut }
