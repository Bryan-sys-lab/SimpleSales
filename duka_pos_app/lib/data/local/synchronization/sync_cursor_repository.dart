/// Tracks the sync cursor (last processed position) per aggregate type.
///
/// The cursor lets the synchronizer resume from where it left off after a
/// restart or network interruption, without re-sending already-acknowledged
/// events.
class SyncCursorRepository {
  SyncCursorRepository._();
  static final SyncCursorRepository instance = SyncCursorRepository._();

  /// Reads the cursor for [aggregateType].
  Future<String?> readCursor(String aggregateType) async {
    // Stub: backed by shop_settings keyed by 'sync_cursor_$aggregateType'
    return null;
  }

  /// Writes the cursor for [aggregateType].
  Future<void> writeCursor(String aggregateType, String cursor) async {
    // Stub: write to shop_settings
  }
}
