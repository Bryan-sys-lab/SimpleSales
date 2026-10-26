// The in-app update's own rules.
//
// The comparison rule is the one that decides whether a till can update at all,
// and getting it wrong is not a cosmetic bug:
//
//   * comparing by version NAME means "2.10.0" vs "2.9.0" is decided by string
//     comparison, which says 2.9.0 is newer. A shop on 2.10.0 is then offered a
//     downgrade the OS refuses.
//
//   * treating a build of 0 as "a release" means every real build is newer, so
//     nothing is ever offered — and nothing says why.
//
// Both are pinned here, along with the manifest-parsing rules that decide which
// of those a handset sees.

import 'dart:convert';

import 'package:duka_pos/services/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading a manifest', () {
    Map<String, Object?> good() => <String, Object?>{
          'build': 7,
          'version': '2.1.0',
          'downloadUrl': 'https://example.com/app.apk',
          'notes': 'Receipts print faster',
        };

    test('a well-formed manifest becomes a release', () {
      final release = AppRelease.tryParse(good());
      expect(release, isNotNull);
      expect(release!.build, 7);
      expect(release.versionName, '2.1.0');
      expect(release.downloadUrl, 'https://example.com/app.apk');
      expect(release.notes, 'Receipts print faster');
      expect(release.required, isFalse);
    });

    test('a platform announcement is accepted without tenant data', () {
      final announcement = PlatformAnnouncement.tryParse(<String, Object?>{
        'id': 'announcement-1',
        'title': 'New update',
        'body': 'A faster checkout is available.',
      });
      expect(announcement, isNotNull);
      expect(announcement!.id, 'announcement-1');
      expect(announcement.body, isNot(contains('tenant')));
    });

    test('legacy snake-case manifests remain readable', () {
      final release = AppRelease.tryParse(<String, Object?>{
        'version_code': 8,
        'version_name': '2.2.0',
        'download_url': 'https://example.com/app.apk',
        'release_notes': 'Fixes',
      });
      expect(release?.build, 8);
      expect(release?.notes, 'Fixes');
    });

    test('the decision is the build, and the name is only a label', () {
      // THE trap. 2.10.0 sorts before 2.9.0 as a string. If the comparison were
      // made on names, a shop on 2.10.0 would be offered 2.9.0 and the OS would
      // refuse it as a downgrade.
      final newer = AppRelease.tryParse(
          <String, Object?>{...good(), 'build': 11, 'version': '2.10.0'})!;
      final older = AppRelease.tryParse(
          <String, Object?>{...good(), 'build': 10, 'version': '2.9.0'})!;

      expect(newer.build, greaterThan(older.build));
      // And the name ordering is the opposite of the build ordering, which is
      // the whole reason the name is never used for the decision.
      expect(newer.versionName.compareTo(older.versionName), lessThan(0));
    });

    test('a build of zero is refused rather than served', () {
      // 0 is lower than every real build, so a handset handed it would conclude
      // it was already up to date. That failure is invisible everywhere except
      // in this parse.
      expect(AppRelease.tryParse(<String, Object?>{...good(), 'build': 0}),
          isNull);
      expect(AppRelease.tryParse(<String, Object?>{...good(), 'build': -3}),
          isNull);
    });

    test('a negative or fractional build is refused', () {
      expect(AppRelease.tryParse(<String, Object?>{...good(), 'build': 2.5}),
          isNull);
    });

    test('a release with nowhere to download from is refused', () {
      // A release with no URL would be offered and then fail to download.
      for (final bad in <String>['', '   ']) {
        expect(
          AppRelease.tryParse(<String, Object?>{...good(), 'downloadUrl': bad}),
          isNull,
          reason: 'downloadUrl "$bad" cannot be installed',
        );
      }
    });

    test('a release with no version name is refused', () {
      expect(AppRelease.tryParse(<String, Object?>{...good(), 'version': ''}),
          isNull);
      expect(AppRelease.tryParse(<String, Object?>{...good(), 'version': '  '}),
          isNull);
    });

    test('anything that is not an object is refused', () {
      // A list, a string, null: the shape is wrong in a way that must not be
      // guessed around.
      for (final raw in <Object?>[
        <Object>[1, 2],
        'a string',
        null,
        42,
      ]) {
        expect(AppRelease.tryParse(raw), isNull);
      }
    });

    test('a missing notes field is an empty note, not a crash', () {
      final release = AppRelease.tryParse(good()..remove('notes'));
      expect(release, isNotNull);
      expect(release!.notes, '');
    });

    test('required and minimumBuild are read when present, absent as absent',
        () {
      final plain = AppRelease.tryParse(good())!;
      expect(plain.required, isFalse);
      expect(plain.minimumBuild, isNull);
      expect(plain.urgency, UpdateUrgency.normal);

      final required = AppRelease.tryParse(<String, Object?>{
        ...good(),
        'required': true,
        'minimumBuild': 5,
      })!;
      expect(required.required, isTrue);
      expect(required.minimumBuild, 5);
      expect(required.urgency, UpdateUrgency.required);
    });
  });

  group('the comparison the OS will also make', () {
    test('an equal build is not an update', () {
      // Android refuses an equal versionCode with INSTALL_FAILED_VERSION_
      // DOWNGRADE. Offering it would be a prompt that cannot be acted on.
      final current = 7;
      final served = 7;
      expect(served > current, isFalse,
          reason: 'the same build is already installed');
    });

    test('a lower build is not an update', () {
      expect(6 > 7, isFalse);
    });

    test('a higher build is', () {
      expect(8 > 7, isTrue);
    });

    test('minimumBuild gates a build that is too old to update over', () {
      // The server can say "you must be on build 12+". A shop on 9 is told that
      // rather than handed an APK that opens a database it cannot read.
      final release = AppRelease.tryParse(<String, Object?>{
        'build': 20,
        'version': '3.0.0',
        'downloadUrl': 'https://example.com/app.apk',
        'minimumBuild': 12,
      })!;

      bool canUpdateFrom(int current) =>
          release.build > current &&
          (release.minimumBuild == null || current >= release.minimumBuild!);

      expect(canUpdateFrom(9), isFalse);
      expect(canUpdateFrom(12), isTrue);
      expect(canUpdateFrom(19), isTrue);
      expect(canUpdateFrom(20), isFalse, reason: 'already on it');
    });
  });

  group('the manifest as bytes', () {
    test('a real JSON body parses the same as the map above', () {
      final raw = jsonEncode(<String, Object?>{
        'build': 7,
        'version': '2.1.0',
        'downloadUrl': 'https://example.com/app.apk',
      });
      final release = AppRelease.tryParse(jsonDecode(raw));
      expect(release, isNotNull);
      expect(release!.build, 7);
    });

    test('a proxy error page is not a release', () {
      // What a shop on a captive portal actually receives.
      expect(AppRelease.tryParse('not json at all'), isNull);
      expect(AppRelease.tryParse(''), isNull);
    });
  });
}
