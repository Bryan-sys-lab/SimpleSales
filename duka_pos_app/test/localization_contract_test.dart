import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'support/harness.dart';

void main() {
  test('the production catalogue exposes English and Swahili', () {
    expect(
      AppLocalizations.supportedLocales,
      containsAll(<Locale>[const Locale('en'), const Locale('sw')]),
    );
    expect(AppLocalizations.delegate.isSupported(const Locale('sw')), isTrue);
  });

  test('Swahili translates the shell and shared actions', () async {
    final AppLocalizations sw =
        await AppLocalizations.delegate.load(const Locale('sw'));

    expect(sw.navDashboard, 'Dashibodi');
    expect(sw.navMore, 'Zaidi');
    expect(sw.shellCreditMenuLabel, 'Wateja wa mkopo');
    expect(sw.actionSave, 'Hifadhi');
    expect(sw.errorOffline, contains('intaneti'));
  });

  testWidgets('Swahili shell copy survives a narrow 200% text viewport',
      (tester) async {
    await tester.pumpApp(
      locale: const Locale('sw'),
      surfaceSize: 320.0,
      textScaler: TextScaler.linear(2),
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.navDashboard),
              actions: <Widget>[
                IconButton(
                  onPressed: () {},
                  tooltip: l10n.shellCreditMenuLabel,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  tooltip: l10n.shellAccountMenuLabel,
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            ),
            body: Center(child: Text(l10n.marketplaceDescription)),
            bottomNavigationBar: NavigationBar(
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  label: l10n.navDashboardShort,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.more_horiz),
                  label: l10n.navMoreShort,
                ),
              ],
            ),
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
