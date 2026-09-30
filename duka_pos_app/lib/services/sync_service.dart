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
    try {
      final linked = _sheets.currentUser ?? await _sheets.signIn();
      if (linked == null) return await _excelFallbackSales(since);
      final id =
          await _sheets.ensureSpreadsheet(await _spreadsheetId, shopName);
      await _saveSpreadsheetId(id);
      await _sheets.appendSales(id, since: since);
      return SyncResult.pushedToSheets;
    } catch (_) {
      return _excelFallbackSales(since);
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
