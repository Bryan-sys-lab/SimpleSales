// The camera scanning screen: the one screen where a till is judged on how
// fast it reads.
//
// WHAT THIS TEST IS FOR
//
// 1. THE RE-TRIGGER. The screen used to treat a scan as the end of the
//    session: the first code stopped the camera, popped the route, and the
//    operator had to press the till's scan button again before the next item
//    could be read. The scanner now keeps reading, so the test proves the
//    SECOND code lands with no press in between — and that no "try again"
//    affordance is standing in the way.
//
// 2. THE RE-READ. A camera reports the same label again and again while it
//    stays in frame, so the screen needs a guard between "the same label" and
//    "the next item". The guard is timed, and a timed guard needs a clock the
//    test controls: the test steps the clock rather than waiting a real half
//    second.
//
// 3. THE LAYOUT. A scanner is a phone held in one hand at a counter, so the
//    screen has to survive 200% text on the narrowest phone in the shop.
//
// The camera is a FAKE, and that is the point: the screen talks to the camera
// through one interface, so the same screen that runs on a handset runs in a
// test with a stream of detections and no lens behind it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:duka_pos/services/barcode/scan_input_service.dart';
import 'package:duka_pos/widgets/camera_scan_screen.dart';
import 'package:duka_pos/widgets/camera_scan_source.dart';

import '../support/harness.dart';

/// The text scales a real phone can be set to.
///
/// 1.3 is the Android "large" step. 2.0 is the accessibility step, and it is
/// where a fixed height stops being a height.
const List<double> _textScales = <double>[1.0, 1.3, 2.0];

/// A camera with no lens behind it.
class _FakeCamera implements CameraScanSource {
  _FakeCamera({this.failsToStart = false});

  final StreamController<BarcodeCapture> _detections =
      StreamController<BarcodeCapture>.broadcast();
  final ValueNotifier<CameraStatus> _status =
      ValueNotifier<CameraStatus>(const CameraStatus(hasTorch: true));

  /// Why the camera will not run, when it will not run.
  CameraFailure? failureReason;

  /// Whether opening the camera throws.
  bool failsToStart;

  /// How many times the screen tried to open the camera.
  int starts = 0;

  @override
  Stream<BarcodeCapture> get detections => _detections.stream;

  @override
  ValueListenable<CameraStatus> get status => _status;

  @override
  Future<void> start() async {
    starts++;
    if (failsToStart) {
      throw StateError('the platform refused the camera');
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setTorch(bool on) async {
    _status.value = CameraStatus(
      torchOn: on,
      hasTorch: true,
      failure: failureReason,
    );
  }

  @override
  Widget buildPreview(BuildContext context, Rect? scanWindow) {
    return const SizedBox.expand();
  }

  /// The camera reads a code.
  void read(String code) {
    _detections.add(
      BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: code)]),
    );
  }

  /// The camera cannot decode a frame.
  void failToDecode() {
    _detections.addError(StateError('the frame could not be decoded'));
  }

  /// The camera fails.
  void fail(CameraFailure reason) {
    failureReason = reason;
    _status.value = CameraStatus(failure: reason);
  }

  Future<void> dispose() async {
    await _detections.close();
    _status.dispose();
  }
}

/// A clock the test steps.
class _FakeClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  DateTime call() => _now;

  void advance(Duration by) {
    _now = _now.add(by);
  }
}

/// Reads a code and lets the screen catch up with it.
///
/// TWO pumps, and the second one is not decoration: a stream delivery is a
/// microtask, and the frame that shows the result is built after it. One pump
/// delivers the code; the next one draws the confirmation.
Future<void> _read(
  WidgetTester tester,
  _FakeCamera camera,
  String code,
) async {
  camera.read(code);
  await tester.pump();
  await tester.pump();
}

