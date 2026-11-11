/// The current schema version. New schema changes start at version 81.
///
/// All released migrations (v1–v80) are immutable historical code. A new
/// migration is always added as a new version — never edited after shipping —
/// because a shop's phone may be several versions behind and needs every step
/// run in order to land on the current schema without data loss.
class SchemaVersion {
  SchemaVersion._();

  /// Current production schema version.
  static const int current = 80;

  /// First version managed by the new migration registry.
  ///
  /// Versions 1–80 remain under the historical migration path in
  /// [DatabaseHelper]. Version 81+ uses the new [Migration] registry.
  static const int firstRegistryManaged = 81;
}
