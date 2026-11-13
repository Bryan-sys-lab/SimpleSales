// Diagnostics upload: sends the phone's failure log to the backend so a
// system admin can see what broke, on what phone, under what conditions.
//
// The upload is best-effort: a failed upload never stops a till from selling,
// and the local copy remains on the phone until the owner clears it.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/crash_log.dart';
import 'backend_service.dart';

/// A single failure entry packaged for upload.
class CrashEntryPayload {
  const CrashEntryPayload({
    required this.kind,
    required this.message,
    this.stack,
    this.route,
    this.actorName,
    this.action,
    this.breadcrumbs = const <String>[],
    this.createdAt,
  });

  final String kind;
  final String message;
  final String? stack;
  final String? route;
  final String? actorName;
  final String? action;
  final List<String> breadcrumbs;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'message': message,
        if (stack != null) 'stack': stack,
        if (route != null) 'route': route,
        if (actorName != null) 'actorName': actorName,
        if (action != null) 'action': action,
        if (breadcrumbs.isNotEmpty) 'breadcrumbs': breadcrumbs,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };
}

/// A complete device diagnostic report packaged for upload.
class DeviceDiagnosticPayload {
  const DeviceDiagnosticPayload({
    required this.deviceId,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.locale,
    this.manufacturer,
    this.model,
    this.tenantId,
    required this.crashes,
  });

  final String deviceId;
  final String platform;
  final String osVersion;
  final String appVersion;
  final String buildNumber;
  final String locale;
  final String? manufacturer;
  final String? model;
  final String? tenantId;
  final List<CrashEntryPayload> crashes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'platform': platform,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'locale': locale,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (tenantId != null) 'tenantId': tenantId,
        'crashes': crashes.map((c) => c.toJson()).toList(),
      };
}

/// Result of an upload attempt.
class DiagnosticUploadResult {
  const DiagnosticUploadResult._({
    required this.ok,
    this.serverId,
    this.errors,
  });

  factory DiagnosticUploadResult.ok(String serverId) =>
      DiagnosticUploadResult._(ok: true, serverId: serverId);

  factory DiagnosticUploadResult.failed(List<Object> errors) =>
      DiagnosticUploadResult._(ok: false, errors: errors);

  final bool ok;
  final String? serverId;
  final List<Object>? errors;
}

/// Collects device identity and failure logs, and uploads them to the
// backend's /api/admin/diagnostics endpoint.
class DiagnosticsUploadService {
  DiagnosticsUploadService._();
  static final DiagnosticsUploadService instance = DiagnosticsUploadService._();

  final Dio _dio = Dio();

  /// A stable device id, read from storage once and regenerated on first use.
  static const _deviceIdKey = 'diagnostic_device_id';

  /// The backend path device diagnostics are posted to.
  static const _uploadPath = '/api/admin/diagnostics';

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = String.fromEnvironment('DEVICE_ID',
        defaultValue: '${Platform.localHostname}-${DateTime.now().millisecondsSinceEpoch}');
    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }

  /// The tenant id linked to this device, if any.
  Future<String?> _tenantId() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'workspace',
        columns: ['tenant_id'],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['tenant_id'] as String?;
    } catch (_) {
      // Workspace table may not exist yet.
    }
    return null;
  }

  /// Gather everything the backend needs: device identity, build facts, and
  /// the local failure log.
  Future<DeviceDiagnosticPayload> buildReport() async {
    final deviceId = await _deviceId();
    final tenantId = await _tenantId();

    final info = await PackageInfo.fromPlatform();

    return DeviceDiagnosticPayload(
      deviceId: deviceId,
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      appVersion: info.version,
      buildNumber: info.buildNumber,
      locale: Platform.localeName,
      manufacturer: null,
      model: Platform.localHostname,
      tenantId: tenantId,
      crashes: await _crashEntries(),
    );
  }

  /// Reads the local failure log and maps it to upload payloads.
  Future<List<CrashEntryPayload>> _crashEntries() async {
    final entries = await DatabaseHelper.instance
        .crashLog(const CrashLogQuery(limit: 200));
    return entries.map((e) => CrashEntryPayload(
      kind: e.kind.wire,
      message: e.message,
      stack: e.stack,
      route: e.route,
      actorName: e.actorName,
      action: e.action,
      breadcrumbs: e.breadcrumbs,
      createdAt: e.at.isNotEmpty ? DateTime.tryParse(e.at) : null,
    )).toList();
  }

  /// POST the report to the backend. Best-effort: failures are swallowed and
  /// reported as a failed result, never thrown.
  Future<DiagnosticUploadResult> upload() async {
    try {
      final report = await buildReport();
      final base = BackendService.backendUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await _dio.post(
        '$base$_uploadPath',
        data: report.toJson(),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>?;
        return DiagnosticUploadResult.ok(data?['id'] as String? ?? '');
      }
      return DiagnosticUploadResult.failed([
        'HTTP ${response.statusCode}',
      ]);
    } on DioException catch (e) {
      return DiagnosticUploadResult.failed([
        'Network: ${e.message}',
      ]);
    } on Object catch (e) {
      return DiagnosticUploadResult.failed([
        e.toString(),
      ]);
    }
  }

  /// Upload and, if successful, clear the local log so the phone does not
  /// keep re-sending the same failures.
  Future<DiagnosticUploadResult> uploadAndClear() async {
    final result = await upload();
    if (result.ok) {
      try {
        await DatabaseHelper.instance.clearCrashLog();
      } catch (_) {
        // Clearing is best-effort too; the server already has the data.
      }
    }
    return result;
  }
}
