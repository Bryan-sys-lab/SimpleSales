// The shift screen's LAYOUT, across the matrix that catches what a unit test
// cannot.
//
// This screen used to be untestable because it read the database from
// `initState`. Splitting the reads into `loadShiftLedger` means the presentation
// can now be rendered straight from a constructed value — so the same device ×
// scale × brightness sweep the entry screens get applies here too, on the one
// screen whose numbers are the reason an owner trusts the app.
//
// `loadAppFonts` is not optional: under the default Ahem test font every glyph is
// a fixed em-square, so the 2.0x half of this matrix would pass while a real
// phone overflowed.

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/shift_close_sheet.dart';
import 'package:duka_pos/screens/shift_history_card.dart';
import 'package:duka_pos/screens/shift_screen.dart';
import 'package:duka_pos/screens/shift_till_count_sheet.dart';
import 'package:duka_pos/screens/shift_variance.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A shift that has been open since this morning, with a float and a count that
/// DISAGREES with the ledger.
///
/// The shortage case specifically: it is the widest content the screen can hold
/// (a four-figure figure, a chip, a word, and two buttons) and the one an owner
/// needs to read correctly, so if anything on this screen is going to clip it is
/// this.
Shift _openShift({num float = 5000}) => Shift(
      id: 1,
      staffId: 7,
      staffName: 'Amina',
      startTime: DateTime(2026, 10, 4, 8, 12).toIso8601String(),
      startFloat: Money.fromMajor(float),
    );

/// The shortage case. Built from the catalogue at the point of use rather than
/// cached, because `l10n` is loaded in `setUpAll` and a top-level final would
/// capture it before that has run.
ShiftVariance _shortfall(AppLocalizations l10n) =>
    ShiftVariance.between(l10n, Money.fromMajor(4600), Money.fromMajor(5000));

/// The screen's open-shift card, with both handlers inert.
Widget _openShiftCard(AppLocalizations l10n, {ShiftVariance? variance}) =>
    Scaffold(
      body: OpenShiftCard(
        shift: _openShift(),
        expected: Money.fromMajor(5000),
        variance: variance ?? _shortfall(l10n),
        onCount: () {},
        onClose: () {},
      ),
    );

void main() {
  /// The catalogue the variance words come from.
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1.0, 2.0]) {
      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        final String where = '${device.name} x$scale $brightness';

        testWidgets('the open shift fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: _openShiftCard(l10n),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('open shift card $where');
          tester.expectTapTargetsMeetMinimum(find.byType(Scaffold));
        });

        testWidgets('the uncounted drawer fits $where',
            (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home:
                _openShiftCard(l10n, variance: ShiftVariance.notCounted(l10n)),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('uncounted drawer $where');
        });

        testWidgets('the ledger fits $where, with and without history',
            (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  ShiftHistoryCard(
                    shifts: <Shift>[_openShift()],
                    totalShifts: 41,
                  ),
                  const SizedBox(height: 24),
                  const ReconciliationHistoryCard(
                      reconciliations: <Reconciliation>[]),
                ],
              ),
            ),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('shift history $where');
          // The cap has to be visible, or a 41-row ledger reads as a 1-row one.
          expect(
              find.textContaining('earlier shifts not shown'), findsOneWidget);
        });

        testWidgets('no shift open fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: const Scaffold(
              body: NoShiftCard(canOpen: true, onOpen: _nothing),
            ),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('no shift $where');
          tester.expectTapTargetsMeetMinimum(find.byType(Scaffold));
        });
      }
    }
  }

  group('the variance strip', () {
    testWidgets('says the direction in words, and announces the whole thing',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpApp(
        home: Scaffold(
          body: VarianceStrip(variance: ShiftVariance.notCounted(l10n)),
        ),
      );

      expect(find.text(l10n.varianceNotCounted), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('not been counted')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('puts the figure on its own line, where it cannot be clipped',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      // A five-figure shortage: the widest content the strip can ever hold, on
      // the narrowest phone in the matrix. A `Row` of word + chip + figure fails
      // here, which is the whole reason the figure has its own line.
      await tester.pumpApp(
        home: Scaffold(
          body: VarianceStrip(
            variance: ShiftVariance.between(
              l10n,
              Money.fromMajor(12340),
              Money.fromMajor(25000),
            ),
          ),
        ),
      );
      tester.expectNoOverflow('a five-figure variance on the narrowest phone');
      // `formatMoney` drops the decimals on a whole amount, so the figure on
      // screen is `KSh 12,660` — asserted through the widget's own output rather
      // than a hand-written string, so this cannot drift from the formatter.
      expect(
        find.text(formatMoney(Money.fromMajor(12660))),
        findsOneWidget,
      );
    });
  });

  group('the counting table', () {
    // Nine rows of three columns each is the widest table in the app, and a row
    // that clips does not error — it just stops counting. Every denomination is
    // rendered, because the LAST one is a coin and the first is a note: a table
    // that fits "KSh 1,000" and clips "KSh 1" is exactly the failure.
    for (final Device device in <Device>[Device.compact, Device.small]) {
      for (final double scale in <double>[1.0, 2.0]) {
        testWidgets('every denomination fits ${device.name} x$scale',
            (WidgetTester tester) async {
          tester.useDevice(device);
          final Map<int, TextEditingController> counts =
              <int, TextEditingController>{
            for (final int denomination in kTillDenominations)
              denomination: TextEditingController(text: '12'),
          };
          addTearDown(() {
            for (final TextEditingController c in counts.values) {
              c.dispose();
            }
          });

          await tester.pumpApp(
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  for (int i = 0; i < kTillDenominations.length; i++)
                    TillDenominationRow(
                      denomination: kTillDenominations[i],
                      controller: counts[kTillDenominations[i]]!,
                      value: Money.fromMajor(
                        kTillDenominations[i] * 12,
                      ),
                      showDivider: i != kTillDenominations.length - 1,
                      onChanged: () {},
                    ),
                  TillCountTotal(total: Money.fromMajor(247200)),
                ],
              ),
            ),
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('till count ${device.name} x$scale');
        });
      }
    }

    testWidgets('the running total is announced, not merely redrawn',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpApp(
        home: Scaffold(
          body: TillCountTotal(total: Money.fromMajor(247200)),
        ),
      );

      expect(
        find.bySemanticsLabel(
            'Counted so far ${formatMoney(Money.fromMajor(247200))}'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the closed-shift sentence', () {
    test('a balanced close says so', () {
      expect(
        describeClosedShift(
          l10n,
          ShiftVariance.between(
            l10n,
            Money.fromMajor(5000),
            Money.fromMajor(5000),
          ),
        ),
        contains(l10n.shiftClosedBalanced),
      );
    });

    test('a shortage names the amount and the direction', () {
      final String said = describeClosedShift(
        l10n,
        ShiftVariance.between(
            l10n, Money.fromMajor(4400), Money.fromMajor(5000)),
      );
      expect(said, contains(formatMoney(Money.fromMajor(600))));
      // The English direction word is the copy contract being pinned here: a
      // translator replaces the whole sentence, not one token of it, so the
      // assertion that matters is that the DIRECTION is spelled out rather than
      // carried by a minus sign.
      expect(said, contains('short'));
      expect(said, isNot(contains('-600')));
    });

    test('an overage names the amount and the direction', () {
      expect(
        describeClosedShift(
          l10n,
          ShiftVariance.between(
              l10n, Money.fromMajor(5600), Money.fromMajor(5000)),
        ),
        allOf(contains(formatMoney(Money.fromMajor(600))), contains('over')),
      );
    });
  });
}

void _nothing() {}
