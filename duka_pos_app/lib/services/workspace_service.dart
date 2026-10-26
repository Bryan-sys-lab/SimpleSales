import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// [WorkspaceService.legacyKey] under another name, for a test that asserts
  /// a shop filed under the legacy key stays filed there.
  ///
  /// Exposed because the constant is the value the DATABASE FILENAME is derived
  /// from: a change to it silently moves every legacy shop's ledger to a new
  /// empty file. A test asserting the literal value is the only thing that
  /// catches that.
  static const legacyKeyForTests = legacyKey;

  /// [registryKey], for a test that needs to write the registry directly.
  static const registryKeyForTests = registryKey;

  /// The registry, for assertions.
  ///
  /// Same data [registry] returns; named separately so a test's intent is
  /// legible at the call site.
  static Future<Map<String, Map<String, String>>> registryForTests() =>
      registry();

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
      required String shopName,
      bool legacyTenantSeen = false}) async {
    final current = await registry();
    current[workspaceKey] = {
      'shopName': shopName,
      // Written as '0' rather than omitted so an existing key is overwritten
      // rather than left behind: the adoption marker must be able to be cleared.
      if (legacyTenantSeen) _legacyAdoptedKey: '1',
      if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(registryKey, jsonEncode(current));
  }

  /// Removes a workspace registry entry after a failed, not-yet-completed
  /// shop creation. This is intentionally explicit rather than a generic
  /// "clear registry" operation so an error cannot erase another shop.
  static Future<void> unregister(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty || workspaceKey == legacyKey) return;
    final current = await registry();
    if (!current.containsKey(workspaceKey)) return;
    current.remove(workspaceKey);
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

  /// The tenant this device should be posting for, given the shop in use.
  ///
  /// The ACTIVE tenant is derived from the active workspace rather than kept in
  /// a second key: a single global `tenant_id` was written by whichever shop
  /// verified last and then posted from every shop on the device. With two shops
  /// on one phone, the second shop's syncs, staff calls and analytics were sent
  /// under the first shop's tenant id — cross-shop data mixing the server
  /// resolves in the caller's favour, so it is both a privacy and a correctness
  /// fault.
  ///
  /// Returns null when the active shop has no tenant, which is the honest
  /// answer: an unlinked shop has nothing to post under, and silently falling
  /// back to another shop's tenant would be the bug this replaces.
  static Future<String?> activeTenantId() async {
    final active = await activeWorkspaceKey();
    final all = await registry();
    final entry = all[active];
    final tenantId = entry?['tenantId'];
    if (tenantId != null && tenantId.isNotEmpty) return tenantId;
    return _adoptLegacyTenant(active, all);
  }

  /// One-time adoption of the pre-per-workspace global `tenant_id`.
  ///
  /// Moving the active tenant from a global preference into the registry is
  /// correct — see the note on [activeTenantId] — but it would have left every
  /// install that had linked before the change reading "no tenant": the
  /// registry entry for such a shop holds only `shopName`, because
  /// `owner_setup_screen` registered it that way and the tenant was written to
  /// the global key by `linkShopToBackend`. Every guarded backend call then
  /// silently no-ops (`if (await tenantId == null) return;`), so the shop looks
  /// unlinked to the owner and to anyone reading the logs, with nothing wrong
  /// on the server.
  ///
  /// So the global value is adopted once, for the shop that is active at the
  /// time, and only until it has been. It is not read again afterwards, which
  /// keeps the cross-shop fix intact: an adopted tenant belongs to exactly one
  /// workspace from then on.
  ///
  /// Returns null when there is nothing to adopt — a genuinely unlinked shop,
  /// which is the honest answer rather than a silent fallback.
  static Future<String?> _adoptLegacyTenant(
      String active, Map<String, Map<String, String>> all) async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_legacyTenantKey);
    if (legacy == null || legacy.isEmpty) return null;
    if (all.containsKey(active) &&
        all[active]!.containsKey(_legacyAdoptedKey)) {
      // Already adopted for this shop: the legacy key is stale now.
      await prefs.remove(_legacyTenantKey);
      return null;
    }
    await register(
      workspaceKey: active,
      shopName: all[active]?['shopName'] ?? 'Shop',
      tenantId: legacy,
      legacyTenantSeen: true,
    );
    await prefs.remove(_legacyTenantKey);
    return legacy;
  }

  /// The single global key the active tenant used to live under.
  ///
  /// Read once per install by [_adoptLegacyTenant], then removed.
  static const _legacyTenantKey = 'tenant_id';

  /// Registry marker recording that this shop already adopted the legacy
  /// tenant, so the adoption runs exactly once rather than on every read.
  static const _legacyAdoptedKey = 'legacyTenantSeen';

  /// The active shop's name, or null when it holds none.
  ///
  /// Needed by the caller that writes a tenant back into the registry, because
  /// [register] takes the fields it already has rather than inventing a name for
  /// the shop being linked.
  static Future<String?> activeShopName() async {
    final all = await registry();
    return all[await activeWorkspaceKey()]?['shopName'];
  }
}

/// One shop that lives on this device.
///
/// The shop switcher used to build its list from the BACKEND's `/tenant/shops`,
/// which meant a shop added on this device without a tenant link could never be
/// switched to — the shop existed, its database existed, and the one screen
/// supposed to change between them could not see it. The local registry is the
/// only authority on which shops are HERE, so it is what the switcher reads;
/// the backend still contributes the role and the online state where it has
/// them, but it is never the reason a shop is missing from the list.
@immutable
class LocalShop {
  const LocalShop({
    required this.workspaceKey,
    required this.shopName,
    this.tenantId,
  });

  final String workspaceKey;
  final String shopName;
  final String? tenantId;

  /// Whether this shop has been linked to the backend. Not whether it is
  /// reachable right now: a linked shop that is offline is still linked.
  bool get isBackendLinked => tenantId != null && tenantId!.isNotEmpty;
}

/// Extension so [WorkspaceService] can be read as a single object with the
/// registry helpers on it, while the model stays a plain value type.
extension WorkspaceServiceShops on WorkspaceService {
  /// Every shop registered on this device, in the order a person expects: the
  /// original shop first, then the rest alphabetically.
  ///
  /// The registry is keyed by workspace key, so a shop whose name was later
  /// edited on the backend keeps its local entry — the name shown here is the
  /// one recorded when the shop was created on this device, which is the name
  /// the owner typed.
  static Future<List<LocalShop>> localShops() async {
    final all = await WorkspaceService.registry();
    final shops = all.entries.map((entry) {
      final name = entry.value['shopName'] ?? '';
      return LocalShop(
        workspaceKey: entry.key,
        // A blank name renders as a placeholder rather than an empty row: the
        // key is what identifies the shop, and the row has to say something.
        shopName: name.isEmpty ? 'Unnamed shop' : name,
        tenantId: entry.value['tenantId'],
      );
    }).toList();
    shops.sort((a, b) {
      if (a.workspaceKey == WorkspaceService.legacyKey) return -1;
      if (b.workspaceKey == WorkspaceService.legacyKey) return 1;
      return a.shopName.compareTo(b.shopName);
    });
    return shops;
  }
}
