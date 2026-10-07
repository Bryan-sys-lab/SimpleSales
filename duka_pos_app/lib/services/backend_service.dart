import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import 'etims/etims_service.dart';
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
        data: {'mpesaEnabled': true, 'paymentChannelId': channelId});
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
      if (channelId != null) 'paymentChannelId': channelId,
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

  // ---------------- eTIMS ----------------

  /// Asks the backend to issue a KRA receipt for one sale.
  ///
  /// Called from the pending queue rather than from the checkout path, and that
  /// placement is the whole design: the customer has already paid and the sale
  /// is already committed, so a KRA outage here delays an invoice and nothing
  /// else. Issuing inline would mean an unreachable tax authority can stop a
  /// shop taking money.
  ///
  /// Amounts go over the wire as integer minor units, matching how they are
  /// stored. The backend contract predates the move to minor units and speaks
  /// major units for catalogue prices, so every figure here is converted
  /// explicitly rather than relying on the wire shape — sending a `Money`
  /// object would serialise as the text "Money(4050 minor units)".
  static Future<EtimsIssueResult> issueEtimsReceipt(
    Map<String, dynamic> payload, {
    String? deviceId,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) {
      // Not linked. This is a configuration problem, not a transient one, so
      // it is surfaced as permanent and the till stops retrying it.
      throw const EtimsRejectedException(
          'This shop is not linked to the backend, so receipts cannot be issued.');
    }

    final response = await _dio.post(
      '$backendUrl/etims/receipts',
      data: {...payload, if (deviceId != null) 'device_id': deviceId},
    );
    final data = response.data as Map<String, dynamic>? ?? const {};
    final receiptNumber = data['kra_receipt_number'];
    if (receiptNumber is! String || receiptNumber.trim().isEmpty) {
      throw StateError('The backend returned no KRA receipt number');
    }
    return EtimsIssueResult(
      kraReceiptNumber: receiptNumber.trim(),
      verificationUrl: data['verification_url'] as String?,
      qrPayload: data['qr_payload'] as String?,
      status: data['status'] as String?,
    );
  }

  /// How many receipts are still waiting to be issued.
  static Future<EtimsQueueStatus> getEtimsQueueStatus() async {
    await ensureInitialized();
    final response = await _dio.get('$backendUrl/etims/status');
    final data = response.data as Map<String, dynamic>? ?? const {};
    return EtimsQueueStatus(
      configured: data['configured'] == true,
      pending: (data['pending_upload'] as num?)?.toInt() ?? 0,
      rejected: (data['rejected'] as num?)?.toInt() ?? 0,
      deviceStatus: data['device_status'] as String?,
      tin: data['tin'] as String?,
    );
  }

  /// The Z-report for a day, as KRA requires it at close of trade.
  ///
  /// Generated server-side because it has to reconcile against the receipts
  /// KRA has actually accepted, which the till cannot know.
  static Future<Map<String, dynamic>> getEtimsZReport({
    DateTime? date,
  }) async {
    await ensureInitialized();
    final response =
        await _dio.get('$backendUrl/etims/z-report', queryParameters: {
      if (date != null) 'date': _isoDate(date),
    });
    return (response.data as Map<String, dynamic>?) ?? const {};
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Pushes the till's TIN and device registration to the backend.
  ///
  /// The TIN is legally significant and is never accepted from a client without
  /// the backend confirming it against KRA's registration.
  static Future<void> registerEtimsDevice({
    required String tin,
    required String deviceId,
    String? deviceName,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) throw StateError('Shop is not linked to backend');
    await _dio.post('$backendUrl/etims/device', data: {
      'tin': tin,
      'device_id': deviceId,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
    });
  }

  /// Pushes a stock correction to the backend.
  ///
  /// `/products/sync` no longer carries `stockQty` for existing rows because
  /// the server is the authority there, so this is how a break, a delivery or a
  /// count reaches it. Best effort: the local ledger is already updated, and a
  /// failed push is surfaced rather than silently dropped.
  static Future<bool> adjustStockOnBackend({
    required Product product,
    required int delta,
    String? reason,
    String? staffProfileId,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return false;
    final remoteId = product.remoteId;
    if (remoteId == null) return false;
    try {
      await _dio.post('$backendUrl/products/stock-adjust', data: {
        'product_id': remoteId,
        'delta': delta,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (staffProfileId != null) 'staff_profile_id': staffProfileId,
      });
      return true;
    } on DioException {
      return false;
    }
  }

  /// Syncs one product to the backend immediately after it is edited.
  ///
  /// The bulk path runs on the auto-sync timer, so a price or name change is
  /// invisible to the backend for up to six hours — long enough for the shop to
  /// sell at a stale price. Pushing the single edited row keeps the catalogue
  /// current without re-sending the whole inventory.
  static Future<void> syncProductToBackend(Product product) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return;
    if (product.id == null) return;

    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': [
        {
          'id': product.id,
          'remoteId': product.remoteId,
          'name': product.name,
          'category': product.category,
          // Major units on the wire: the backend contract predates the move to
          // integer cents and is expressed in shillings. Sending a Money object
          // here would serialise as "Money(4050 minor units)".
          'costPrice': product.costPrice.asMajor,
          'sellPrice': product.sellPrice.asMajor,
          'stockQty': product.stockQty,
          'reorderLevel': product.reorderLevel,
          'bottleMl': product.bottleMl,
          'halfPrice': product.halfPrice?.asMajor,
          'quarterPrice': product.quarterPrice?.asMajor,
          'exciseStampBatch': product.exciseStampBatch,
          'active': product.active,
        }
      ],
    });

    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    for (final item in synced) {
      final remoteId = item['remoteId'];
      // A newly created product has no remote id until the server assigns one.
      if (remoteId is String && remoteId.isNotEmpty) {
        await DatabaseHelper.instance.setProductRemoteId(product.id!, remoteId);
      }
    }
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
                'costPrice': p.costPrice.asMajor,
                'sellPrice': p.sellPrice.asMajor,
                'stockQty': p.stockQty,
                'reorderLevel': p.reorderLevel,
                'bottleMl': p.bottleMl,
                'halfPrice': p.halfPrice?.asMajor,
                'quarterPrice': p.quarterPrice?.asMajor,
                'exciseStampBatch': p.exciseStampBatch,
                'active': p.active,
              })
          .toList(),
    });

    // Update local DB with remote IDs in one transaction. This ran on the
    // 5-minute auto-sync path, so a per-row write meant one implicit
    // transaction and one fsync per product on every cycle.
    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    final pairs = <int, String>{};
    for (final item in synced) {
      final localId = item['localId'];
      final remoteId = item['remoteId'];
      if (localId is int && remoteId is String && remoteId.isNotEmpty) {
        pairs[localId] = remoteId;
      }
    }
    if (pairs.isNotEmpty) {
      await DatabaseHelper.instance.setProductRemoteIds(pairs);
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

/// What the backend returned for an issued tax receipt.
class EtimsIssueResult {
  const EtimsIssueResult({
    required this.kraReceiptNumber,
    this.verificationUrl,
    this.qrPayload,
    this.status,
  });

  /// KRA's own receipt number. This is the number an auditor asks for, and it
  /// is *not* the till's own `receipt_number` — the two are deliberately
  /// independent so a KRA-side gap cannot renumber what the customer was
  /// already handed.
  final String kraReceiptNumber;

  /// The page a customer scans to verify the receipt against KRA.
  final String? verificationUrl;

  /// The exact string encoded in the receipt's QR code.
  ///
  /// Preferred over [verificationUrl] for the QR because KRA's verification
  /// page expects specific parameters; encoding a URL built locally is how a
  /// receipt ends up with a QR that scans to a 404.
  final String? qrPayload;

  final String? status;
}

/// The shop's eTIMS posture, for the settings screen.
class EtimsQueueStatus {
  const EtimsQueueStatus({
    required this.configured,
    required this.pending,
    required this.rejected,
    this.deviceStatus,
    this.tin,
  });

  /// Whether the shop has a TIN and a registered device, without which no
  /// receipt can be issued at all.
  final bool configured;

  final int pending;
  final int rejected;
  final String? deviceStatus;
  final String? tin;
}
