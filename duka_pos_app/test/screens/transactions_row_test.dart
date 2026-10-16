// The ledger's list rows, from constructed values.
//
// What this pins is the pairing the screen exists for: the money (totals, items,
// tender) and the accountability (who the audit log says rang it). A list of only
// one of the two cannot answer "who sold what", which is the question the
// dashboard's transactions count opens this to answer.
//
// Rendered from constructed values so no database has to be seeded to check the
// layout, and the pins below are the ones that are silently breakable: a pruned
// audit log must not blank a sale, and the seller column must stay gated.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/audit_log.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/screens/transactions_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

Sale _sale({
  int id = 7,
  String staff = 'Amina',
  int totalMinor = 1500,
  int items = 2,
}) =>
    Sale(
      id: id,
      staffName: staff,
      total: Money.fromMinor(totalMinor),
      profit: Money.fromMinor(400),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      paymentMethod: 'cash',
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

AuditLogEntry _audit({String actor = 'Amina', int saleId = 7}) => AuditLogEntry(
      action: AuditAction.saleRecorded,
      entity: AuditEntity.sale,
      entityId: 'id-$saleId',
      actorName: actor,
      detail: '2 line(s), cash',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('the money and the accountability, on one row', () {
    testWidgets('both halves are named when the log has the sale',
        (WidgetTester tester) async {
      await tester.pumpApp(
        home: TransactionsRow(
          sale: _sale(staff: 'Amina'),
          audit: _audit(actor: 'Amina'),
          canSeeSellers: true,
        ),
      );

      // The money half: which sale it was.
      expect(find.text(l10n.transactionsSoldBy('Amina')), findsOneWidget);
      // The accountability half: the same act, read as who logged it.
      expect(find.text(l10n.transactionsAuditBy('Amina')), findsOneWidget);
      expect(find.textContaining('KSh'), findsWidgets);
    });

    testWidgets('a sale whose log entry was pruned still says everything it can',
        (WidgetTester tester) async {
      // The audit counter is dropped on retention, and a pruned log must not
      // turn a sale into a blank row — the money is still the money.
      await tester.pumpApp(
        home: TransactionsRow(
          sale: _sale(staff: 'Amina'),
          audit: null,
          canSeeSellers: true,
        ),
      );

      expect(find.text(l10n.transactionsSoldBy('Amina')), findsOneWidget,
          reason: 'who rang it is on the sale row itself, not only the log');
      expect(find.textContaining('Logged as'), findsNothing);
    });

    testWidgets('a role that may not read the ledger does not see who sold',
        (WidgetTester tester) async {
      // The who-sold-it column is management-facing: a cashier's own shift is
      // theirs, a roster-wide ledger of everyone's is not.
      await tester.pumpApp(
        home: TransactionsRow(
          sale: _sale(staff: 'Amina'),
          audit: _audit(actor: 'Amina'),
          canSeeSellers: false,
        ),
      );

      expect(find.textContaining('Sold by'), findsNothing,
          reason: 'the seller column is gated');
      expect(find.textContaining('Logged as'), findsNothing,
          reason: 'and so is the audit half, which names the same people');
    });

    testWidgets('an audit entry can name a DIFFERENT actor than the sale did',
        (WidgetTester tester) async {
      // The point of reading both: a reconciled or re-billed sale is rung by one
      // person and logged by another, and a ledger that shows only one of them
      // cannot tell those apart.
      await tester.pumpApp(
        home: TransactionsRow(
          sale: _sale(staff: 'Brian'),
          audit: _audit(actor: 'Amina', saleId: 7),
          canSeeSellers: true,
        ),
      );

      expect(find.text(l10n.transactionsSoldBy('Brian')), findsOneWidget);
      expect(find.text(l10n.transactionsAuditBy('Amina')), findsOneWidget);
    });
  });
}
