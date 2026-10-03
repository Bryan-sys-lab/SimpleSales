import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import 'encrypted_backup_service.dart';

const _lastBackupKey = 'last_backup_at';

/// How the reminder banner (see BackupReminder below) decides "overdue."
/// Kept short deliberately — a shop with real daily sales volume that goes
/// two days without a backup is one bad afternoon away from losing real data.
const backupReminderThreshold = Duration(hours: 30);

/// The fully-offline half of the hybrid sync. Writes a real .xlsx file (not
/// just CSV) so it opens correctly in both Excel and Google Sheets' own
/// "Import" dialog — this is how sync happens when there's no internet: the
/// owner exports, transfers the file by USB/WhatsApp/SD card, and imports it
/// on the other device or uploads it to Sheets manually later.
/// Marker for the automatic backup job; kept trivial so it is cheap to send
/// between the scheduler and this function.
class InventoryBackupRequest {
  const InventoryBackupRequest();
}

/// Builds and writes an encrypted inventory snapshot, returning the file path.
///
/// This must run on the **main** isolate. Reading the catalogue needs sqflite
/// and writing the file needs path_provider, and neither plugin is registered
/// inside a `compute` isolate — dispatching this function wholesale threw on
/// every run and the caller's `catch` swallowed it, so automatic backups
/// silently stopped happening. The genuinely CPU-bound part (AES-GCM over the
/// workbook) is dispatched separately by [EncryptedBackupService.encryptToFile],
/// so the expensive work still leaves the frame loop.
///
/// This is the scheduler-facing entry point and is a thin delegate:
/// [ExcelService.saveAutomaticInventoryBackup] holds the single implementation,
/// so a manual backup and an automatic one can never drift apart.
Future<String> writeAutomaticInventoryBackup(
    InventoryBackupRequest request) async {
  final file = await ExcelService().saveAutomaticInventoryBackup();
  return file.path;
}

/// Records when the last automatic backup was written, so the dashboard can
/// prompt the owner before the snapshot is too old to be useful.
Future<void> recordAutomaticBackupWritten(String path) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
  // The written file is recorded alongside the timestamp so the rotation step
  // and the "last backup" prompt agree on which snapshot is current, and so a
  // future reconciliation can tell a written-but-unrotated snapshot from one
  // that was never produced.
  await prefs.setString('${_lastBackupKey}_path', path);
}

class ExcelService {
  final _db = DatabaseHelper.instance;

  Future<File> exportInventory() async {
    final products = await _db.getProducts(activeOnly: false);
    final book = xl.Excel.createExcel();
    final sheet = book['Inventory'];
    sheet.appendRow(
        Product.sheetHeaders.map((h) => xl.TextCellValue(h)).toList());
    for (final p in products) {
      sheet.appendRow(p.toSheetRow().map(_cell).toList());
    }
    book.delete('Sheet1');
    return _save(book, 'duka-inventory');
  }

  Future<File> exportSales({DateTime? since}) async {
    final sales = await _db.getSales(since: since);
    final book = xl.Excel.createExcel();
    final sheet = book['Sales'];
    sheet.appendRow(Sale.sheetHeaders.map((h) => xl.TextCellValue(h)).toList());
    for (final s in sales) {
      for (final row in s.toSheetRows()) {
        sheet.appendRow(row.map(_cell).toList());
      }
    }
    book.delete('Sheet1');
    return _save(book, 'duka-sales');
  }

  Future<File> exportEncryptedSales({DateTime? since}) async {
    final workbook = await exportSales(since: since);
    final encrypted = await EncryptedBackupService.encryptToFile(
        await workbook.readAsBytes(),
        prefix: 'duka-sales');
    if (workbook.existsSync()) await workbook.delete();
    return encrypted;
  }

  xl.CellValue _cell(dynamic v) {
    if (v is int) return xl.IntCellValue(v);
    if (v is double) return xl.DoubleCellValue(v);
    return xl.TextCellValue(v?.toString() ?? '');
  }

  Future<File> _save(xl.Excel book, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename =
        '$prefix-${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(book.encode()!);
    return file;
  }

  /// Hands the exported file to the OS share sheet (WhatsApp, Bluetooth,
  /// email, "Save to Drive", etc.) rather than assuming any one destination.
  /// Also stamps "last backup" time — the share sheet opening is treated as
  /// a completed backup even though we can't confirm the user picked a
  /// destination, since there's no reliable OS signal for that; better to
  /// slightly over-trust than nag someone who did back up.
  Future<void> shareFile(File file) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'Duka POS export',
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
  }

  /// Saves an opt-in background backup without opening the platform share
  /// sheet. This is used by AutoSyncService while the app is open.
  Future<File> saveAutomaticInventoryBackup() async {
    final workbook = await exportInventory();
    final file = await EncryptedBackupService.encryptToFile(
        await workbook.readAsBytes(),
        prefix: 'duka-inventory');
    if (workbook.existsSync()) await workbook.delete();
    await recordAutomaticBackupWritten(file.path);
    return file;
  }

  Future<File> exportEncryptedInventory() async {
    final workbook = await exportInventory();
    final encrypted = await EncryptedBackupService.encryptToFile(
        await workbook.readAsBytes(),
        prefix: 'duka-inventory');
    if (workbook.existsSync()) await workbook.delete();
    return encrypted;
  }

  Future<int> importEncryptedInventory() async {
    final bytes = await EncryptedBackupService.pickAndDecrypt();
    if (bytes == null) return 0;
    return _importInventoryBytes(bytes);
  }

  static Future<DateTime?> lastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastBackupKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<bool> isBackupOverdue() async {
    final last = await lastBackupTime();
    if (last == null) return true;
    return DateTime.now().difference(last) > backupReminderThreshold;
  }

  /// Reads back a previously exported (or hand-edited) inventory file and
  /// upserts every row. Existing products are matched by id when present,
  /// otherwise treated as new — lets the owner bulk-edit prices in Excel
  /// and re-import rather than editing 40 products one at a time on a phone.
  Future<int> importInventory() async {
    final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (files.isEmpty) return 0;
    final selected = files.single;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The selected workbook could not be read');
    }
    return _importInventoryBytes(bytes);
  }

  Future<int> _importInventoryBytes(List<int> bytes) async {
    final book = xl.Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) {
      throw const FormatException('The workbook has no worksheets');
    }
    final sheet = book.tables.values.first;
    final imported = <Product>[];
    for (final row in sheet.rows.skip(1)) {
      if (row.isEmpty) continue;
      // Single shared row parser/validator (Product.fromRow) so this importer,
      // the Sheets importer and the product editor cannot drift apart.
      final product = Product.fromRow(
        row.map((cell) => cell?.value).toList(),
        parseId: (value) =>
            value == null ? null : int.tryParse(value.toString()),
      );
      if (product != null) imported.add(product);
    }
    await _db.upsertProducts(imported);
    return imported.length;
  }
}
