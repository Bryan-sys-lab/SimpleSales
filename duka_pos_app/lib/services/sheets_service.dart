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
    var count = 0;
    for (final row in values.skip(1)) {
      if (row.length < 7 || row[1].toString().trim().isEmpty) continue;
      final cost = double.tryParse(row[3].toString());
      final price = double.tryParse(row[4].toString());
      final stock = double.tryParse(row[5].toString());
      final reorder = int.tryParse(row[6].toString());
      final bottleMl =
          row.length > 8 ? int.tryParse(row[8].toString()) ?? 750 : 750;
      final half = row.length > 9 && row[9].toString().trim().isNotEmpty
          ? double.tryParse(row[9].toString())
          : null;
      final quarter = row.length > 10 && row[10].toString().trim().isNotEmpty
          ? double.tryParse(row[10].toString())
          : null;
      if (cost == null ||
          price == null ||
          stock == null ||
          reorder == null ||
          cost < 0 ||
          price < 0 ||
          stock < 0 ||
          reorder < 0 ||
          bottleMl < 1 ||
          bottleMl > 10000) {
        throw const FormatException(
            'The sheet contains an invalid inventory row');
      }
      await _db.upsertProduct(Product(
        id: int.tryParse(row[0].toString()),
        name: row[1].toString().trim(),
        category: row[2].toString().trim().isEmpty
            ? 'General'
            : row[2].toString().trim(),
        costPrice: cost,
        sellPrice: price,
        stockQty: stock,
        reorderLevel: reorder,
        bottleMl: bottleMl,
        halfPrice: half,
        quarterPrice: quarter,
        exciseStampBatch: row.length > 7 ? row[7].toString() : '',
        updatedAt: DateTime.now().toIso8601String(),
      ));
      count++;
    }
    return count;
  }

  /// Appends new sales since [since] to the Sales tab, rather than rewriting
  /// the whole sheet every time — sales only ever get added, never edited,
  /// so an append-only log matches how the data actually behaves and is
  /// far cheaper to sync as the log grows over months.
  Future<void> appendSales(String spreadsheetId, {DateTime? since}) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    final sales = await _db.getSales(since: since);
    if (sales.isEmpty) return;
    final rows = <List<dynamic>>[];
    for (final s in sales) {
      rows.addAll(s.toSheetRows());
    }
    await api.spreadsheets.values.append(
      sheets.ValueRange(values: rows),
      spreadsheetId,
      'Sales!A1',
      valueInputOption: 'RAW',
    );
  }
}
