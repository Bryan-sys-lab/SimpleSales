// Routing tests for the top-level stage decision.
//
// The bug this file exists to prevent: the first-run walkthrough used to be
// evaluated before the sign-in check, so on any till that had not dismissed it
// — a newly provisioned one, or one whose workspace had been switched — every
// user was held on the welcome screens and could never reach the PIN pad. A
// cashier with a valid PIN was stuck behind "create an account".
//
// resolveAppStage is pure, so this is asserted directly rather than inferred
// from a pumped widget tree that would need a live database.

import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/app_stage.dart';

void main() {
  group('resolveAppStage', () {
    test('reports loading before anything else is known', () {
      expect(
        resolveAppStage(
          isLoading: true,
          hasDatabaseFailure: true,
          hasShop: false,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
        ),
        AppStage.loading,
      );
    });

    test('reports a database failure ahead of every other state', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: true,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: true,
        ),
        AppStage.databaseFailed,
      );
    });

    test('a till with no shop goes to setup, not to a login attempt', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: false,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
        ),
        AppStage.settingUp,
      );
    });

    test('an existing shop with nobody signed in reaches the PIN pad', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: true,
        ),
        AppStage.signingIn,
      );
    });

    // The regression itself: a shop that exists but has not seen the
    // walkthrough must still offer sign-in. Checking onboarding first is what
    // stranded cashiers.
    test('an undismissed walkthrough does not block sign-in', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
        ),
        AppStage.signingIn,
        reason: 'sign-in must outrank the optional walkthrough',
      );
    });

    test('the walkthrough appears only after a successful sign-in', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: false,
        ),
        AppStage.onboarding,
      );
    });

    test('a signed-in user past the walkthrough gets the shop', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: true,
        ),
        AppStage.ready,
      );
    });

    // Signing out must return to the PIN pad even mid-walkthrough, so a till
    // cannot be left showing shop screens to the next person who picks it up.
    // signOut() also drops the role to cashier, so isAdmin is false after it.
    test('signing out of a walkthrough session returns to the PIN pad', () {
      final beforeSignOut = resolveAppStage(
        isLoading: false,
        hasDatabaseFailure: false,
        hasShop: true,
        isSignedIn: true,
        isAdmin: true,
        onboardingComplete: false,
      );
      final afterSignOut = resolveAppStage(
        isLoading: false,
        hasDatabaseFailure: false,
        hasShop: true,
        isSignedIn: false,
        isAdmin: false,
        onboardingComplete: false,
      );

      expect(beforeSignOut, AppStage.onboarding);
      expect(afterSignOut, AppStage.signingIn);
    });

    // The walkthrough's copy is written to whoever set the shop up ("the email
    // you entered", "add cashiers in Settings"), so a cashier must go straight
    // to the shop rather than be shown admin setup guidance — or be made to
    // wait for it on a till where the admin has not signed in yet.
    test('a cashier is never shown the admin walkthrough', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: false,
          onboardingComplete: false,
        ),
        AppStage.ready,
        reason: 'walkthrough is admin-only and must not gate a cashier',
      );
    });

    test('a cashier still reaches the PIN pad on an undismissed till', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: false,
          isAdmin: false,
          onboardingComplete: false,
        ),
        AppStage.signingIn,
      );
    });

    // A shop where only the owner has ever signed in: the admin is offered the
    // walkthrough once, and finishing it clears it for everyone.
    test('the admin alone is offered the walkthrough on a fresh till', () {
      final asOwner = resolveAppStage(
        isLoading: false,
        hasDatabaseFailure: false,
        hasShop: true,
        isSignedIn: true,
        isAdmin: true,
        onboardingComplete: false,
      );
      final asCashier = resolveAppStage(
        isLoading: false,
        hasDatabaseFailure: false,
        hasShop: true,
        isSignedIn: true,
        isAdmin: false,
        onboardingComplete: false,
      );

      expect(asOwner, AppStage.onboarding);
      expect(asCashier, AppStage.ready);
    });
  });
}