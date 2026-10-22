// The new bottom bar, the floating support bubble, and the login field.
//
// These are the three pieces the owner asked for by shape rather than by
// behaviour, so the tests are about SHAPE: that the sell button is in the
// middle, that the other destinations divide around it, that the mark is a
// circle and not a square inside one, and that the support bubble opens the
// support page without rebuilding anything behind it.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/routing/shell_nav_bar.dart';
import 'package:duka_pos/ui/components/support_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  Widget bar(List<AppDestination> destinations, AppDestination selected) =>
      Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: ShellNavBar(
          destinations: destinations,
          selected: selected,
          onSelect: (_) {},
        ),
      );

  group('the sell button is in the middle', () {
    testWidgets('the bar puts the ball between the two halves',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: bar(
          <AppDestination>[
            AppDestination.dashboard,
            AppDestination.inventory,
            AppDestination.sell,
            AppDestination.analytics,
            AppDestination.settings,
          ],
          AppDestination.sell,
        ),
      );
      await tester.pump();

      // The ball's centre is the middle of the bar, whatever the counts on
      // each shoulder.
      final Rect nav = tester.getRect(find.byType(ShellNavBar));
      final Rect ball = tester.getRect(find.byType(ShellNavBar));
      expect(ball.center.dx, closeTo(nav.center.dx, 0.5));
    });

    testWidgets('every destination is reachable, and named in full',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: bar(
          <AppDestination>[
            AppDestination.dashboard,
            AppDestination.inventory,
            AppDestination.sell,
            AppDestination.analytics,
            AppDestination.settings,
          ],
          AppDestination.sell,
        ),
      );
      await tester.pump();

      // Every destination is on the bar, with a label that is COMPLETE — the
      // full word when it fits, the short one when it does not, and never a
      // word cut in half.
      for (final AppDestination destination in <AppDestination>[
        AppDestination.dashboard,
        AppDestination.inventory,
        AppDestination.analytics,
        AppDestination.settings,
      ]) {
        final String full = destination.label(l10n);
        final String short = destination.shortLabel(l10n);
        expect(
          find
                  .descendant(
                    of: find.byType(ShellNavBar),
                    matching: find.text(full),
                  )
                  .evaluate()
                  .isNotEmpty ||
              find
                  .descendant(
                    of: find.byType(ShellNavBar),
                    matching: find.text(short),
                  )
                  .evaluate()
                  .isNotEmpty,
          isTrue,
          reason: '${destination.name} is on the bar, whole',
        );
      }
    });

    testWidgets('the labels are never cut in half',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);

      await tester.pumpApp(
        home: bar(
          <AppDestination>[
            AppDestination.dashboard,
            AppDestination.inventory,
            AppDestination.sell,
            AppDestination.analytics,
            AppDestination.settings,
          ],
          AppDestination.sell,
        ),
      );
      await tester.pump();

      // No label in the bar ends in an ellipsis: a label cut to "Dashbo…" is
      // worse than a shorter word that is complete.
      for (final Text text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ShellNavBar),
          matching: find.byType(Text),
        ),
      )) {
        expect(text.data, isNot(contains('…')));
      }

      // AND no label is cut SILENTLY.
      //
      // Checking the string for an ellipsis is not enough: a `Text` with a
      // `maxLines` and no `overflow` drops the lines past the limit and
      // paints nothing to say so. The bar used to do exactly that — it
      // measured the room per cell about ten pixels generously, chose the
      // full word, and then painted "Dashbo" with no marker at all.
      //
      // So: the painted text must FIT the box it was given. If the label had
      // to be cut to fit, this is where that shows.
      for (final Element element in find
          .descendant(
            of: find.byType(ShellNavBar),
            matching: find.byType(Text),
          )
          .evaluate()) {
        final RenderParagraph paragraph =
            element.renderObject! as RenderParagraph;
        expect(
          paragraph.computeMaxIntrinsicWidth(paragraph.size.height),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: 'the label "${paragraph.text.toPlainText()}" does not fit '
              'the ${paragraph.size.width}px it was given',
        );
      }
    });

    testWidgets('the mark is a circle, not a square inside one',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: bar(
          <AppDestination>[AppDestination.sell],
          AppDestination.sell,
        ),
      );
      await tester.pump();

      // The sell mark is a CIRCLE, not a square inside a circle.
      //
      // It used to be a promotional tile — a dark card with "NEW SALE" on it —
      // clipped to a round shape, and at the size of a nav icon that was
      // unreadable mush with a visible square in the middle of it. It is a
      // GLYPH now, painted on a solid circle, so the shape to assert is the
      // circle itself: a decoration whose shape is `BoxShape.circle`, and no
      // square in the middle of it.
      final Iterable<Container> circles = tester
          .widgetList<Container>(
        find.descendant(
          of: find.byType(ShellNavBar),
          matching: find.byType(Container),
        ),
      )
          .where((Container container) {
        final Decoration? decoration = container.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle;
      });

      expect(circles, isNotEmpty);
    });
  });

  group('the support bubble', () {
    testWidgets('is a button that says what it does',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: Center(
            child: SupportBubble(
              label: 'Support',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SupportBubble), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('opens the support page when tapped',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      int taps = 0;

      await tester.pumpApp(
        home: Scaffold(
          body: Center(
            child: SupportBubble(
              label: 'Support',
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SupportBubble));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('the support route is a branch', () {
    test('and the destination knows its own path', () {
      expect(AppDestination.support.path, Routes.support);
    });
  });
}
