import 'package:shared_preferences/shared_preferences.dart';
import 'sheets_service.dart';
import 'excel_service.dart';

enum SyncResult { pushedToSheets, savedExcelOnly, failed }

/// This is the "hybrid" decision point: try Google Sheets first since it's
/// the more convenient path when there's signal; if that fails for any
/// reason (no internet, not signed in, API error), fall back to writing the
/// Excel file locally so the owner still has a fresh export ready to share
/// manually. The app never blocks on connectivity — every sync action
/// completes one way or the other.
class SyncService {
  final _sheets = SheetsService();
  final _excel = ExcelService();

  Future<String?> get _spreadsheetId async =>
      (await SharedPreferences.getInstance()).getString('spreadsheet_id');

  Future<void> _saveSpreadsheetId(String id) async =>
      (await SharedPreferences.getInstance()).setString('spreadsheet_id', id);

  /// High-water mark for the Google Sheets sales export.
  ///
  /// Without this, `appendSales(after: null)` re-appends the shop's entire
  /// sales ledger on every manual sync, silently inflating revenue in the
  /// owner's spreadsheet.
  static const _salesWatermarkKey = 'sales_sheet_watermark';

  Future<DateTime?> get _salesWatermark async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_salesWatermarkKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _saveSalesWatermark(DateTime value) async =>
      (await SharedPreferences.getInstance())
          .setString(_salesWatermarkKey, value.toIso8601String());

  Future<bool> get isGoogleLinked async => _sheets.currentUser != null;

  Future<SyncResult> syncInventory(String shopName) async {
    try {
      final linked = _sheets.currentUser ?? await _sheets.signIn();
      if (linked == null) return await _excelFallbackInventory();
      final id =
          await _sheets.ensureSpreadsheet(await _spreadsheetId, shopName);
      await _saveSpreadsheetId(id);
      await _sheets.pushInventory(id);
      return SyncResult.pushedToSheets;
    } catch (_) {
      return _excelFallbackInventory();
    }
  }

  Future<SyncResult> syncSales(String shopName, {DateTime? since}) async {
    // Default `since` to the last successful export so repeated syncs append
    // only new sales instead of duplicating the whole ledger.
    final effectiveSince = since ?? await _salesWatermark;
    try {
      final linked = _sheets.currentUser ?? await _sheets.signIn();
      if (linked == null) return await _excelFallbackSales(effectiveSince);
      final id =
          await _sheets.ensureSpreadsheet(await _spreadsheetId, shopName);
      await _saveSpreadsheetId(id);
      // Advance the watermark to the newest sale the sheet now provably
      // contains. Stamping `DateTime.now()` instead would jump the mark past
      // any sale committed while the append was in flight, and because the
      // mark only moves forward those sales would never be exported.
      final newestExported =
          await _sheets.appendSales(id, after: effectiveSince);
      if (newestExported != null) await _saveSalesWatermark(newestExported);
      return SyncResult.pushedToSheets;
    } catch (_) {
      return _excelFallbackSales(effectiveSince);
    }
  }

  Future<SyncResult> _excelFallbackInventory() async {
    try {
      final file = await _excel.exportEncryptedInventory();
      await _excel.shareFile(file);
      return SyncResult.savedExcelOnly;
    } catch (_) {
      return SyncResult.failed;
    }
  }

  Future<SyncResult> _excelFallbackSales(DateTime? since) async {
    try {
      final file = await _excel.exportEncryptedSales(since: since);
      await _excel.shareFile(file);
      return SyncResult.savedExcelOnly;
    } catch (_) {
      return SyncResult.failed;
    }
  }
}
