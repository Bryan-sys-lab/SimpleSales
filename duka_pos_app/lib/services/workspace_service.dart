import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local shop registry. Each workspace has its own SQLite file, so an offline
/// sale can never leak into another shop's ledger. Encrypted backups remain a
/// separate opt-in protection; SQLite-at-rest encryption requires SQLCipher.
class WorkspaceService {
  static const activeKey = 'active_workspace_key';
  static const registryKey = 'workspace_registry_v1';
  static const legacyKey = 'legacy';

  static Future<String> activeWorkspaceKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(activeKey) ?? legacyKey;
  }

  static Future<void> setActiveWorkspace(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeKey, key);
  }

  static Future<Map<String, Map<String, String>>> registry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(registryKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return decoded.map((key, value) => MapEntry(
          key.toString(),
          value is Map
              ? value.map((k, v) => MapEntry(k.toString(), v.toString()))
              : <String, String>{},
        ));
  }

  static Future<void> register(
      {required String workspaceKey,
      String? tenantId,
      required String shopName}) async {
    final current = await registry();
    current[workspaceKey] = {
      'shopName': shopName,
      if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(registryKey, jsonEncode(current));
  }

  static Future<String?> workspaceForTenant(String tenantId) async {
    final all = await registry();
    for (final entry in all.entries) {
      if (entry.value['tenantId'] == tenantId) return entry.key;
    }
    return null;
  }
}
