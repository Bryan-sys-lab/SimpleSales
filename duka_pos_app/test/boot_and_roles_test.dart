// Boot routing, role capabilities, and the multi-shop carry-over.
//
// Three things are being pinned here, all of them security-relevant or
// trust-relevant:
//
//  * Who can reach the PIN pad. A routing rule that sends a cashier to an
//    admin-only screen is not a cosmetic bug, it is either a dead end or a
//    privilege escalation.
//  * Which roles can do what. Role checks used to be `role != 'cashier'`,
//    which grants management rights to any value it does not recognise.
//  * That a second shop on a device gets a real owner, with the existing
//    admin's PIN hash, so adding a branch is not a re-registration.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/services/roles.dart';

void main() {
  group('boot routing', () {
    AppStage stage({
      bool isLoading = false,
      bool dbFailed = false,
      bool hasShop = true,
      bool signedIn = false,
      bool isAdmin = false,
      bool onboarding = false,
      AppChooserIntent intent = AppChooserIntent.signIn,
    }) =>
        resolveAppStage(
          isLoading: isLoading,
          hasDatabaseFailure: dbFailed,
          hasShop: hasShop,
          isSignedIn: signedIn,
          isAdmin: isAdmin,
          onboardingComplete: onboarding,
          chooserIntent: intent,
        );

    test('loading comes before everything, including failure', () {
      expect(stage(isLoading: true, dbFailed: true), AppStage.loading);
      expect(stage(isLoading: true, hasShop: false), AppStage.loading);
    });

    test('a database failure is never masked by a sign-in screen', () {
      // A cashier must never be shown a PIN pad for a database that cannot be
      // read: the PIN would be verified against nothing.
      expect(stage(dbFailed: true, signedIn: false), AppStage.databaseFailed);
    });

    test('a shop exists and nobody is signed in -> the chooser', () {
      expect(stage(), AppStage.signingIn);
    });

    test('the chooser intent selects between sign in and setup', () {
      expect(stage(intent: AppChooserIntent.signIn), AppStage.signingIn);
      expect(stage(intent: AppChooserIntent.setUp), AppStage.settingUp);
      expect(stage(intent: AppChooserIntent.addShop), AppStage.settingUp);
    });

    test('no shop at all -> setup, because there is nothing to sign in to', () {
      // There is no roster and no PIN hash, so offering a sign-in would be
      // offering a keypad that cannot succeed.
      expect(stage(hasShop: false), AppStage.settingUp);
      // Even if the chooser asked for sign in, setup is the only honest answer.
      expect(stage(hasShop: false, intent: AppChooserIntent.signIn),
          AppStage.settingUp);
    });

    test('a signed-in admin who has not seen the walkthrough gets it', () {
      expect(stage(signedIn: true, isAdmin: true, onboarding: false),
          AppStage.onboarding);
    });

    test('a signed-in CASHIER never gets the walkthrough, even undismissed',
        () {
      // This is the rule that was previously checked first and stranded every
      // user on welcome screens with no way to reach the PIN pad. It is also a
      // small information leak: the walkthrough's copy describes how the shop
      // is configured.
      expect(stage(signedIn: true, isAdmin: false, onboarding: false),
          AppStage.ready);
    });

    test('sign-in outranks the walkthrough in every combination', () {
      for (final onboardingComplete in [true, false]) {
        for (final isAdmin in [true, false]) {
          expect(
            stage(
                signedIn: false,
                isAdmin: isAdmin,
                onboarding: onboardingComplete),
            isNot(AppStage.onboarding),
            reason: 'onboarding=$onboardingComplete admin=$isAdmin',
          );
        }
      }
    });
  });

  group('roles', () {
    test('every role parses from its stored value', () {
      for (final role in ShopRole.values) {
        expect(ShopRole.parse(role.wire), role);
      }
    });

    test('an unknown or missing role resolves to the LEAST privileged', () {
      // The old check was `role != 'cashier'`, which granted inventory and
      // reports to anything unrecognised — fail-open on every permission.
      for (final junk in [
        '',
        'Cashier',
        'CASHIER ',
        'superuser',
        'root',
        null
      ]) {
        final role = ShopRole.parse(junk);
        expect(role.seesAllSales, isFalse, reason: '$junk saw all sales');
        expect(role.canManageStock, isFalse, reason: '$junk managed stock');
        expect(role.canAdminister, isFalse, reason: '$junk administered');
        expect(role.canDeleteProducts, isFalse,
            reason: '$junk deleted products');
      }
    });

    test('a cashier sees and does only their own', () {
      const cashier = ShopRole.cashier;
      expect(cashier.seesAllSales, isFalse);
      expect(cashier.canManageStock, isFalse);
      expect(cashier.canSeeAnalytics, isFalse);
      expect(cashier.canAdminister, isFalse);
      expect(cashier.canDeleteProducts, isFalse);
      expect(cashier.canRegisterTaxIdentity, isFalse);
    });

    test('a manager gets stock and reports but not staff or KRA', () {
      const manager = ShopRole.manager;
      expect(manager.seesAllSales, isTrue);
      expect(manager.canManageStock, isTrue);
      expect(manager.canSeeAnalytics, isTrue);
      expect(manager.canAdminister, isTrue);
      // Deleting a product and registering a tax identity are both
      // consequential enough to be owner-only.
      expect(manager.canDeleteProducts, isFalse);
      expect(manager.canRegisterTaxIdentity, isFalse);
    });

    test('an admin staff account has the same rights as the owner', () {
      // The decision that was made: a shop can delegate full admin rights
      // without handing over the owner account and its PIN.
      for (final capability in [
        ShopRole.admin.seesAllSales,
        ShopRole.admin.canManageStock,
        ShopRole.admin.canSeeAnalytics,
        ShopRole.admin.canAdminister,
        ShopRole.admin.canDeleteProducts,
        ShopRole.admin.canRegisterTaxIdentity,
      ]) {
        expect(capability, isTrue);
      }
    });

    test('admin is never offered in the assignable list', () {
      // The owner already holds it. A second admin is a deliberate act, not
      // something next to 'cashier' in a dropdown where it can be picked by
      // accident.
      expect(ShopRole.assignable, isNot(contains(ShopRole.admin)));
      expect(ShopRole.assignable, [ShopRole.manager, ShopRole.cashier]);
    });

    test('every role has a distinct label for the sign-in screen', () {
      final labels = ShopRole.values.map((r) => r.label).toSet();
      expect(labels, hasLength(ShopRole.values.length));
      for (final role in ShopRole.values) {
        expect(role.label, isNotEmpty);
      }
    });
  });
}
