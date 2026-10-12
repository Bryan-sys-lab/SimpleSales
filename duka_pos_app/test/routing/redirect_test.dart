import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The router's guard, tested as a PURE function.
///
/// No widget tree, no database, no booted app: four booleans and a path in, a
/// path or `null` out. That is the whole reason the guard was extracted from
/// `RootRouter`'s `switch` — the security-relevant ordering ("a cashier must
/// always be able to reach the PIN pad") is now assertable in a millisecond
/// instead of by reading a widget's `build` method and hoping.
AppStageSnapshot snapshot({
  AppStage stage = AppStage.ready,
  bool canManageStock = true,
  bool isAdmin = true,
}) =>
    AppStageSnapshot(
      stage: stage,
      canManageStock: canManageStock,
      isAdmin: isAdmin,
    );

String? guard(AppStage stage, String location,
        {bool canManageStock = true, bool isAdmin = true}) =>
    appRedirect(
      snapshot: snapshot(
        stage: stage,
        canManageStock: canManageStock,
        isAdmin: isAdmin,
      ),
      location: location,
    );

void main() {
  group('the boot gate outranks everything', () {
    test('a deep link to the dashboard while loading lands on the splash', () {
      expect(guard(AppStage.loading, Routes.dashboard), Routes.splash);
    });

    test('a deep link to the till while loading lands on the splash', () {
      expect(guard(AppStage.loading, Routes.sell), Routes.splash);
    });

    test('a broken database lands on recovery, whatever was requested', () {
      expect(guard(AppStage.databaseFailed, Routes.dashboard), Routes.recovery);
      expect(guard(AppStage.databaseFailed, Routes.login), Routes.recovery);
      expect(guard(AppStage.databaseFailed, Routes.splash), Routes.recovery);
    });
  });

  group('a signed-out session can only reach the door', () {
    test('no shop yet lands on setup', () {
      expect(guard(AppStage.settingUp, '/anything'), Routes.setup);
      expect(guard(AppStage.settingUp, Routes.setup), isNull);
    });

    test('a shop with nobody signed in lands on the chooser', () {
      expect(guard(AppStage.signingIn, Routes.dashboard), Routes.welcome);
      expect(guard(AppStage.signingIn, Routes.settings), Routes.welcome);
      expect(guard(AppStage.signingIn, Routes.welcome), isNull);
    });

    test('THE rule: a deep link can never reach the shop while signed out', () {
      for (final String path in <String>[
        Routes.dashboard,
        Routes.sell,
        Routes.inventory,
        Routes.analytics,
        Routes.settings,
        Routes.shift,
        Routes.reports,
        Routes.taxSettings,
      ]) {
        expect(
          guard(AppStage.signingIn, path),
          Routes.welcome,
          reason: 'a signed-out user reached $path',
        );
      }
    });
  });

  group('a signed-in session cannot stay on a door', () {
    for (final String door in <String>[
      Routes.splash,
      Routes.recovery,
      Routes.welcome,
      Routes.login,
      Routes.setup,
    ]) {
      test('$door redirects home', () {
        expect(guard(AppStage.ready, door), Routes.dashboard);
      });
    }

    test('but the shell paths are allowed', () {
      for (final String path in <String>[
        Routes.dashboard,
        Routes.sell,
        Routes.inventory,
        Routes.analytics,
        Routes.settings,
      ]) {
        expect(guard(AppStage.ready, path), isNull);
      }
    });
  });

  group('the walkthrough is guidance, not a gate', () {
    test('an admin who has not seen it is held on the walkthrough', () {
      expect(guard(AppStage.onboarding, Routes.dashboard), Routes.onboarding);
      expect(guard(AppStage.onboarding, Routes.onboarding), isNull);
    });

    test('a cashier is never held on the admin-only walkthrough', () {
      // This is the bug the ordering comment describes: checking the walkthrough
      // before authentication stranded every user, cashier included, on the
      // welcome screens of any till whose walkthrough had not been dismissed.
      expect(
        guard(AppStage.onboarding, Routes.sell,
            canManageStock: false, isAdmin: false),
        Routes.dashboard,
      );
    });
  });

  group('role gating on the branch itself', () {
    test('a cashier deep-linked to inventory is sent to the dashboard', () {
      expect(
        guard(AppStage.ready, Routes.inventory, canManageStock: false),
        Routes.dashboard,
      );
    });

    test('a cashier deep-linked to analytics is sent to the dashboard', () {
      expect(
        guard(AppStage.ready, Routes.analytics, canManageStock: false),
        Routes.dashboard,
      );
    });

    test('a cashier can reach their own shift screen for reconciliation', () {
      expect(
        guard(AppStage.ready, Routes.shift, canManageStock: false),
        isNull,
      );
    });

    test('a cashier deep-linked to reports is sent to the dashboard', () {
      expect(
        guard(AppStage.ready, Routes.reports, canManageStock: false),
        Routes.dashboard,
      );
    });

    test('a non-admin deep-linked to settings is sent to the dashboard', () {
      expect(
        guard(AppStage.ready, Routes.settings, isAdmin: false),
        Routes.dashboard,
      );
    });

    test('a non-admin deep-linked to tax settings is sent to the dashboard',
        () {
      expect(
        guard(AppStage.ready, Routes.taxSettings, isAdmin: false),
        Routes.dashboard,
      );
    });

    test('a manager who is not the owner keeps analytics but loses settings',
        () {
      expect(
        guard(AppStage.ready, Routes.analytics,
            canManageStock: true, isAdmin: false),
        isNull,
      );
      expect(
        guard(AppStage.ready, Routes.settings,
            canManageStock: true, isAdmin: false),
        Routes.dashboard,
      );
    });

    test('a cashier keeps the till', () {
      expect(
        guard(AppStage.ready, Routes.sell,
            canManageStock: false, isAdmin: false),
        isNull,
      );
    });
  });

  group('the guard terminates', () {
    // A redirect that bounces forever is the classic go_router failure, and it
    // presents as a blank screen with no error. Every stage's canonical location
    // must resolve to `null` on the next pass.
    const Map<AppStage, String> gated = <AppStage, String>{
      AppStage.loading: Routes.splash,
      AppStage.databaseFailed: Routes.recovery,
      AppStage.chooser: Routes.welcome,
      AppStage.signingIn: Routes.welcome,
      AppStage.settingUp: Routes.setup,
      AppStage.onboarding: Routes.onboarding,
    };

    gated.forEach((AppStage stage, String path) {
      test('$stage settles at $path in one hop and then stops', () {
        // First hop from an arbitrary location.
        expect(guard(stage, '/somewhere/else'), path);

        // Second hop from where the first sent us must be allowed, for the stage
        // that actually owns that path — otherwise the guard loops.
        final AppStage owner = gated.entries
            .firstWhere((MapEntry<AppStage, String> e) => e.value == path)
            .key;
        expect(
          guard(owner, path),
          isNull,
          reason:
              'the guard bounced away from its own destination, so it would '
              'loop forever and present as a blank screen',
        );
      });
    });

    test(
        'a signed-in session at an UNMATCHED path is allowed through, so the '
        'designed 404 owns it rather than a silent bounce', () {
      expect(guard(AppStage.ready, '/no/such/page'), isNull);
    });
  });

  group('the route table', () {
    test('every destination has a distinct path', () {
      final Set<String> paths =
          AppDestination.values.map((AppDestination d) => d.path).toSet();
      expect(paths.length, AppDestination.values.length);
    });

    test('every destination resolves back from its own path', () {
      for (final AppDestination destination in AppDestination.values) {
        expect(AppDestination.fromPath(destination.path), destination);
      }
    });

    test('an unknown path resolves to nothing rather than throwing', () {
      expect(AppDestination.fromPath('/nope'), isNull);
    });

    test('there are exactly five branches, and Reports is not one of them', () {
      expect(AppDestination.values.length, 5);
      expect(
        AppDestination.values.map((AppDestination d) => d.path),
        isNot(contains(Routes.reports)),
        reason: 'Reports is a view inside Analytics, not a sixth tab',
      );
    });
  });
}
