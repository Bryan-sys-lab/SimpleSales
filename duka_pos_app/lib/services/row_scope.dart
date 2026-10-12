// Row-level security for a till that talks to more than one shop.
//
// ## What "row-level" means here
//
// This app is not a database with many tenants in one file — each shop on the
// device is its OWN SQLite file, and that is the first and best isolation. But
// every row that LEAVES the device carries a `remote_id`, and a `remote_id` is
// minted by the server inside the namespace of one tenant.
//
// So a row does not merely have an id; it has a scope it was created under, and
// it may only ever be written back under that same scope. Change the tenant a
// shop is bound to — unlink, relink, delete the account, restore a backup onto
// a different phone — and every `remote_id` already in the file was minted
// inside the OLD tenant's namespace. Re-sending those ids to the new tenant is
// a cross-tenant write: the server resolves a foreign row as if it were ours,
// which is either a silent overwrite of another shop's data or a leak of ours.
//
// ## Why this is a rule and not a check at each call site
//
// The blast radius of getting it wrong is another shop's ledger, so the rule is
// stated once, in one place, and every outbound write goes through it. A caller
// cannot "forget" to scope a payload it posts.
//
// ## The invalidation, not the guess
//
// The rule is INVALIDATE, not GUESS. A row whose scope no longer matches is not
// reconciled, not re-minted optimistically, and not sent: its cached `remote_id`
// is cleared, and the next sync lets the server mint a fresh one under the
// tenant the shop is actually bound to now.

import 'workspace_service.dart';

/// Why a row could not be written.
///
/// Named rather than a bare string, because the caller has to say something
/// honest to the shop and "sync failed" would send an owner looking for a
/// network problem that does not exist.
enum RowScopeFailure {
  /// This shop is not linked to any tenant, so it has nothing to write under.
  notLinked,

  /// The row was minted under a tenant other than the one this shop is bound
  /// to now. Writing it would be a cross-tenant write.
  foreignScope,

  /// The shop's own binding could not be read.
  unknown,
}

/// Thrown when a row would be written outside its scope.
class RowScopeException implements Exception {
  const RowScopeException(this.failure, [this.detail]);

  final RowScopeFailure failure;

  /// The workspace or tenant that refused the write, for a log line.
  final String? detail;

  @override
  String toString() =>
      'RowScopeException($failure${detail == null ? '' : ': $detail'})';
}

/// The identity a row may travel under.
///
/// Two fields, because either alone is not an identity: a workspace with no
/// tenant is an unlinked shop, and a tenant with no workspace is another shop's
/// tenant. Both have to match for a write to be in scope.
class RowScope {
  const RowScope({required this.workspaceKey, required this.tenantId});

  /// The shop on this device.
  final String workspaceKey;

  /// The tenant that shop is bound to on the server.
  final String tenantId;

  /// The scope for the shop that is active right now, or null when it has no
  /// tenant.
  ///
  /// Null is a real answer, not an error: an unlinked shop has nothing to write
  /// under and should send nothing rather than picking a neighbour's tenant.
  static Future<RowScope?> current() async {
    final tenantId = await WorkspaceService.activeTenantId();
    if (tenantId == null || tenantId.isEmpty) return null;
    return RowScope(
      workspaceKey: await WorkspaceService.activeWorkspaceKey(),
      tenantId: tenantId,
    );
  }

  /// Whether the two scopes name the same shop on the same tenant.
  ///
  /// Equality of BOTH fields. One field matching is how a tenant adopted from
  /// another shop passes a check it should not.
  bool covers(RowScope? other) =>
      other != null &&
      other.tenantId == tenantId &&
      other.workspaceKey == workspaceKey;

  @override
  String toString() => 'RowScope($workspaceKey -> $tenantId)';
}

/// Asserts that a row minted under [origin] may be written under [current].
///
/// Throws [RowScopeException] with `foreignScope` when it may not, which is the
/// caller's cue to invalidate the row's cached id rather than to retry.
void assertRowInScope({
  required RowScope? current,
  required RowScope? origin,
}) {
  if (current == null) {
    throw const RowScopeException(RowScopeFailure.notLinked);
  }
  if (!current.covers(origin)) {
    throw RowScopeException(RowScopeFailure.foreignScope, '$origin');
  }
}
