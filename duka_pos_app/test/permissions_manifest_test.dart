// The permissions this app declares, and the ones it should.
//
// This suite exists because two of the app's permissions were declared in a
// way that made the feature behind them DEAD, and neither mistake was visible
// to `flutter analyze` or to a Dart test:
//
//   * `REQUEST_INSTALL_PACKAGES` was capped with `maxSdkVersion="25"`. The
//     permission is ENFORCED from API 26 and does not exist below it, so the
//     cap declared it for the devices that do not need it and withheld it from
//     every device that does. `canRequestPackageInstalls()` then answered false
//     on every modern handset and the in-app updater could never install
//     anything — a feature that looked present in the code and was dead in the
//     field.
//   * iOS had no `NSBluetoothAlwaysUsageDescription`. From iOS 13 the system
//     does not prompt for Bluetooth without it: it TERMINATES the app the
//     first time CoreBluetooth is touched. A till that paired a printer on iOS
//     would have crashed the first time a receipt was printed.
//
// The general lesson, the same one the manifest suite already records: what
// the manifest merger, AAPT or the OS decides is invisible to `flutter test`,
// so if it can be asserted without building an APK, it should be.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final xml = manifest.existsSync() ? manifest.readAsStringSync() : '';

  final infoPlist = File('ios/Runner/Info.plist');
  final plist = infoPlist.existsSync() ? infoPlist.readAsStringSync() : '';

  /// The `<uses-permission>` element for [name], or an empty string.
  ///
  /// Comment-aware, because a comment that quotes a permission name must not
  /// be able to make this file look right when it is wrong.
  String permissionElement(String name) {
    final pattern = RegExp(
      '<uses-permission\\s+android:name="android\\.permission\\.$name"[^>]*>',
    );
    for (final match in pattern.allMatches(xml)) {
      final start = match.start;
      final before = xml.substring(0, start);
      final openComment = before.lastIndexOf('<!--');
      final closeComment = before.lastIndexOf('-->');
      if (openComment > closeComment) continue;
      return match.group(0)!;
    }
    return '';
  }

  group('the in-app updater', () {
    test('the install permission is declared for the releases that enforce it',
        () {
      final String element = permissionElement('REQUEST_INSTALL_PACKAGES');
      expect(
        element,
        isNotEmpty,
        reason: 'without it the OS refuses every install the app starts',
      );

      // The permission was ENFORCED from API 26. A cap at 25 declares it for
      // the releases that do not enforce it and withholds it from every
      // release that does — which is every release in the field.
      expect(
        element,
        isNot(contains('maxSdkVersion="25"')),
        reason: 'the permission is enforced FROM API 26, so a ceiling at 25 '
            'withholds it from every modern device and the in-app updater can '
            'never install anything',
      );
      expect(
        element,
        contains('minSdkVersion="26"'),
        reason: 'the floor belongs on the permission, not a ceiling',
      );
    });
  });

  group('the camera', () {
    test('is declared, and a camera is not a requirement to install', () {
      expect(permissionElement('CAMERA'), isNotEmpty);
      // A shop with a wedge scanner and no camera must still install the app.
      expect(
        xml,
        contains(
          '<uses-feature android:name="android.hardware.camera" '
          'android:required="false"/>',
        ),
      );
    });
  });

  group('the printer', () {
    test('the runtime Bluetooth permissions are declared for API 31+', () {
      // Android 12 split the blanket permission into connect and scan. Both
      // are runtime permissions on API 31+, and a till with a paired printer
      // that cannot reach it reports "no printers found".
      expect(permissionElement('BLUETOOTH_SCAN'), isNotEmpty);
      expect(permissionElement('BLUETOOTH_CONNECT'), isNotEmpty);
    });

    test('the legacy pair is capped at API 30, where it still exists', () {
      // Above API 30 the legacy permissions are ignored, so declaring them is
      // noise; below it they are the ones that exist.
      final String legacy = permissionElement('BLUETOOTH');
      expect(legacy, isNotEmpty);
      expect(legacy, contains('maxSdkVersion="30"'));
    });

    test('iOS declares what it shows when it asks for Bluetooth', () {
      // Without this key iOS does not prompt: it TERMINATES the app the first
      // time CoreBluetooth is touched, so a till that paired a printer on iOS
      // would crash the first time a receipt was printed.
      expect(
        plist,
        contains('NSBluetoothAlwaysUsageDescription'),
        reason: 'from iOS 13 the app is TERMINATED without this key',
      );
      expect(
        plist,
        contains('<string>Send receipts to your Bluetooth receipt printer.'
            '</string>'),
        reason: 'the string is what the system prompt shows, so it has to be '
            'there and has to say what the shop gets out of it',
      );
    });
  });

  group('the camera on iOS', () {
    test('both usage strings are declared', () {
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, contains('NSPhotoLibraryUsageDescription'));
    });
  });

  group('the permissions the app does NOT ask for', () {
    test('no location, because the app never derives a place from a radio', () {
      // A till that wanted location would be a till asking for something a
      // shop should not have to explain.
      expect(permissionElement('ACCESS_FINE_LOCATION'), isEmpty);
      expect(permissionElement('ACCESS_COARSE_LOCATION'), isEmpty);
    });

    test('no notifications, because the app has no notification feature', () {
      // A permission for something the app does not do is a permission the
      // owner refuses for nothing, and a refusal teaches them to refuse.
      expect(permissionElement('POST_NOTIFICATIONS'), isEmpty);
    });

    test('no blanket storage, because the photo picker needs none', () {
      // Reading the gallery goes through the system photo picker, which is
      // granted by the picker itself.
      expect(permissionElement('READ_EXTERNAL_STORAGE'), isEmpty);
      expect(permissionElement('MANAGE_EXTERNAL_STORAGE'), isEmpty);
    });
  });
}
