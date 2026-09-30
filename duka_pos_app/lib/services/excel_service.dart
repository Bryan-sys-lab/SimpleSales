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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
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
      if (row.isEmpty || row.length < 7 || row[1]?.value == null) continue;
      final idVal = row[0]?.value;
      final name = row[1]!.value.toString().trim();
      final category = row[2]?.value?.toString().trim() ?? 'General';
      final cost = double.tryParse(row[3]?.value?.toString() ?? '');
      final price = double.tryParse(row[4]?.value?.toString() ?? '');
      final stock = double.tryParse(row[5]?.value?.toString() ?? '');
      final reorder = int.tryParse(row[6]?.value?.toString() ?? '');
      final bottleMl = row.length > 8
          ? int.tryParse(row[8]?.value?.toString() ?? '') ?? 750
          : 750;
      final halfPrice =
          row.length > 9 && (row[9]?.value?.toString() ?? '').trim().isNotEmpty
              ? double.tryParse(row[9]!.value.toString())
              : null;
      final quarterPrice = row.length > 10 &&
              (row[10]?.value?.toString() ?? '').trim().isNotEmpty
          ? double.tryParse(row[10]!.value.toString())
          : null;
      if (name.isEmpty ||
          name.length > 120 ||
          category.length > 80 ||
          cost == null ||
          !cost.isFinite ||
          cost < 0 ||
          price == null ||
          !price.isFinite ||
          price < 0 ||
          stock == null ||
          !stock.isFinite ||
          stock < 0 ||
          reorder == null ||
          reorder < 0 ||
          bottleMl < 1 ||
          bottleMl > 10000 ||
          (halfPrice != null && (!halfPrice.isFinite || halfPrice < 0)) ||
          (quarterPrice != null &&
              (!quarterPrice.isFinite || quarterPrice < 0))) {
        throw const FormatException(
            'The workbook contains an invalid inventory row');
      }
      final product = Product(
        id: idVal == null ? null : int.tryParse(idVal.toString()),
        name: name,
        category: category.isEmpty ? 'General' : category,
        costPrice: cost,
        sellPrice: price,
        stockQty: stock.toDouble(),
        reorderLevel: reorder,
        bottleMl: bottleMl,
        halfPrice: halfPrice,
        quarterPrice: quarterPrice,
        exciseStampBatch:
            row.length > 7 ? (row[7]?.value?.toString() ?? '') : '',
        updatedAt: DateTime.now().toIso8601String(),
      );
      imported.add(product);
    }
    for (final product in imported) {
      await _db.upsertProduct(product);
    }
    return imported.length;
  }
}
