import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:duka_pos/app_brand.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brand constants and the launcher icon they ship as.
///
/// The icon checks are here rather than in a golden test on purpose. A golden
/// asserts the icon *looks* like the last one; this asserts it is actually a
/// PNG of the right size at every density. A half-regenerated icon set — the
/// kind you get from a script that failed on one file, or a merge that took
/// the new 192 and the old 48 — still looks plausible in a diff, and the only
/// symptom a user sees is a Flutter logo, or a blank tile, on their handset.
void main() {
  group('SimplePosBrand', () {
    test('exposes a non-empty name and legal name', () {
      expect(SimplePosBrand.appName, isNotEmpty);
      expect(SimplePosBrand.legalName, isNotEmpty);
    });

    test('is named Simple POS', () {
      // Hardcoded on purpose. A rename that changes this constant is a product
      // decision, and this test is the thing that has to be argued with.
      expect(SimplePosBrand.appName, 'Simple POS');
      expect(SimplePosBrand.legalName, 'Simple POS');
    });

    test('attributes the vendor', () {
      expect(SimplePosBrand.poweredByTag, contains('Nerva'));
    });

    test('has no placeholder support contact', () {
      // Empty is a valid state: the owner has not filled it in yet. What is
      // not valid is a placeholder that looks like a real address, because an
      // empty string at least has to be handled deliberately by the caller.
      expect(SimplePosBrand.supportContact, isNot(contains('TODO')));
      expect(SimplePosBrand.supportContact, isNot(contains('example')));
    });

    test('keeps the product name free of the Dart package name', () {
      // The Dart package is still duka_pos. That is deliberate and invisible;
      // it only becomes a bug if a user-visible string inherits it.
      expect(SimplePosBrand.appName, isNot(contains('duka')));
      expect(SimplePosBrand.legalName, isNot(contains('duka')));
    });
  });

  group('launcher icon PNGs', () {
    /// Legacy launcher icons, and the density each one has to be.
    const legacyDensities = <String, int>{
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };

    /// The adaptive foreground and monochrome layers are 108dp, not 48dp.
    const adaptiveDensities = <String, int>{
      'mipmap-mdpi': 108,
      'mipmap-hdpi': 162,
      'mipmap-xhdpi': 216,
      'mipmap-xxhdpi': 324,
      'mipmap-xxxhdpi': 432,
    };

    final resDir = Directory('android/app/src/main/res').absolute.path;

    test('every legacy density has a valid, correctly sized ic_launcher.png',
        () {
      for (final entry in legacyDensities.entries) {
        final path = '$resDir/${entry.key}/ic_launcher.png';
        expectValidPng(path, expectedWidth: entry.value, expectedHeight: entry.value);
      }
    });

    test('every density has an adaptive foreground layer', () {
      for (final entry in adaptiveDensities.entries) {
        final path = '$resDir/${entry.key}/ic_launcher_foreground.png';
        expectValidPng(path, expectedWidth: entry.value, expectedHeight: entry.value);
      }
    });

    test('every density has a monochrome layer for themed icons', () {
      // A themed icon that silently falls back to the full-colour one is not a
      // build failure, so nothing else would catch a missing file here.
      for (final entry in adaptiveDensities.entries) {
        final path = '$resDir/${entry.key}/ic_launcher_monochrome.png';
        expectValidPng(path, expectedWidth: entry.value, expectedHeight: entry.value);
      }
    });

    test('the adaptive icon layer stack declares all three layers', () {
      final file = File('$resDir/mipmap-anydpi-v26/ic_launcher.xml');
      expect(file.existsSync(), isTrue,
          reason: 'API 26+ devices need mipmap-anydpi-v26/ic_launcher.xml or '
              'they fall back to the legacy bitmap and ignore the monochrome');
      final xml = file.readAsStringSync();
      expect(xml, contains('<background'));
      expect(xml, contains('<foreground'));
      expect(xml, contains('<monochrome'));
      expect(xml, contains('@color/ic_launcher_background'));
    });

    test('the splash background is the brand ink colour, not white', () {
      // Compared as a parsed ARGB value, not as a substring. Android accepts
      // `#RRGGBB` and `#AARRGGBB` for the same colour, so a strict string match
      // would fail on a resource that is in fact exactly right — which is how a
      // correct splash ends up "fixed" into a wrong one.
      const expectedInk = 0xFF251A1D;
      final colors = File('$resDir/values/colors.xml');
      expect(colors.existsSync(), isTrue);
      final brandInk = RegExp(r'name="brand_ink"\s*>\s*#([0-9a-fA-F]{6,8})')
          .firstMatch(colors.readAsStringSync());
      expect(brandInk, isNotNull,
          reason: 'colors.xml must define brand_ink from DukaColors.ink');
      final hex = brandInk!.group(1)!;
      final argb = hex.length == 6 ? 0xFF000000 | int.parse(hex, radix: 16)
          : int.parse(hex, radix: 16);
      expect(argb, expectedInk);
      for (final variant in ['drawable', 'drawable-v21']) {
        final launch = File('$resDir/$variant/launch_background.xml');
        expect(launch.existsSync(), isTrue, reason: '$variant splash is missing');
        expect(launch.readAsStringSync(), contains('@color/brand_ink'),
            reason: '$variant would flash white on startup');
      }
      for (final variant in ['values', 'values-night']) {
        final styles = File('$resDir/$variant/styles.xml');
        expect(styles.existsSync(), isTrue, reason: '$variant/styles.xml is missing');
        expect(styles.readAsStringSync(), contains('@drawable/launch_background'));
      }
    });

    test('every iOS app icon slot named in Contents.json is a real PNG', () {
      final dir = Directory(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset').absolute.path;
      final contentsFile = File('$dir/Contents.json');
      expect(contentsFile.existsSync(), isTrue);
      final decoded = jsonDecode(contentsFile.readAsStringSync()) as Map;
      final images = decoded['images'] as List;

      var checked = 0;
      for (final raw in images) {
        final entry = raw as Map<String, dynamic>;
        final filename = entry['filename'] as String?;
        if (filename == null) continue; // a slot Xcode fills in itself
        final points =
            double.parse((entry['size'] as String).split('x').first);
        final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
        final edge = (points * scale).round();
        expectValidPng('$dir/$filename',
            expectedWidth: edge, expectedHeight: edge);
        checked++;
      }

      expect(checked, greaterThanOrEqualTo(19),
          reason: 'expected the full Flutter iOS slot set');
    });

    test('the iOS app icon PNGs carry no alpha channel', () {
      // App Store validation rejects an app icon with transparency. The colour
      // type byte of the IHDR chunk is at offset 25: 2 is truecolour RGB,
      // 6 is truecolour with alpha.
      final dir = Directory(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset').absolute.path;
      for (final entity in Directory(dir).listSync().whereType<File>()) {
        if (!entity.path.endsWith('.png')) continue;
        final bytes = entity.readAsBytesSync();
        final colourType = bytes[25];
        expect(colourType, isNot(6),
            reason: '${entity.path} has an alpha channel; iOS rejects that');
      }
    });
  });
}

/// Asserts the file at [path] is a non-empty PNG of exactly the given size.
///
/// Reads the IHDR rather than trusting the extension: a truncated download, a
/// text file renamed to .png and a zero-byte placeholder all have plausible
/// names, and only the header tells them apart.
void expectValidPng(
  String path, {
  required int expectedWidth,
  required int expectedHeight,
}) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing — re-run '
      'assets/branding/generate_launcher_icon.py');

  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(0), reason: '$path is empty');
  expect(
    bytes.length,
    greaterThan(33),
    reason: '$path is truncated: ${bytes.length} bytes is too short to '
        'contain a PNG header',
  );

  const pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(
    Uint8List.sublistView(bytes, 0, 8),
    pngMagic,
    reason: '$path does not start with the PNG signature — it is not a PNG',
  );
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR',
      reason: '$path has no IHDR chunk; the file is truncated or malformed');

  final data = ByteData.sublistView(bytes);
  final width = data.getUint32(16, Endian.big);
  final height = data.getUint32(20, Endian.big);
  expect(width, expectedWidth,
      reason: '$path is ${width}px wide, expected ${expectedWidth}px — the '
          'wrong density was written to this folder');
  expect(height, expectedHeight,
      reason: '$path is ${height}px tall, expected ${expectedHeight}px');
}
