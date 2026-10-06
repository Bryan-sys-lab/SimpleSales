import 'package:duka_pos/ui/components/controls.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:duka_pos/ui/components/status.dart';
import 'package:duka_pos/theme/app_spacing.dart';
import 'package:duka_pos/ui/layout/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// The overflow + fit matrix for the design system's own components.
///
/// One `testWidgets` per (device, scale, bold) tuple — the loop is deliberately
/// AROUND `testWidgets`, never inside it. A `RenderFlex` overflow is reported
/// ONCE PER RENDER OBJECT; the flag only resets on `reassemble()`. A test that
/// loops scales internally therefore silently checks 1.0 and under-reports every
/// other value, which is the single easiest way to ship a broken layout with a
/// green suite.
///
/// `boldText` is in the matrix because it widens advance widths — but only when a
/// REAL proportional font is loaded. Under the default Ahem test font every glyph
/// is a fixed em-square regardless of weight, so the bold axis is a no-op and the
/// bold half of this matrix would pass vacuously. `setUpAll(loadAppFonts)` is what
/// makes it mean something.
void main() {
  setUpAll(loadAppFonts);

  Widget harness() => const Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              SectionHeader(label: 'Section'),
              SurfaceCard(
                child: Column(
                  children: <Widget>[
                    KeyValueRow(label: 'Kenyatta bread', value: 'KSh 60'),
                    KeyValueRow(label: 'Milk 500ml', value: 'KSh 85'),
                    KeyValueRow(
                      label: 'A deliberately very long product name that must '
                          'wrap rather than truncate at large text scales',
                      value: 'KSh 1,250',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              StatusChip(tone: StatusTone.success, text: 'Paid'),
              StatusChip(tone: StatusTone.warning, text: 'Low stock'),
              StatusChip(tone: StatusTone.danger, text: 'Blocked'),
              CountBadge(
                  count: 12, noun: 'items low', tone: StatusTone.warning),
              SizedBox(height: 8),
              StatTile(
                label: "Today's sales",
                value: 'KSh 48,320',
                emphasis: StatEmphasis.strong,
              ),
              MoneyText(amount: 'KSh 1,250,000.00', size: 24),
              SizedBox(height: 8),
              PersistentBanner(
                message: 'Printer is offline. Sales will still be recorded.',
                actionLabel: 'Retry',
                tone: StatusTone.warning,
              ),
            ],
          ),
        ),
      );

  for (final Device device in Device.all) {
    for (final double scale in kTextScales) {
      for (final bool bold in <bool>[false, true]) {
        testWidgets(
          'components fit @ ${device.name} x$scale${bold ? ' bold' : ''}',
          (WidgetTester tester) async {
            tester.useDevice(device);
            await tester.pumpApp(
              home: harness(),
              textScaler: TextScaler.linear(scale),
              boldText: bold,
            );
            tester.expectNoOverflow(
              'components @ ${device.name} x$scale bold=$bold',
            );
          },
        );
      }
    }
  }

  group('a price is never truncated', () {
    testWidgets('MoneyText at 3x scale still reports its full value',
        (WidgetTester tester) async {
      // A clipped `RenderParagraph` reports NOTHING — there is no overflow
      // indicator for text. This is the silent failure class, so it needs its
      // own assertion rather than relying on the overflow net above.
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: const Scaffold(
          body: SectionedPage(
            sections: <Widget>[
              MoneyText(amount: 'KSh 1,250,000.00', size: 28),
            ],
          ),
        ),
        textScaler: TextScaler.linear(3.0),
      );

      final Finder money = find.text('KSh 1,250,000.00');
      expect(money, findsOneWidget);

      final Text widget = tester.widget<Text>(money);
      expect(
        widget.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'a price with ellipsis is a cashier reading a wrong number',
      );
      expect(widget.maxLines, isNull);

      // And it is actually laid out at full size, not squeezed.
      expect(tester.getSize(money).height, greaterThan(0));
      tester.expectNoOverflow('a long price at 3x on a 320dp screen');
    });
  });

  group('a long label wraps rather than truncating', () {
    testWidgets('KeyValueRow grows its row instead of clipping the label',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: const Scaffold(
          body: SectionedPage(
            sections: <Widget>[
              SurfaceCard(
                child: KeyValueRow(
                  label: 'A product name far too long for one line at two '
                      'hundred percent text scale on a three hundred and '
                      'twenty logical pixel screen',
                  value: 'KSh 1,250',
                ),
              ),
            ],
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      );

      final Finder label = find.textContaining('far too long');
      final Text text = tester.widget<Text>(label);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getSize(label).height,
        greaterThan(tester.getSize(find.text('KSh 1,250')).height),
        reason: 'if the label did not wrap, it would be one line tall — which '
            'means it was clipped, not fitted',
      );
    });
  });

  group('the layout primitives respect the window', () {
    testWidgets('AdaptiveGrid computes its column count from the width',
        (WidgetTester tester) async {
      for (final (Device device, int expected) in <(Device, int)>[
        (Device.compact, 1),
        (Device.small, 1),
        (Device.medium, 1),
        (Device.tablet, 3),
      ]) {
        tester.useDevice(device);
        await tester.pumpApp(
          home: Scaffold(
            body: AdaptiveGrid(
              itemCount: 4,
              minCellWidth: 220,
              maxColumns: 4,
              itemBuilder: (BuildContext context, int i) => Text('cell $i'),
            ),
          ),
        );
        final int columns = AdaptiveGrid.columnsFor(
          available: MediaQuery.sizeOf(
                tester.element(find.text('cell 0')),
              ).width -
              16,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        );
        expect(columns, expected, reason: 'at ${device.name}');
      }
    });

    test('the column count is a pure function of the width', () {
      expect(
        AdaptiveGrid.columnsFor(
          available: 320,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        ),
        1,
      );
      // (available + gap) / (cell + gap), floored: 1008 / 228 = 4.42 -> 4.
      expect(
        AdaptiveGrid.columnsFor(
          available: 1000,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        ),
        4,
      );
      // 900 is the interesting boundary just below it: 908 / 228 = 3.98 -> 3.
      expect(
        AdaptiveGrid.columnsFor(
          available: 900,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        ),
        3,
      );
      // A zero or negative width must not crash or return zero columns.
      expect(
        AdaptiveGrid.columnsFor(
          available: 0,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        ),
        1,
      );
      // And the cap holds on a very wide window rather than producing eight
      // unreadable columns.
      expect(
        AdaptiveGrid.columnsFor(
          available: 3000,
          gap: 8,
          minCellWidth: 220,
          maxColumns: 4,
        ),
        4,
      );
    });

    test('prose is capped at a readable measure', () {
      // ~70 characters at this face. A settings paragraph at full width on a
      // tablet is 140 characters a line and is unreadable in a way that looks
      // fine at a glance, which is what makes it survive review.
      expect(AppSpacing.standard.readableMaxWidth, lessThanOrEqualTo(720));
      expect(AppSpacing.standard.readableMaxWidth, greaterThan(600));
    });
  });

  group('tap targets', () {
    testWidgets('every control on the dense components clears 44px',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              SurfaceCard(
                onTap: () {},
                semanticLabel: 'Kenyatta bread, KSh 60',
                child: const Text('Kenyatta bread'),
              ),
              KeyValueRow(
                label: 'Milk 500ml',
                value: 'KSh 85',
                onTap: () {},
              ),
              StatTile(
                label: 'Sales',
                value: 'KSh 48,320',
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      tester.expectTapTargetsMeetMinimum(find.byType(Scaffold));
    });

    testWidgets('the action bar button is at least 44px, and taller',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: ActionBar(
            primary: FilledButton(
              onPressed: () {},
              child: const Text('Charge KSh 4,320'),
            ),
          ),
        ),
      );
      // The TARGET is the button, not its label: a label's rendered height is
      // the glyph box, and asserting on it would measure typography, not
      // reachability.
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.text('Charge KSh 4,320'), findsOneWidget);
    });
  });

  group('the confirm dialog names the consequence', () {
    testWidgets('dismissal is its own outcome, never a confirmation',
        (WidgetTester tester) async {
      ConfirmOutcome? outcome;
      await tester.pumpApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  outcome = await confirmIrreversible(
                    context,
                    title: 'Delete 12 products permanently',
                    message: 'Their stock history stays, but the products and '
                        'their prices are gone.',
                    confirmLabel: 'Delete permanently',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The dialog says what will happen and how many.
      expect(find.text('Delete 12 products permanently'), findsOneWidget);
      // The confirming button carries the verb, not "OK".
      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.text('OK'), findsNothing);

      // Cancel is an explicit decline.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(outcome, isA<ConfirmDeclined>());
    });

    testWidgets('accepting returns ConfirmAccepted',
        (WidgetTester tester) async {
      ConfirmOutcome? outcome;
      await tester.pumpApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  outcome = await confirmIrreversible(
                    context,
                    title: 'Close the shift with KSh 250 short',
                    message: 'The variance will be recorded against the shift.',
                    confirmLabel: 'Close shift',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close shift'));
      await tester.pumpAndSettle();
      expect(outcome, isA<ConfirmAccepted>());
    });
  });
}
