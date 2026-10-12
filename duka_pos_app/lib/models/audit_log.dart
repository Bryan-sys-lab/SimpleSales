/// The actions an audit row records.
///
/// A closed enum rather than free strings: a log whose vocabulary drifts into
/// "product_edited" in one call site and "productEdit" in another is a log that
/// cannot be queried, and the admin dashboard reads this by value.
///
/// Every member is a single event with a single actor and a single subject.
enum AuditAction {
  productCreated('product_created'),
  productUpdated('product_updated'),
  productVariantAdded('product_variant_added'),
  productVariantUpdated('product_variant_updated'),
  productVariantRemoved('product_variant_removed'),
  barcodeAdded('barcode_added'),
  barcodeRemoved('barcode_removed'),
  barcodeKindChanged('barcode_kind_changed'),
  stockAdjusted('stock_adjusted'),
  saleRecorded('sale_recorded'),
  shotCupSold('shot_cup_sold'),
  staffAdded('staff_added'),
  staffRemoved('staff_removed'),
  staffPinReset('staff_pin_reset'),
  paymentMethodChanged('payment_method_changed'),
  printerPaired('printer_paired'),
  printerSaved('printer_saved'),
  taxSettingsChanged('tax_settings_changed'),
  syncSettingsChanged('sync_settings_changed'),
  backupExported('backup_exported'),
  backupRestored('backup_restored'),
  backupErased('backup_erased'),
  shopSwitched('shop_switched'),
  shopCreated('shop_created'),
  shiftOpened('shift_opened'),
  shiftClosed('shift_closed'),
  identityLinked('identity_linked'),
  ownerPinReset('owner_pin_reset'),
  accountDeleted('account_deleted');

  const AuditAction(this.wire);

  /// The stored value. Snake case so the row reads the same in SQLite as it
  /// does in the admin dashboard's JSON.
  final String wire;

  /// Falls back to a product update for a row this build does not define.
  ///
  /// A row written by a NEWER version of the app and read by an older one would
  /// otherwise throw inside `firstWhere`, and taking the whole activity screen
  /// down because a field released a version late is worse than showing the
  /// wrong label on one row.
  static AuditAction fromWire(String? value) =>
      values.firstWhere((a) => a.wire == value, orElse: () => productUpdated);
}

/// What an action was done to.
///
/// Paired with [AuditAction.entityId] — the pair is what makes "everything that
/// touched this product" a single query rather than a scan.
enum AuditEntity {
  product('product'),
  variant('variant'),
  barcode('barcode'),
  staff('staff'),
  sale('sale'),
  settings('settings'),
  backup('backup'),
  workspace('workspace'),
  shift('shift'),
  identity('identity'),

  /// The owner account itself, as distinct from the person's session.
  ///
  /// A PIN reset is a change to the ACCOUNT rather than to a setting, and the
  /// two answer different questions from an auditor.
  owner('owner'),

  /// The online account, whose deletion the shop initiated.
  account('account');

  const AuditEntity(this.wire);

  final String wire;

  /// Falls back to settings for a row this build does not define.
  static AuditEntity fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => settings);
}

/// One state-changing thing someone did in this shop.
///
/// ### Why this exists alongside `stock_adjustments` and `sales`
///
/// Those tables answer "what happened to the stock" and "what was sold". Neither
/// answers "who changed the VAT rate", "which cashier removed a barcode", or
/// "was this backup erased by the owner or by staff" — and those are the
/// questions a shop asks when the numbers stop adding up. A sale is a fact about
/// the ledger; an audit row is a fact about the person.
///
/// ### Why the actor is denormalised
///
/// `deleteStaffWithTombstone` scrubs the staff table by `staff_id`, and the
/// ledger keeps only the tombstone. A row that resolved its actor through a join
/// would render "deleted user" on every action a removed cashier took, which is
/// both useless for reconstruction and a leak: the display name is already on the
/// sale. So the name is stored here, once, at write time.
class AuditLogEntry {
  const AuditLogEntry({
    this.id,
    required this.action,
    required this.entity,
    required this.actorName,
    this.entityId,
    this.actorId,
    this.detail,
    required this.createdAt,
  });

  final int? id;

  final AuditAction action;

  final AuditEntity entity;

  /// Null for an action on something with no stable id — a settings change has
  /// no "which setting" id worth recording, because the detail carries it.
  final String? entityId;

  /// Null for the owner. See the class doc: tying a row to a row that may be
  /// scrubbed would leak the name the tombstone exists to remove.
  final int? actorId;

  final String actorName;

  /// The before/after or the reason, already rendered as a sentence.
  ///
  /// Localised by the caller at write time — the log is read by an admin who
  /// may not read the shop's locale, so it is stored as plain text rather than
  /// keyed, and a controller can render whatever it wants on the way out.
  final String? detail;

  final String createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'action': action.wire,
        'entity': entity.wire,
        'entity_id': entityId,
        'actor_id': actorId,
        'actor_name': actorName,
        'detail': detail,
        'created_at': createdAt,
      };

  factory AuditLogEntry.fromMap(Map<String, dynamic> m) => AuditLogEntry(
        id: m['id'],
        action: AuditAction.fromWire(m['action']),
        entity: AuditEntity.fromWire(m['entity']),
        entityId: m['entity_id'],
        actorId: m['actor_id'],
        actorName: m['actor_name'] ?? '',
        detail: m['detail'],
        createdAt: m['created_at'],
      );

  AuditLogEntry copyWith({int? id, String? entityId}) => AuditLogEntry(
        id: id ?? this.id,
        action: action,
        entity: entity,
        entityId: entityId ?? this.entityId,
        actorId: actorId,
        actorName: actorName,
        detail: detail,
        createdAt: createdAt,
      );
}

/// A filter for reading the log.
///
/// [limit] defaults to 200 and is capped higher by the caller, not here: this is
/// the shape of a query, not a policy about how much of the log to load.
class AuditLogQuery {
  const AuditLogQuery({
    this.entity,
    this.entityId,
    this.actorId,
    this.actions,
    this.since,
    this.limit = 200,
  });

  final AuditEntity? entity;
  final String? entityId;
  final int? actorId;
  final List<AuditAction>? actions;

  /// Inclusive lower bound, ISO-8601. Null means "from the start", which is
  /// only safe because the index orders newest-first.
  final String? since;

  final int limit;
}
