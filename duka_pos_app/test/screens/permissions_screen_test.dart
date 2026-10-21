// The permissions step.
//
// The screen the owner walks through once, after the walkthrough, to grant the
// two permissions the till can use.
//
// What this pins is the property that matters most about it: it CANNOT BLOCK.
// A shop with a wedge scanner and no camera, or a till that has not paired a
// printer, must still be able to sell. So "Continue" is always there, and the
// screen says so in words — a screen of system prompts with no reassurance
// reads as a wall rather than as a question.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/permissions_screen.dart';
import 'package:duka_pos/services/permission_service.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A permission service that answers whatever the test tells it to.
class _FakePermissions implements PermissionService {
  _FakePermissions({
    Map<TillPermission, PermissionState>? states,
    this.grantOnRequest = false,
  }) : states = <TillPermission, PermissionState>{...?states};

  final Map<TillPermission, PermissionState> states;

  /// What a request answers.
  final bool grantOnRequest;

  /// The permissions that were asked for, in order.
  final List<TillPermission> asked = <TillPermission>[];

  @override
  Future<PermissionState> state(TillPermission permission) async =>
      states[permission] ?? PermissionState.notAsked;

  @override
  Future<bool> request(TillPermission permission) async {
    asked.add(permission);
    if (grantOnRequest) {
      states[permission] = PermissionState.granted;
      return true;
    }
    return false;
  }
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('it names the two permissions and why they are wanted',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: PermissionsScreen(permissions: _FakePermissions()),
    );
    await tester.pumpAndSettle();

    // The camera, and what the shop gets out of it.
    expect(find.text(l10n.permissionsCameraTitle), findsOneWidget);
    expect(find.text(l10n.permissionsCameraWhy), findsOneWidget);

    // Bluetooth, and what the shop gets out of it.
    expect(find.text(l10n.permissionsBluetoothTitle), findsOneWidget);
    expect(find.text(l10n.permissionsBluetoothWhy), findsOneWidget);

    // And the reassurance, in words. A screen of prompts with no sentence
    // saying they are optional reads as a wall.
    expect(find.text(l10n.permissionsOptionalNote), findsOneWidget);
  });

  testWidgets('asking for a permission reports the answer', (tester) async {
    tester.useDevice(Device.small);
    final _FakePermissions permissions = _FakePermissions(grantOnRequest: true);
    await tester.pumpApp(
      home: PermissionsScreen(permissions: permissions),
    );
    await tester.pumpAndSettle();

    // Not granted yet.
    expect(find.text(l10n.permissionsAllowed), findsNothing);

    await tester.tap(find.text(l10n.permissionsAllow).first);
    await tester.pumpAndSettle();

    expect(permissions.asked, contains(TillPermission.camera));
    expect(find.text(l10n.permissionsAllowed), findsOneWidget);
  });

  testWidgets('a refused permission says so, and is not asked twice silently',
      (tester) async {
    tester.useDevice(Device.small);
    final _FakePermissions permissions = _FakePermissions(
      states: <TillPermission, PermissionState>{
        TillPermission.camera: PermissionState.refused,
      },
    );
    await tester.pumpApp(
      home: PermissionsScreen(permissions: permissions),
    );
    await tester.pumpAndSettle();

    // A refused permission can be asked for again, so the button says "Allow".
    expect(find.text(l10n.permissionsAllow), findsWidgets);
    expect(find.text(l10n.permissionsAllowed), findsNothing);
  });

  testWidgets('a permanently refused permission says "Open Settings"',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: PermissionsScreen(
        permissions: _FakePermissions(
          states: <TillPermission, PermissionState>{
            TillPermission.camera: PermissionState.permanentlyDenied,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only the system Settings screen can undo "don't ask again". Promising
    // to ask again would waste the tap and teach the owner that the app does
    // not listen.
    //
    // Scoped to the camera's own card: the Bluetooth permission is untouched
    // in this test and still offers "Allow", and that is correct.
    final Finder cameraCard = find.ancestor(
      of: find.text(l10n.permissionsCameraTitle),
      matching: find.byType(SurfaceCard),
    );
    expect(
      find.descendant(
        of: cameraCard,
        matching: find.text(l10n.permissionsOpenSettings),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cameraCard,
        matching: find.text(l10n.permissionsAllow),
      ),
      findsNothing,
    );
  });

  testWidgets('Continue is always there, and always works', (tester) async {
    tester.useDevice(Device.small);
    bool finished = false;
    await tester.pumpApp(
      home: PermissionsScreen(
        permissions: _FakePermissions(),
        onComplete: () async => finished = true,
      ),
    );
    await tester.pumpAndSettle();

    // Nothing was granted, nothing was asked, and the step still ends.
    await tester.tap(find.text(l10n.permissionsContinue));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('it lays out on the narrowest phone at the largest text',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: PermissionsScreen(permissions: _FakePermissions()),
      textScaler: TextScaler.linear(2.0),
    );
    await tester.pumpAndSettle();

    tester.expectNoOverflow('permissions step at 2x text');
  });
}
