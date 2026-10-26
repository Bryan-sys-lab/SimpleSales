import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import 'encrypted_backup_service.dart';
import 'import_row_parser.dart';
import 'inventory_importer.dart';
import '../utils/crypto_utils.dart';

export 'inventory_importer.dart' show InventoryImportResult;

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

/// Writes the complete local workspace for the opt-in automatic backup path.
/// Unlike the spreadsheet export, this includes staff, queues, audit history,
/// credit, shifts, and every analytics source table.
Future<String> writeAutomaticFullBackup(InventoryBackupRequest request) async {
  final file = await ExcelService().saveAutomaticFullBackup();
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

  /// Tabs this importer knows how to read. Anything else in the workbook is
  /// reported as skipped rather than silently ignored: a `Sales` tab the owner
  /// expected to come in is worth saying out loud.
  static const _readableSheetNames = {'inventory', 'barcodes', 'variants'};

  /// Exports the catalogue.
  ///
  /// Writes three sheets: `Inventory`, one row per product carrying its *primary*
  /// barcode; `Barcodes`, one row per additional code; and `Variants`, one row
  /// per sellable version. One product can no longer hold all of its codes in a
  /// single column, and inventing a delimiter-joined "primary|secondary|tertiary"
  /// column would break every existing importer and any spreadsheet formula
  /// reading the file.
  Future<File> exportInventory() async {
    final products = await _db.getProducts(activeOnly: false);
    final barcodes = await _db.getAllBarcodes();
    final variants = await _db.getAllVariants();

    // A product's primary code is the first one it owns. Stable by insertion
    // order so a re-export does not reshuffle which code is "primary".
    final primaryByProduct = <int, String>{};
    final extra = <ProductBarcode>[];
    for (final code in barcodes) {
      if (primaryByProduct.containsKey(code.productId)) {
        extra.add(code);
      } else {
        primaryByProduct[code.productId] = code.barcode;
      }
    }

    final book = xl.Excel.createExcel();
    final sheet = book[inventorySheetName];
    sheet.appendRow(
        Product.sheetHeaders.map((h) => xl.TextCellValue(h)).toList());
    for (final p in products) {
      sheet.appendRow(
          p.toSheetRow(barcode: primaryByProduct[p.id]).map(_cell).toList());
    }
    book.delete('Sheet1');

    // Always written, even when empty, so an export → edit → re-import cycle
    // has a stable shape. Importing a workbook with no such sheet is still
    // supported, so a file from an older version imports unchanged.
    final barcodeSheet = book[barcodesSheetName];
    barcodeSheet.appendRow(
        ProductBarcode.sheetHeaders.map((h) => xl.TextCellValue(h)).toList());
    for (final code in extra) {
      barcodeSheet.appendRow([
        code.productId,
        code.barcode,
        code.kind,
      ].map(_cell).toList());
    }

    final variantSheet = book[variantsSheetName];
    variantSheet.appendRow(
        ProductVariant.sheetHeaders.map((h) => xl.TextCellValue(h)).toList());
    for (final variant in variants) {
      variantSheet.appendRow(variantSheetRow(variant).map(_cell).toList());
    }

    return _save(book, 'duka-inventory');
  }

  /// Exports every sale in the requested period by default. A limit is only
  /// applied when the caller explicitly asks for a bounded export; reports
  /// must never silently truncate a one-year history.
  Future<File> exportSales({DateTime? since, int? limit}) async {
    final sales = await _db.getSales(since: since, limit: limit);
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

  Future<File> exportEncryptedSales({DateTime? since, int? limit}) async {
    final workbook = await exportSales(since: since, limit: limit);
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

  /// Encodes a workbook to bytes off the main thread.
  ///
  /// The `excel` codec is pure Dart and transferable across isolates, so it
  /// can run on a background isolate without the platform channels that
  /// `getProducts`/`getSales` need on the main isolate.
  static List<int> _encodeWorkbook(xl.Excel book) => book.encode()!;

  /// Decodes a workbook off the main thread.
  ///
  /// THE BUG THIS FIXES. The import used to decode on the UI isolate, and
  /// decoding a workbook is ZIP inflation plus XML parsing of every sheet —
  /// pure CPU, no I/O, seconds on a supplier price list.
  ///
  /// On Android that is two ways to lose the session:
  ///
  ///   * the UI isolate blocks, the system shows "SimpleSales isn't
  ///     responding", and the owner taps "Close app" — which kills the
  ///     process. A process that restarts comes back SIGNED OUT, because the
  ///     session is deliberately not persisted across restarts. That is what
  ///     "importing logged me out" is;
  ///   * the workbook, the inflated archive, the parsed sheets and the raw
  ///     cell copies are all in memory at once, and a cheap handset's
  ///     low-memory killer ends it the same way.
  ///
  /// The EXPORT already did this (see [_encodeWorkbook]). The import did not,
  /// and it is the heavier of the two: an export writes the app's own
  /// catalogue, and an import reads whatever a supplier sent.
  static Future<xl.Excel> _decodeWorkbook(List<int> bytes) =>
      compute(_decodeWorkbookSync, bytes);

  /// The isolate's half of the decode.
  static xl.Excel _decodeWorkbookSync(List<int> bytes) =>
      xl.Excel.decodeBytes(bytes);

  Future<File> _save(xl.Excel book, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename =
        '$prefix-${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    final file = File('${dir.path}/$filename');
    final bytes = await compute(_encodeWorkbook, book);
    await file.writeAsBytes(bytes);
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
    final clearBytes = await workbook.readAsBytes();
    final file = await EncryptedBackupService.encryptToFile(clearBytes,
        prefix: 'duka-inventory');
    if (workbook.existsSync()) await workbook.delete();
    await _db.recordBackupLog(
      uuid: generateUuid(),
      kind: 'automatic_device_bound',
      path: file.path,
      clearBytes: clearBytes.length,
    );
    await recordAutomaticBackupWritten(file.path);
    return file;
  }

  Future<File> saveAutomaticFullBackup() async {
    final snapshot = await _db.exportFullSnapshot();
    final clearBytes = utf8.encode(jsonEncode(snapshot));
    final file = await EncryptedBackupService.encryptToFile(
      clearBytes,
      prefix: 'duka-autobackup',
    );
    await _db.recordBackupLog(
      uuid: generateUuid(),
      kind: 'automatic_full_device_bound',
      path: file.path,
      clearBytes: clearBytes.length,
      manifestJson: jsonEncode(snapshot['manifest']),
    );
    await recordAutomaticBackupWritten(file.path);
    return file;
  }

  Future<File> exportEncryptedInventory() async {
    final workbook = await exportInventory();
    final clearBytes = await workbook.readAsBytes();
    final encrypted = await EncryptedBackupService.encryptToFile(clearBytes,
        prefix: 'duka-inventory');
    if (workbook.existsSync()) await workbook.delete();
    await _db.recordBackupLog(
      uuid: generateUuid(),
      kind: 'encrypted_device_bound',
      path: encrypted.path,
      clearBytes: clearBytes.length,
    );
    return encrypted;
  }

  Future<File> exportPortableEncryptedInventory(String passphrase) async {
    final workbook = await exportInventory();
    final clearBytes = await workbook.readAsBytes();
    final encrypted = await EncryptedBackupService.encryptPortableToFile(
      clearBytes,
      passphrase: passphrase,
      prefix: 'duka-inventory-portable',
    );
    if (workbook.existsSync()) await workbook.delete();
    await _db.recordBackupLog(
      uuid: generateUuid(),
      kind: 'portable_passphrase',
      path: encrypted.path,
      clearBytes: clearBytes.length,
    );
    return encrypted;
  }

  /// Full portable backup: unlike the spreadsheet export this carries every
  /// local table, including sales, staff, permissions, credit, shifts, audit
  /// history, queues and the source data used by analytics.
  Future<File> exportPortableFullBackup(String passphrase) async {
    final snapshot = await _db.exportFullSnapshot();
    final clearBytes = utf8.encode(jsonEncode(snapshot));
    final encrypted = await EncryptedBackupService.encryptPortableToFile(
      clearBytes,
      passphrase: passphrase,
      prefix: 'duka-full-portable',
    );
    await _db.recordBackupLog(
      uuid: generateUuid(),
      kind: 'portable_full_passphrase',
      path: encrypted.path,
      clearBytes: clearBytes.length,
      manifestJson: jsonEncode(snapshot['manifest']),
    );
    return encrypted;
  }

  Future<int> importPortableEncryptedInventory(String passphrase) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['duka'],
    );
    if (files.isEmpty) return 0;
    final bytes = await EncryptedBackupService.decryptPortableBytes(
      encodedBytes: await File(files.single.path!).readAsBytes(),
      passphrase: passphrase,
    );
    return (await importInventoryBytes(bytes)).imported;
  }

  Future<void> importPortableFullBackup(String passphrase) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['duka'],
    );
    if (files.isEmpty) return;
    final bytes = await EncryptedBackupService.decryptPortableBytes(
      encodedBytes: await File(files.single.path!).readAsBytes(),
      passphrase: passphrase,
    );
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Invalid full backup');
    await _db.restoreFullSnapshot(
      Map<String, Object?>.from(decoded),
      allowWorkspaceMismatch: true,
    );
  }

  Future<int> importEncryptedInventory() async {
    final bytes = await EncryptedBackupService.pickAndDecrypt();
    if (bytes == null) return 0;
    return (await importInventoryBytes(bytes)).imported;
  }

  /// The restore, from bytes.
  ///
  /// The production path goes through the share sheet and a file picker; this is
  /// the same importer from the moment the bytes arrive, which is what a test
  /// can drive and what a restore actually depends on.
  @visibleForTesting
  Future<InventoryImportResult> importInventoryBytesForTest(List<int> bytes) =>
      importInventoryBytes(bytes);

  /// Records when a backup was written, at an injectable moment.
  ///
  /// Production records "now"; a test ages the stamp to prove the reminder
  /// re-appears without waiting thirty days for it.
  @visibleForTesting
  static Future<void> recordAutomaticBackupForTest(String path,
      {DateTime? at}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastBackupKey, (at ?? DateTime.now()).toIso8601String());
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
  Future<InventoryImportResult> importInventory({
    void Function(ImportProgress)? onProgress,
  }) async {
    final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (files.isEmpty) {
      return const InventoryImportResult(imported: 0);
    }
    final selected = files.single;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The selected workbook could not be read');
    }
    return importInventoryBytes(bytes, onProgress: onProgress);
  }

  /// The whole import, from the bytes of a workbook.
  ///
  /// Public so the tests can drive a real .xlsx through the real code path
  /// rather than a stand-in: the bugs this fixes — the sheet found by position,
  /// the unconditional `skip(1)`, the count that reported parses as imports —
  /// only exist in the code between the bytes and the database, and a test that
  /// mocks that away is testing nothing.
  @visibleForTesting
  Future<InventoryImportResult> importInventoryBytes(
    List<int> bytes, {
    void Function(ImportProgress)? onProgress,
  }) async {
    onProgress?.call(const ImportProgress(ImportStage.reading));
    final xl.Excel book;
    try {
      // Off the UI isolate. See [_decodeWorkbook] for why that is the
      // difference between an import and a signed-out till.
      book = await _decodeWorkbook(bytes);
    } catch (_) {
      // A .csv renamed to .xlsx lands here, and "could not be opened as a
      // workbook" is actionable where the decoder's own error is not.
      throw const FormatException(
        'That file could not be opened as a workbook. Open it in Excel and use '
        '"Save As" to save a new .xlsx, then import that.',
      );
    }
    try {
      if (book.tables.isEmpty) {
        throw const FormatException('The workbook has no worksheets');
      }
    } on ArgumentError {
      // `Excel.tables` throws rather than returning an empty map when the
      // workbook is damaged, and an `ArgumentError` is neither a
      // `FormatException` nor an `UnreadableLayoutException` — so a corrupt
      // file used to be reported as a generic failure instead of the message
      // that says what is wrong with it.
      throw const FormatException('The workbook has no worksheets');
    }

    final sheetName = _inventorySheetName(book);
    final layout = SheetLayout.fromRawRows(_rawRows(book.tables[sheetName]!));
    // Refused whole rather than read positionally. A workbook we cannot map is
    // not a workbook with 287 bad rows in it — see SheetLayout.refusal.
    //
    // Nothing is resolved on the way out. A refusal says nothing about the rows
    // a PREVIOUS import of a different file left behind — and `sheetName` here
    // is this file's tab (falling back to its first non-empty one), which need
    // not be the tab those problems were recorded under. Resolving them on a
    // refusal destroys the only copy of the raw row values the owner can still
    // finish on the imports screen. Only a successful `apply()` supersedes the
    // previous import's problems.
    if (layout.refusal != null) {
      throw UnreadableLayoutException(layout.refusal!);
    }
    final importer = InventoryImporter(_db);
    return importer.apply(
      source: 'excel',
      sheetName: sheetName,
      rows: layout.rows,
      columns: layout.columns,
      barcodes: readBarcodeRows(_rawRowsOf(book, barcodesSheetName)),
      variants: readVariantRows(_rawRowsOf(book, variantsSheetName)),
      skippedSheets: _skippedSheets(book),
      onProgress: onProgress,
    );
  }

  /// The tab holding the inventory.
  ///
  /// A tab literally named `Inventory` wins, because that is this app's own
  /// export and there is nothing to work out.
  ///
  /// Otherwise the tabs are SCORED, not taken in order. The old rule was "the
  /// first tab that has rows", and it broke on the two shapes real supplier
  /// files come in:
  ///
  ///   * a daily stock tracker — one tab per day, 190 of them, none named
  ///     anything useful. The first tab is the oldest day in the book, so the
  ///     import wrote last March's stock as today's.
  ///   * a workbook whose first tab is a cover page or a summary, with the
  ///     product list further along.
  ///
  /// So every tab is read for its header, and the one that maps the most
  /// fields onto the app's columns wins; a tie goes to the tab with more
  /// product rows, and a further tie to the LAST one, which for a book of
  /// daily tabs is the most recent day — the only one whose closing stock is
  /// still true.
  ///
  /// The `Barcodes` and `Variants` tabs are not candidates: they are read
  /// separately by name, and a file that has them would otherwise have its
  /// barcode list chosen as the product list because it is shorter and its
  /// header maps cleanly.
  static String _inventorySheetName(xl.Excel book) {
    for (final name in book.tables.keys) {
      if (name.trim().toLowerCase() == inventorySheetName.toLowerCase()) {
        return name;
      }
    }

    final skip = {
      barcodesSheetName.toLowerCase(),
      variantsSheetName.toLowerCase(),
    };
    String? bestName;
    var bestScore = -1;
    for (final name in book.tables.keys) {
      final lower = name.trim().toLowerCase();
      if (skip.contains(lower)) continue;
      final raw = _rawRows(book.tables[name]!);
      if (raw.isEmpty) continue;
      final layout = SheetLayout.fromRawRows(raw);
      // A tab with no header we can map is a cover page, a note, or a picture
      // of a table — not the table.
      if (!layout.headerRowDetected || layout.refusal != null) continue;
      final mapped = layout.columns.mappedCount;
      // `>=`, not `>`: a daily tracker's tabs all map the same columns, so the
      // tie is the normal case and the LAST tab wins. Counting ROWS as a
      // tiebreak was worse than useless here — a day's row count includes its
      // section titles and moves with every sale — so the oldest day could
      // outrank the newest by having one more "SPIRITS" heading.
      if (mapped >= bestScore) {
        bestScore = mapped;
        bestName = name;
      }
    }
    if (bestName != null) return bestName;

    for (final name in book.tables.keys) {
      if (_rawRows(book.tables[name]!).isNotEmpty) return name;
    }
    // Nothing but empty sheets. Take the first so the caller reports a count of
    // zero against a named tab rather than crashing on a missing one.
    return book.tables.keys.first;
  }

  /// Tabs this import did not read, by name.
  /// Tabs present in the file that this importer did not read.
  ///
  /// Only *other* tabs count as skipped. The sheet it actually read is not a
  /// skipped sheet however unusual its name, so a workbook whose data is on a
  /// tab called "Price List" is not reported as having skipped its own data.
  /// [skipEmptySheets] drops `Sheet1`-style defaults, which are absent from the
  /// file the owner actually sees and would otherwise be listed as ignored
  /// content they never knew was there.
  List<String> _skippedSheets(xl.Excel book, {bool skipEmpty = true}) {
    final read = _inventorySheetName(book).trim().toLowerCase();
    return book.tables.keys
        .where((name) => name.trim().toLowerCase() != read)
        .where(
            (name) => !_readableSheetNames.contains(name.trim().toLowerCase()))
        .where((name) => !skipEmpty || _rawRows(book.tables[name]!).isNotEmpty)
        .toList();
  }

  /// Cell values of a sheet, one list per row, blanks preserved as null.
  static List<List<dynamic>> _rawRows(xl.Sheet sheet) =>
      sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList();

  /// [rawRows] for an optional tab, or an empty list when it is absent.
  static List<List<dynamic>> _rawRowsOf(xl.Excel book, String name) {
    final sheet = book.tables[name];
    return sheet == null ? const [] : _rawRows(sheet);
  }
}
