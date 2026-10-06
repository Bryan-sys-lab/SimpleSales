// AndroidManifest.xml shape.
//
// This suite exists because of a build break that no Dart test could see.
//
// The `<queries>` block had been placed inside `<application>`, which is where
// it reads most naturally — next to the code that needs it, with its own
// explanatory comment. AAPT rejects it at resource-linking time:
//
//   AAPT: error: unexpected element <queries> found in <manifest><application>
//
// That is not a Dart failure. `flutter analyze` passed, all 326 tests passed, and
// the APK still would not build; only CI's `flutter build apk --debug` caught
// it, after nine minutes. These assertions turn that class of mistake into a
// one-second local test.
//
// The general lesson, recorded because it is easy to repeat: anything AAPT,
// the manifest merger, or Gradle decides is invisible to `flutter test`. If it
// can be asserted without building an APK, it should be.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final xml = manifest.existsSync() ? manifest.readAsStringSync() : '';

  /// The character offset of the first real occurrence of [tag], skipping any
  /// occurrence inside an XML comment.
  ///
  /// Comment-aware as well as the manifest prose being de-tagged: a future
  /// comment that quotes an element name must not be able to make this file look
  /// structurally wrong, or worse, look structurally right when it is wrong.
  int elementOffsetOf(String tag) {
    for (final match in RegExp('<$tag[\\s>/]').allMatches(xml)) {
      if (!_isInsideComment(xml, match.start, tag)) return match.start;
    }
    return -1;
  }

  group('AndroidManifest', () {
    test('exists and is readable', () {
      expect(manifest.existsSync(), isTrue,
          reason: 'run this from duka_pos_app, the package root');
      expect(xml, isNotEmpty);
    });

    test('<queries> is a direct child of <manifest>, before <application>', () {
      final queriesAt = elementOffsetOf('queries');
      final applicationAt = elementOffsetOf('application');

      expect(queriesAt, greaterThan(-1),
          reason: 'no <queries> block at all; on Android 11+ that means '
              'Bluetooth discovery silently returns nothing');
      expect(applicationAt, greaterThan(-1));
      expect(queriesAt, lessThan(applicationAt),
          reason: '<queries> must be a sibling of <application>, not a child '
              'of it, and must precede it');

      // Exactly one, and not nested: a second copy inside <application> would
      // reintroduce the failure the first one was moved out to fix.
      expect(RegExp('<queries>').allMatches(xml).length, 1);
    });

    test('every top-level element is one Android allows as a manifest child',
        () {
      // The allow-list is short, which is the point. Anything outside it is
      // either misplaced or something nobody intended to add.
      const allowed = {
        'uses-permission',
        'uses-feature',
        'uses-sdk',
        'queries',
        'application',
        'permission',
        'permission-group',
        'permission-tree',
        'uses-library',
        'compatible-screens',
        'supports-screens',
        'category',
      };
      // `.skip(1)` drops the root element itself: this test is asking which
      // elements are valid *children* of the manifest, and the manifest is not
      // its own child.
      final tags = RegExp(r'<(/?)([a-zA-Z-]+)')
          .allMatches(xml)
          .where((m) => m.group(1) == '')
          .where((m) => !_isInsideComment(xml, m.start, m.group(2)!))
          .skip(1)
          .map((m) => m.group(2)!)
          .toSet();

      for (final tag in tags) {
        // Only judge elements at the manifest's own indentation level; nested
        // ones (<activity>, <intent>, <data>) are legitimate.
        if (RegExp('^\\s{0,4}<$tag[\\s>]', multiLine: true).hasMatch(xml)) {
          expect(allowed, contains(tag),
              reason: '<$tag> is not a valid direct child of <manifest>');
        }
      }
    });

    test('requests the Bluetooth permissions an ESC/POS printer needs', () {
      for (final permission in [
        'android.permission.BLUETOOTH_CONNECT',
        'android.permission.BLUETOOTH_SCAN',
      ]) {
        expect(xml, contains(permission),
            reason: '$permission is missing; pairing will fail on API 31+');
      }
      // neverForLocation is a promise this app can keep: the Bluetooth path only
      // reads a device address and never derives a location from it.
      expect(xml, contains('android:usesPermissionFlags="neverForLocation"'));
      // The pre-31 pair is capped, because it is silently ignored above it and
      // declaring an ignored permission is noise.
      expect(
          xml,
          matches(RegExp(
              r'android\.permission\.BLUETOOTH"\s*\n?\s*android:maxSdkVersion="30"'
              r'|android:maxSdkVersion="30"\s*\n?\s*android:name="android\.permission\.BLUETOOTH"')));
    });

    test('requests the camera permission for barcode scanning', () {
      expect(xml, contains('android.permission.CAMERA'));
    });

    test('neither Bluetooth nor a camera is required to install', () {
      // A shop with a wedge scanner and no camera must still be able to install
      // and sell. Making either hardware required would exclude real tills.
      expect(
          xml, contains('android.hardware.camera" android:required="false"'));
      expect(xml,
          contains('android.hardware.bluetooth" android:required="false"'));
    });

    test('does not request NFC', () {
      // Some receipt printers advertise NFC. A blanket NFC permission on a till
      // is a liability, not a feature, and nothing here uses it.
      expect(xml, isNot(contains('android.permission.NFC')));
    });

    test('the launcher icon and splash point at files that exist', () {
      final icon =
          RegExp(r'android:icon="@mipmap/([^"]+)"').firstMatch(xml)?.group(1);
      expect(icon, isNotNull, reason: 'no android:icon on <application>');
      for (final density in [
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        final file =
            File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
        expect(file.existsSync(), isTrue,
            reason: 'ic_launcher.png missing from mipmap-$density');
      }
    });

    test('the launcher label is the product name', () {
      expect(xml, contains('android:label="Simple POS"'));
    });
  });
}

/// Whether the first occurrence of [tag] sits inside an XML comment.
///
/// The manifest's own comments quote element names verbatim — this file's
/// rationale is written into the manifest — so a naive scan would find
/// `<queries>` inside prose and conclude the element is nested.
bool _isInsideComment(String xml, int at, String tag) {
  final openComment = xml.lastIndexOf('<!--', at);
  if (openComment < 0) return false;
  final closeComment = xml.indexOf('-->', openComment);
  if (closeComment < at) return false;
  // Only a *complete* comment counts. An unterminated `<!--` means this is a
  // real element and the earlier text is prose, not a comment.
  if (closeComment < 0) return false;
  return xml.substring(openComment, closeComment).contains('<$tag');
}
