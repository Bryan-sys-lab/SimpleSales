import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../db/database_helper.dart';
import '../models/models.dart';

/// The online half of the hybrid sync. Requires:
///  1. A Google Cloud project with the Sheets API enabled.
///  2. An OAuth client ID registered for this app's package name / bundle id.
///  3. The owner signing in with their Google account once, from Settings.
/// See the setup README for the exact console steps — none of this can be
/// wired up from code alone, it's a one-time account configuration step.
class SheetsService {
  static final _googleSignIn =
      GoogleSignIn(scopes: [sheets.SheetsApi.spreadsheetsScope]);
  final _db = DatabaseHelper.instance;

  Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();
  Future<void> signOut() => _googleSignIn.signOut();
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<sheets.SheetsApi?> _api() async {
    final account =
        _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return null;
    return sheets.SheetsApi(client);
  }

  /// Creates (if needed) and returns the spreadsheet id the app syncs to.
  /// The id is cached in local prefs by the caller after first creation.
  Future<String> ensureSpreadsheet(String? existingId, String shopName) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    if (existingId != null) {
      try {
        await api.spreadsheets.get(existingId);
        return existingId;
      } catch (_) {
        // fall through and create a new one if the cached id is no longer valid
      }
    }
    final spreadsheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: '$shopName — Duka POS'),
      sheets: [
        sheets.Sheet(properties: sheets.SheetProperties(title: 'Inventory')),
        sheets.Sheet(properties: sheets.SheetProperties(title: 'Sales')),
      ],
    );
    final created = await api.spreadsheets.create(spreadsheet);
    return created.spreadsheetId!;
  }

  /// Overwrites the Inventory tab with the current local product list.
  /// This app is the source of truth for stock counts — Sheets is a mirror
  /// for the owner to view/share, not a second place to edit stock from,
  /// which avoids the two-way-sync conflict problem entirely.
  Future<void> pushInventory(String spreadsheetId) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    final products = await _db.getProducts(activeOnly: false);
    final rows = [
      Product.sheetHeaders,
      ...products.map((p) => p.toSheetRow()),
    ];
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: rows),
      spreadsheetId,
      'Inventory!A1',
      valueInputOption: 'RAW',
    );
  }

  /// Imports the same Inventory columns produced by [pushInventory]. This is
  /// deliberately an explicit action: a sheet never silently overwrites local
  /// stock during background sync.
  Future<int> importInventory(String spreadsheetId) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    final values =
        (await api.spreadsheets.values.get(spreadsheetId, 'Inventory!A:K'))
                .values ??
            const <List<dynamic>>[];
    if (values.length < 2) return 0;
    // Same shared parser/validator as the Excel importer and the product
    // editor, and all rows are validated before anything is written.
    final parsed = <Product>[];
    for (final row in values.skip(1)) {
      final product = Product.fromRow(
        row,
        parseId: (value) =>
            value == null ? null : int.tryParse(value.toString()),
      );
      if (product != null) parsed.add(product);
    }
    await _db.upsertProducts(parsed);
    return parsed.length;
  }

  /// Appends sales newer than [after] to the Sales tab, rather than rewriting
  /// the whole sheet every time — sales only ever get added, never edited,
  /// so an append-only log matches how the data actually behaves and is
  /// far cheaper to sync as the log grows over months.
  ///
  /// The window is exclusive so a sale sitting exactly on the previous
  /// high-water mark is appended once, not re-appended on every sync. Work is
  /// drained in bounded batches: a single request carrying a shop's entire
  /// backlog can exceed the Sheets append limits and fail the whole export.
  ///
  /// Returns the newest `created_at` actually written, so the caller can
  /// advance its high-water mark to a value the sheet provably contains rather
  /// than to wall-clock time. Returns null when nothing was appended.
  Future<DateTime?> appendSales(String spreadsheetId,
      {DateTime? after, int batchSize = 500}) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    var cursor = after;
    DateTime? newest;
    while (true) {
      final sales = await _db.getSales(after: cursor, limit: batchSize);
      if (sales.isEmpty) return newest;
      final rows = <List<dynamic>>[];
      DateTime? batchNewest;
      for (final s in sales) {
        rows.addAll(s.toSheetRows());
        final created = DateTime.tryParse(s.createdAt);
        if (created != null && (batchNewest == null || created.isAfter(batchNewest))) {
          batchNewest = created;
        }
      }
      await api.spreadsheets.values.append(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        'Sales!A1',
        valueInputOption: 'RAW',
      );
      newest = batchNewest;
      // Rows come back newest-first, so a batch that did not fill up means the
      // tail is drained and another pass would only re-read the last batch.
      if (sales.length < batchSize || batchNewest == null) return newest;
      cursor = batchNewest;
    }
  }
}