void main() {
  // The real typeface, not the test font: a layout that only fits because
  // every glyph is one em wide is a layout that does not fit.
  setUpAll(loadAppFonts);

  group('the scanner never stops to ask', () {
    testWidgets('the second code lands with no press in between',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera();
      final _FakeClock clock = _FakeClock();
      final ScanSession session = ScanSession();
      final List<ScanResult> received = <ScanResult>[];
      final StreamSubscription<ScanResult> subscription =
          session.codes.listen(received.add);
      addTearDown(subscription.cancel);
      addTearDown(session.dispose);
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(
          session: session,
          source: camera,
          clock: clock.call,
        ),
      );
      await tester.pump();

      // The frame the operator aims at, and the instruction that says what to
      // do with it. A scanner with neither is a scanner nobody can use.
      expect(find.byKey(kCameraScanReticleKey), findsOneWidget);
      expect(find.text('Point the camera at the barcode'), findsOneWidget);

      // The first code is read, confirmed, and handed to the till.
      await _read(tester, camera, '6001234567890');
      expect(received, hasLength(1));
      expect(received.single.normalised, '6001234567890');
      expect(find.text('1 code read'), findsOneWidget);

      // And the scanner is STILL looking: the next code lands with no button
      // pressed, no dialog dismissed, and no state cleared in between. This is
      // the whole point — a till must not stop and ask permission between
      // every item.
      await _read(tester, camera, '6009876543210');
      expect(received, hasLength(2));
      expect(received.last.normalised, '6009876543210');
      expect(find.text('2 codes read'), findsOneWidget);

      // Nothing in the scanning state asks to be pressed again.
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.textContaining('Try camera again'), findsNothing);
    });

    testWidgets('a label held in frame is read once, and read again once it '
        'has been out of view', (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera();
      final _FakeClock clock = _FakeClock();
      final ScanSession session = ScanSession();
      final List<ScanResult> received = <ScanResult>[];
      final StreamSubscription<ScanResult> subscription =
          session.codes.listen(received.add);
      addTearDown(subscription.cancel);
      addTearDown(session.dispose);
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(
          session: session,
          source: camera,
          clock: clock.call,
        ),
      );
      await tester.pump();

      await _read(tester, camera, '6001234567890');
      expect(received, hasLength(1));

      // The camera reports the same label again, 200ms later: the platform
      // does that for as long as the label is in frame. One item, one read.
      clock.advance(const Duration(milliseconds: 200));
      await _read(tester, camera, '6001234567890');
      expect(received, hasLength(1),
          reason: 'the same label, still in frame, is one item');

      // The label leaves the frame and stays out of it for the re-read
      // window. Now it is a second reading of the same code — a second
      // identical item on the trolley, which must be sellable.
      clock.advance(const Duration(milliseconds: 600));
      await _read(tester, camera, '6001234567890');
      expect(received, hasLength(2),
          reason: 'a label that has been out of view is a new reading');
    });
  });

  group('a camera that will not run says so', () {
    testWidgets('a refused camera shows an error with a retry',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera()..fail(
        CameraFailure.permissionDenied,
      );
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(source: camera),
      );
      await tester.pump();

      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.text('Try camera again'), findsOneWidget);
      // The frame is not on screen: there is nothing to aim at.
      expect(find.byKey(kCameraScanReticleKey), findsNothing);
    });

    testWidgets('a camera that cannot be opened shows an error with a retry',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera(failsToStart: true);
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(source: camera),
      );
      await tester.pump();

      expect(find.text('The camera is not available'), findsOneWidget);
      expect(find.text('Try camera again'), findsOneWidget);
    });

    testWidgets('a camera that stops decoding asks to be retried',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera();
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(source: camera),
      );
      await tester.pump();

      // One unreadable frame is a bad moment, not a broken camera: the screen
      // carries on, because a retry here would interrupt a queue of customers
      // over one bad label.
      camera.failToDecode();
      await tester.pump();
      await tester.pump();
      expect(find.text('Try camera again'), findsNothing);
      expect(find.byKey(kCameraScanReticleKey), findsOneWidget);

      // A run of them is a camera that is not decoding. Now the operator gets
      // a way out.
      camera.failToDecode();
      await tester.pump();
      await tester.pump();
      camera.failToDecode();
      await tester.pump();
      await tester.pump();

      expect(find.text('Try camera again'), findsOneWidget);
    });

    testWidgets('the retry opens the camera again', (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera(failsToStart: true);
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(source: camera),
      );
      await tester.pump();
      expect(find.text('Try camera again'), findsOneWidget);

      // The camera comes back.
      camera.failsToStart = false;
      camera.failureReason = null;
      await tester.tap(find.text('Try camera again'));
      await tester.pump();
      await tester.pump();

      expect(camera.starts, greaterThan(1));
      expect(find.byKey(kCameraScanReticleKey), findsOneWidget);
      expect(find.text('Point the camera at the barcode'), findsOneWidget);
    });
  });

  group('the scanner is usable on a phone', () {
    for (final double scale in _textScales) {
      testWidgets('it lays out at ${scale}x text on the narrowest phone',
          (WidgetTester tester) async {
        tester.useDevice(Device.small);

        final _FakeCamera camera = _FakeCamera();
        addTearDown(camera.dispose);

        await tester.pumpApp(
          home: CameraScanScreen(source: camera),
          textScaler: TextScaler.linear(scale),
        );
        await tester.pump();

        tester.expectNoOverflow('the scanner at ${scale}x text');

        // The controls a thumb has to hit are legal targets.
        tester.expectTapTargetsMeetMinimum(
          find.byType(CameraScanScreen),
        );
      });
    }

    testWidgets('a long code and a long instruction do not overflow',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final _FakeCamera camera = _FakeCamera();
      final _FakeClock clock = _FakeClock();
      addTearDown(camera.dispose);

      await tester.pumpApp(
        home: CameraScanScreen(
          source: camera,
          clock: clock.call,
        ),
        textScaler: TextScaler.linear(2.0),
      );
      await tester.pump();

      // A 64 character code is a real thing to scan: a GS1 serial, a
      // customer loyalty card, a QR payload.
      await _read(
        tester,
        camera,
        '1234567890123456789012345678901234567890123456789012345678'
            '901234',
      );

      tester.expectNoOverflow('the scanner with a long code at 2x text');
      expect(find.text('1 code read'), findsOneWidget);
    });
  });
}
