import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import 'import_row_parser.dart';
import 'inventory_importer.dart';

/// The online half of the hybrid sync. Requires:
///  1. A Google Cloud project with the Sheets API enabled.
///  2. An OAuth client ID registered for this app's package name / bundle id.
///  3. The owner signing in with their Google account once, from Settings.
/// See the setup README for the exact console steps — none of this can be
/// wired up from code alone, it's a one-time account configuration step.
class SheetsService {
  /// The singleton `google_sign_in` 7.x exposes.
  ///
  /// 7.x removed the instance constructor entirely, and with it
  /// `signIn`/`signInSilently`/`authenticatedClient`. The replacements are
  /// `authenticate()` and `attemptLightweightAuthentication()` on the singleton,
  /// with the account moved under `authentication`. The public surface of this
  /// class is deliberately unchanged so `SyncService` did not have to change.
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  final _db = DatabaseHelper.instance;

  /// The second tab, holding every code that is *not* the product's primary
  /// barcode.
  ///
  /// Named rather than indexed so a workbook whose tabs are reordered still
  /// imports, and absent-able so a spreadsheet created before barcodes existed
  /// keeps working unchanged.
  static const barcodesSheetTitle = barcodesSheetName;

  /// The third tab, holding sellable versions of a product. Optional for the
  /// same reason the second one is.
  static const variantsSheetTitle = variantsSheetName;

  /// A1 range for the Inventory tab.
  ///
  /// Derived from [Product.sheetHeaders] instead of hand-written as
  /// `Inventory!A1:K`. A hardcoded letter range next to a growing header list is
  /// a silent data-loss bug: Google Sheets truncates a write at the end of the
  /// range, so adding a twelfth column without widening this would drop it on
  /// the floor with no error anywhere.
  static String get inventoryRange =>
      'Inventory!A1:${_columnLetter(Product.sheetColumnCount)}';

  /// A1 range for the Barcodes tab, header row included.
  static String get barcodesRange =>
      '$barcodesSheetTitle!A1:${_columnLetter(ProductBarcode.sheetHeaders.length)}';

  /// A1 range for the Variants tab, header row included.
  static String get variantsRange =>
      '$variantsSheetTitle!A1:${_columnLetter(ProductVariant.sheetColumnCount)}';

