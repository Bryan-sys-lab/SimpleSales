// The ledger's rows, and the record behind them.
//
// A ledger row is a SUMMARY: an amount, a relative time, a method. It is what
// a shopkeeper scans down. But a question like "what happened at 14:32" cannot
// be answered by a summary, so every row opens a record that says WHEN, WHERE,
// HOW it was paid and WHO rang it.
//
// What this pins:
//   * a row is a TARGET — a row that is not tappable is a dead end, and the
//     person standing at the till has to write the answer down instead;
//   * the record carries the four facts, and the cash detail with them —
//     "Cash" alone does not say whether the drawer balanced;
//   * the WHO line is gated by the same permission as the seller column on the
//     row, so a role that may not read the ledger cannot get the name out of
//     it by tapping;
//   * the record fits a phone at 200% text without overflowing.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/transactions_screen.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/harness.dart';

Sale _sale({
  int id = 7,
  String staff = 'Amina',
  int totalMinor = 1500,
  int items = 2,
  String method = 'cash',
  String? reference,
  int tenderedMinor = 2000,
  int changeMinor = 500,
}) =>
    Sale(
      id: id,
      staffName: staff,
      total: Money.fromMinor(totalMinor),
      profit: Money.fromMinor(400),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      paymentMethod: method,
      paymentReference: reference,
      amountTendered: Money.fromMinor(tenderedMinor),
      changeGiven: Money.fromMinor(changeMinor),
      items: <SaleItem>[
        for (int i = 0; i < items; i++)
          SaleItem(
            saleId: id,
            productId: i,
            productName: 'Item $i',
            qty: 1,
            unitPrice: Money.fromMinor(500),
            unitCost: Money.fromMinor(300),
          ),
      ],
    );

/// A session with a shop, so the record has a WHERE to state.
///
/// The session is provided by the test rather than by the harness: the record
/// is about a sale in a PLACE, and a place has to exist for the row to say so.
Widget _withShop(Widget child) => ChangeNotifierProvider<AppState>(
      create: (_) => AppState()
        ..owner = Owner(
          id: 1,
          name: 'Wanjiru',
          pinHash: 'x',
          shopName: 'Mwirigi Store',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      child: child,
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('a ledger row opens the record behind it', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: _withShop(
        TransactionsRow(
          sale: _sale(),
          audit: null,
          canSeeSellers: true,
        ),
      ),
    );

    // Before the tap: the row, and nothing else.
    expect(find.text(l10n.saleDetailsWhen), findsNothing);

    await tester.tap(find.byType(TransactionsRow));
    await tester.pumpAndSettle();

    // The four facts the record exists to answer.
    expect(find.text(l10n.saleDetailsWhen), findsOneWidget);
    expect(find.text(l10n.saleDetailsWhere), findsOneWidget);
    expect(find.text(l10n.saleDetailsHow), findsOneWidget);
    expect(find.text(l10n.saleDetailsWho), findsOneWidget);

    // WHO is a NAME, not a label, and WHERE is the shop the sale was rung in.
    expect(find.text('Amina'), findsWidgets);
    expect(find.text('Mwirigi Store'), findsOneWidget);

    // And the lines, so the total can be checked against the shelf.
    expect(find.text(l10n.saleDetailsWhat), findsOneWidget);
    expect(find.text('Item 0'), findsOneWidget);
  });

  testWidgets('a cash sale says what moved, not just "cash"', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: _withShop(
        TransactionsRow(
          sale: _sale(),
          audit: null,
          canSeeSellers: true,
        ),
      ),
    );

    await tester.tap(find.byType(TransactionsRow));
    await tester.pumpAndSettle();

    // Tendered and change: the two figures that say whether the drawer
    // balanced. "Cash" on its own does not.
    expect(find.textContaining('Tendered'), findsOneWidget);
  });

  testWidgets('a mobile-money sale shows the provider reference',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: _withShop(
        TransactionsRow(
          sale:
              _sale(method: 'mpesa', reference: 'QJG7X2K9AB', tenderedMinor: 0),
          audit: null,
          canSeeSellers: true,
        ),
      ),
    );

    await tester.tap(find.byType(TransactionsRow));
    await tester.pumpAndSettle();

    expect(find.textContaining('QJG7X2K9AB'), findsOneWidget);
  });

  testWidgets('a role that may not read the ledger gets no name',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: _withShop(
        TransactionsRow(
          sale: _sale(),
          audit: null,
          canSeeSellers: false,
        ),
      ),
    );

    await tester.tap(find.byType(TransactionsRow));
    await tester.pumpAndSettle();

    // The money is still readable; the seller is not.
    expect(find.text(l10n.saleDetailsHow), findsOneWidget);
    expect(find.text(l10n.saleDetailsWho), findsNothing);
    expect(find.text('Amina'), findsNothing);
  });

  testWidgets('the record fits a 320dp phone at 200% text', (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: _withShop(
        TransactionsRow(
          sale: _sale(items: 6),
          audit: null,
          canSeeSellers: true,
        ),
      ),
      textScaler: TextScaler.linear(2.0),
    );

    await tester.tap(find.byType(TransactionsRow));
    await tester.pumpAndSettle();

    tester.expectNoOverflow('sale details at 2x text');
  });
}
