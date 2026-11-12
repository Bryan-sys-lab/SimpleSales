// Switching profiles must empty session-scoped cart state. SellScreen clears
// its cart through SessionRefresh.clearForSession, which fires on the
// sessionGeneration bump that setShopProfile triggers. This probe mirrors that
// mechanism exactly (same mixin, same contract) so the assertion is reliable
// without booting the whole till UI.

import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/session_refresh_mixin.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// A SessionRefresh consumer that holds session-scoped "cart" items.
class _CartProbe extends StatefulWidget {
  const _CartProbe();

  @override
  State<_CartProbe> createState() => _CartProbeState();
}

class _CartProbeState extends State<_CartProbe>
    with SessionRefresh<_CartProbe> {
  final List<String> _cart = <String>[];
  int clearForSessionCalls = 0;

  void add(String item) => setState(() => _cart.add(item));

  int get cartLength => _cart.length;

  @override
  void clearForSession() {
    clearForSessionCalls++;
    _cart.clear();
  }

  @override
  Future<void> reloadFromSession() async {}

  @override
  Widget build(BuildContext context) =>
      Text(cartLength == 0 ? 'empty' : '$cartLength item(s)');
}

Future<void> _pumpProbe(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>.value(value: state),
      ],
      child: MaterialApp(
        theme: buildDukaLightTheme(),
        localizationsDelegates: const [],
        supportedLocales: const <Locale>[Locale('en')],
        locale: const Locale('en'),
        home: const _CartProbe(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'switching profiles clears the session-scoped cart',
    (WidgetTester tester) async {
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      state.setShopProfile(ShopProfile.duka);

      await _pumpProbe(tester, state);

      expect(find.text('empty'), findsOneWidget);
      expect(find.text('1 item(s)'), findsNothing);

      // Add an item to the session-scoped cart.
      final _CartProbeState probe = tester.state(find.byType(_CartProbe));
      probe.add('Kenyatta bread');
      await tester.pump();
      expect(find.text('1 item(s)'), findsOneWidget);

      // Capture the session before the switch.
      final int before = state.sessionGeneration;

      // Switch profile: SessionRefresh.clearForSession empties the cart.
      state.setShopProfile(ShopProfile.open);
      await tester.pumpAndSettle();

      expect(state.sessionGeneration, greaterThan(before),
          reason: 'setShopProfile must advance the session generation');
      expect(probe.clearForSessionCalls, 1,
          reason: 'clearForSession must fire on the profile switch');
      expect(find.text('empty'), findsOneWidget);
      expect(find.text('1 item(s)'), findsNothing,
          reason: 'the cart kept an item after the profile switch');

      // Switch back: clears again (still empty).
      state.setShopProfile(ShopProfile.duka);
      await tester.pumpAndSettle();
      expect(probe.clearForSessionCalls, 2);
      expect(find.text('empty'), findsOneWidget);
    },
  );

  testWidgets(
    'signing in under a new profile starts with an empty cart',
    (WidgetTester tester) async {
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      state.setShopProfile(ShopProfile.duka);

      await _pumpProbe(tester, state);
      final _CartProbeState probe = tester.state(find.byType(_CartProbe));
      probe.add('Kenyatta bread');
      await tester.pump();
      expect(find.text('1 item(s)'), findsOneWidget);

      // A fresh sign-in under a different profile must not see the old cart.
      state.signOut();
      state.signIn('Test Owner 2', asOwner: true);
      state.setShopProfile(ShopProfile.open);
      await tester.pumpAndSettle();
      expect(find.text('empty'), findsOneWidget);
    },
  );
}