  /// 1 -> A, 26 -> Z, 27 -> AA.
  static String _columnLetter(int oneBasedIndex) {
    var value = oneBasedIndex;
    var letters = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      letters = String.fromCharCode(0x41 + remainder) + letters;
      value = (value - 1) ~/ 26;
    }
    return letters;
  }

  /// The account this device last authenticated.
  ///
  /// Cached here because `google_sign_in` 7.x removed `currentUser` entirely:
  /// the account now comes only from `authenticate()`,
  /// `attemptLightweightAuthentication()` or the `authenticationEvents` stream.
  /// There is no synchronous accessor, and `isGoogleLinked` on a sync screen
  /// cannot afford to be async, so the last known account is kept and
  /// invalidated explicitly on sign-out.
  GoogleSignInAccount? _account;

  /// The Sheets scopes this app needs. Nothing else is requested: asking for
  /// more makes the consent screen longer for a grant the app never uses.
  static const _scopes = <String>[sheets.SheetsApi.spreadsheetsScope];

  /// One-time platform init. Safe to call repeatedly.
  ///
  /// 7.x requires `initialize` before anything else. Its platform `init` is
  /// idempotent, so it is called on every entry point rather than guarded by a
  /// flag — a flag would break on a hot restart, where the Dart singleton is
  /// rebuilt but the platform side is not.
  static Future<void> _init() async {
    try {
      await _googleSignIn.initialize();
    } catch (error) {
      debugPrint('Google Sign In init failed: $error');
    }
  }

  /// Authenticates the user interactively and returns the account.
  ///
  /// Authentication (who) and scope authorisation (access to Sheets) are two
  /// distinct grants in 7.x. This only does the first; [_api] asks for the
  /// second with a silent attempt so a background sync never opens a consent
  /// screen in front of a customer.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _init();
      _account = await _googleSignIn.authenticate(scopeHint: _scopes);
      return _account;
    } catch (error) {
      // 7.x throws rather than returning null when the user declines, and a
      // declined sign-in is a normal outcome the caller already handles.
      debugPrint('Google sign-in failed: $error');
      return null;
    }
  }

  Future<void> signOut() async {
    _account = null;
    await _googleSignIn.disconnect();
  }

  /// Whether a user is currently authenticated.
  ///
  /// Answers only the "is someone signed in" question, never "do we hold a
  /// usable Sheets grant" — those are separate and conflating them is how a
  /// shop ends up told it is linked while every sync silently no-ops.
  bool get isSignedIn => _account != null;

  /// The cached account, or null.
  GoogleSignInAccount? get currentUser => _account;

  /// An authorised Sheets API client, or null when the shop is not signed in.
  Future<sheets.SheetsApi?> _api() async {
    try {
      await _init();
      _account ??= await _googleSignIn.attemptLightweightAuthentication();
      final account = _account;
      if (account == null) return null;

      // Silent first: returns null when the grant would need a prompt, which is
      // the signal to stay signed out rather than to interrupt a customer.
      // 7.x hangs the scope API off the account's `authorizationClient`, not off
      // the account itself.
      final authz =
          await account.authorizationClient.authorizationForScopes(_scopes);
      if (authz == null) return null;

      return sheets.SheetsApi(authz.authClient(scopes: _scopes));
    } catch (error) {
      // A revoked grant, an expired token or a declined prompt all land here.
      // Callers treat a null API as "not signed in", so swallowing it is what
      // keeps a Sheets sync failure from becoming a crash.
      debugPrint('Google Sheets auth unavailable: $error');
      return null;
    }
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
        sheets.Sheet(
            properties: sheets.SheetProperties(title: barcodesSheetTitle)),
        sheets.Sheet(
            properties: sheets.SheetProperties(title: variantsSheetTitle)),
      ],
    );
    final created = await api.spreadsheets.create(spreadsheet);
    return created.spreadsheetId!;
  }

  /// Overwrites the Inventory tab with the current local product list.
  /// This app is the source of truth for stock counts — Sheets is a mirror
  /// for the owner to view/share, not a second place to edit stock from,
  /// which avoids the two-way-sync conflict problem entirely.
  ///
  /// Also writes the Barcodes and Variants tabs, because one product can carry
  /// several codes and several sellable versions, and the Inventory row can
  /// only hold the primary code and one price.
  Future<void> pushInventory(String spreadsheetId) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    final products = await _db.getProducts(activeOnly: false);
    final barcodes = await _db.getAllBarcodes();
    final variants = await _db.getAllVariants();

    // Primary code = the first code the product owns. Insertion order, so a
    // re-export does not reshuffle which code the Inventory column shows.
    final primaryByProduct = <int, String>{};
    final extra = <ProductBarcode>[];
    for (final code in barcodes) {
      if (primaryByProduct.containsKey(code.productId)) {
        extra.add(code);
      } else {
        primaryByProduct[code.productId] = code.barcode;
      }
    }

    final rows = [
      Product.sheetHeaders,
      ...products.map((p) => p.toSheetRow(barcode: primaryByProduct[p.id])),
    ];
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: rows),
      spreadsheetId,
      inventoryRange,
      valueInputOption: 'RAW',
    );

    await _pushBarcodes(api, spreadsheetId, extra);
    await _pushVariants(api, spreadsheetId, variants);
  }

  /// Writes the Barcodes tab, creating the tab if the spreadsheet predates
  /// barcodes.
  ///
  /// A missing tab is a normal state, not an error: a spreadsheet created
  /// before this feature has only Inventory and Sales, and the owner's next
  /// sync is when it gains a third tab.
  Future<void> _pushBarcodes(
    sheets.SheetsApi api,
    String spreadsheetId,
    List<ProductBarcode> extra,
  ) async {
    final rows = [
      ProductBarcode.sheetHeaders,
      ...extra.map((code) => [
            code.productId,
            code.barcode,
            code.kind,
          ]),
    ];
    try {
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        barcodesRange,
        valueInputOption: 'RAW',
      );
    } catch (_) {
      await _ensureBarcodesTab(api, spreadsheetId);
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        barcodesRange,
        valueInputOption: 'RAW',
      );
    }
  }

  Future<void> _ensureBarcodesTab(
      sheets.SheetsApi api, String spreadsheetId) async {
    await _ensureTab(api, spreadsheetId, barcodesSheetTitle);
  }

  /// Writes the Variants tab, creating it when the spreadsheet predates it.
  ///
  /// Same shape as [_pushBarcodes] and the same reason for it: a tab that does
  /// not exist yet is a normal state, not a failed sync, and the owner's next
  /// sync is when the spreadsheet gains one.
  Future<void> _pushVariants(
    sheets.SheetsApi api,
    String spreadsheetId,
    List<ProductVariant> variants,
  ) async {
    final rows = [
      ProductVariant.sheetHeaders,
      ...variants.map(variantSheetRow),
    ];
    try {
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        variantsRange,
        valueInputOption: 'RAW',
      );
    } catch (_) {
      await _ensureTab(api, spreadsheetId, variantsSheetTitle);
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: rows),
        spreadsheetId,
        variantsRange,
        valueInputOption: 'RAW',
      );
    }
  }

  Future<void> _ensureTab(
    sheets.SheetsApi api,
    String spreadsheetId,
    String title,
  ) async {
    final requests = [
      sheets.Request(
        addSheet: sheets.AddSheetRequest(
          properties: sheets.SheetProperties(title: title),
        ),
      ),
    ];
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
    );
  }

  /// Imports the same Inventory columns produced by [pushInventory]. This is
  /// deliberately an explicit action: a sheet never silently overwrites local
  /// stock during background sync.
  ///
  /// The Barcodes and Variants tabs are read when present and skipped when
  /// absent, so a spreadsheet that was never given one still imports.
  ///
  /// Returns the number of rows actually written, not the number read. The
  /// Excel importer reports the same figure from the same writer, so "imported"
  /// means one thing in both places.
  Future<int> importInventory(String spreadsheetId) async {
    final api = await _api();
    if (api == null) throw StateError('Not signed in to Google');
    final values = await _values(api, spreadsheetId, inventoryRange);
    if (values.isEmpty) return 0;

    // The same layout reader as the Excel path: a header row is detected rather
    // than assumed, so a spreadsheet whose first product was moved into row 1
    // by hand still imports that product instead of eating it.
    final layout = SheetLayout.fromRawRows(values);
    // Refused whole rather than read positionally, exactly as the Excel path
    // refuses it. A sheet is either readable by name or it is not ours.
    //
    // Nothing is resolved on the way out, same as the Excel path: a refusal is
    // a statement about this read, not about the rows the last good import
    // left behind. Only a successful `apply()` supersedes them.
    if (layout.refusal != null) {
      throw UnreadableLayoutException(layout.refusal!);
    }
    final result = await InventoryImporter(_db).apply(
      source: 'sheets',
      sheetName: inventorySheetName,
      rows: layout.rows,
      columns: layout.columns,
      barcodes:
          readBarcodeRows(await _values(api, spreadsheetId, barcodesRange)),
      variants:
          readVariantRows(await _values(api, spreadsheetId, variantsRange)),
    );
    return result.imported;
  }

  /// One tab's values, or an empty list when the tab is absent.
  ///
  /// A missing tab is a normal state, not an import failure: a spreadsheet
  /// created before barcodes existed has none, and refusing the whole inventory
  /// because an *optional* tab is missing is how a sync stops happening.
  Future<List<List<dynamic>>> _values(
    sheets.SheetsApi api,
    String spreadsheetId,
    String range,
  ) async {
    try {
      return (await api.spreadsheets.values.get(spreadsheetId, range)).values ??
          const <List<dynamic>>[];
    } catch (_) {
      return const [];
    }
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
      {DateTime? after, int batchSize = 500, Future<void> Function(DateTime)? onBatch}) async {
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
        if (created != null &&
            (batchNewest == null || created.isAfter(batchNewest))) {
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
      // Report progress so the caller can persist the watermark per batch and
      // never re-append rows that already reached the sheet, even if a later
      // batch fails.
      await onBatch?.call(batchNewest!);
      // Rows come back newest-first, so a batch that did not fill up means the
      // tail is drained and another pass would only re-read the last batch.
      if (sales.length < batchSize || batchNewest == null) return newest;
      cursor = batchNewest;
    }
  }
}
