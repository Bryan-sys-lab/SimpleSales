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
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/services/app_state.dart';

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

    test('a till with no shop goes to the chooser, not straight to setup', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: false,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
        ),
        AppStage.chooser,
      );
    });

    test('a till with no shop still reaches setup when the chooser asks for it',
        () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: false,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
          chooserIntent: AppChooserIntent.setUp,
        ),
        AppStage.settingUp,
      );
    });

    test('a till with no shop reaches setup for add-shop intent too', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: false,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: false,
          chooserIntent: AppChooserIntent.addShop,
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

  group('AppStageController', () {
    test('choose updates intent and notifies listeners', () {
      final AppState state = AppState();
      final AppStageController controller = AppStageController(state);

      expect(controller.intent, AppChooserIntent.signIn);
      expect(controller.snapshot.stage, AppStage.loading);

      controller.choose(AppChooserIntent.setUp);
      expect(controller.intent, AppChooserIntent.setUp);

      controller.choose(AppChooserIntent.addShop);
      expect(controller.intent, AppChooserIntent.addShop);

      controller.choose(AppChooserIntent.signIn);
      expect(controller.intent, AppChooserIntent.signIn);
    });

    test('choose notifies on every call, even for the same intent', () {
      final AppState state = AppState();
      final AppStageController controller = AppStageController(state);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.choose(AppChooserIntent.signIn);
      expect(notifyCount, 1, reason: 'first choose should notify');

      controller.choose(AppChooserIntent.signIn);
      expect(notifyCount, 2,
          reason: 'choosing the same intent again should notify');
    });
  });

  group('the permissions step', () {
    // The step that asks for the camera and for Bluetooth, once, after the
    // walkthrough.
    //
    // The rules it has to keep, all of which are about NOT stranding anybody:
    // a cashier is never routed into it, a sign-out is never held on it, and
    // an owner who has already answered is never asked again.

    test('comes after the walkthrough, not before it', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: false,
          permissionsAsked: false,
        ),
        AppStage.onboarding,
        reason: 'the walkthrough is guidance and comes first; the permissions '
            'step asks about the till, and the till is not set up until the '
            'owner has been walked through',
      );
    });

    test('is offered to an owner who has not been asked', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: true,
          permissionsAsked: false,
        ),
        AppStage.permissions,
      );
    });

    test('is never offered to a cashier', () {
      // The copy is addressed to whoever set the shop up. A cashier must go
      // straight to the shop, or they are held on a screen about a till that
      // is not theirs.
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: false,
          onboardingComplete: true,
          permissionsAsked: false,
        ),
        AppStage.ready,
      );
    });

    test('is asked once: an owner who has answered is not asked again', () {
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: true,
          isAdmin: true,
          onboardingComplete: true,
          permissionsAsked: true,
        ),
        AppStage.ready,
      );
    });

    test('never holds a signed-out user on it', () {
      // The sign-in check outranks everything that is not the boot gate. A
      // cashier with a valid PIN must be able to reach it whatever else the
      // till has not done yet.
      expect(
        resolveAppStage(
          isLoading: false,
          hasDatabaseFailure: false,
          hasShop: true,
          isSignedIn: false,
          isAdmin: true,
          onboardingComplete: true,
          permissionsAsked: false,
        ),
        AppStage.signingIn,
      );
    });
  });
}
