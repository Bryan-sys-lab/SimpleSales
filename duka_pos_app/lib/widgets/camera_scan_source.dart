import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Why the camera is not running.
///
/// The two failures a till operator can do something about, separated because
/// their WORDS are different: "turn camera access on" is useless advice for a
/// phone with no camera, and "this phone has no camera" is a strange thing to
/// say to someone who has just denied a permission.
enum CameraFailure {
  /// The platform will not let the app use the camera.
  permissionDenied,

  /// There is no camera, or it could not be opened.
  unavailable,
}

/// What the camera is doing right now.
@immutable
class CameraStatus {
  const CameraStatus({
    this.torchOn = false,
    this.hasTorch = false,
    this.failure,
  });

  /// Whether the torch is lit.
  final bool torchOn;

  /// Whether this device has a torch at all.
  final bool hasTorch;

  /// Why the camera is not running, when it is not running.
  final CameraFailure? failure;

  @override
  bool operator ==(Object other) =>
      other is CameraStatus &&
      other.torchOn == torchOn &&
      other.hasTorch == hasTorch &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(torchOn, hasTorch, failure);
}

/// The camera, as the scanning screen needs it.
///
/// The screen never touches [MobileScannerController] directly: it asks this
/// for detections, for the status, and for the preview, and it does not know
/// or care which camera answered. That is what lets a test drive the SAME
/// screen with a stream of detections and no lens behind it — a real till has
/// a camera, a test has a [StreamController] — and it is the same seam that
/// keeps the screen's own logic free of platform types.
///
/// The seam is deliberately narrow. Anything the screen does not need is not
/// here, so the screen cannot grow a dependency on the camera it does not have.
abstract interface class CameraScanSource {
  /// The codes the camera reads, as they are read.
  Stream<BarcodeCapture> get detections;

  /// What the camera is doing.
  ///
  /// A listenable, not a value: the screen has to follow the platform. A
  /// torch that lights, a torch that does not exist, and a camera that failed
  /// all arrive here, and a screen that read the state once would show a
  /// torch button on a phone that has no torch.
  ValueListenable<CameraStatus> get status;

  /// Starts the camera.
  ///
  /// Throws when the platform refuses outright: a scanner with no camera is an
  /// error state with a retry, not a screen that pretends to be scanning.
  Future<void> start();

  /// Stops the camera.
  Future<void> stop();

  /// Turns the torch on or off.
  Future<void> setTorch(bool on);

  /// The preview, drawn behind the reticle.
  ///
  /// [scanWindow] is the reticle's rectangle in the preview's own
  /// coordinates. Passing it to the platform means the camera only looks for
  /// codes inside the frame the operator is aiming at, which is both fewer
  /// false reads and a smaller amount of work per frame.
  Widget buildPreview(BuildContext context, Rect? scanWindow);
}

/// The real camera.
///
/// The detection speed is [DetectionSpeed.normal], and that is a decision with
/// a consequence:
///
/// [DetectionSpeed.noDuplicates] compares each frame against the last one and
/// reports a code only when the frame's codes CHANGE. A label that leaves the
/// frame does not change the reported value — the native side keeps the last
/// non-empty set — so the same label can never be read a second time, ever.
/// Two identical items in one trolley would be silently reduced to one.
///
/// [DetectionSpeed.normal] reports what the camera can see, throttled by
/// [MobileScannerController.detectionTimeoutMs], and the re-read guard is the
/// `ScanGate`'s job: a code is read again once it has been out of view.
class MobileCameraSource implements CameraScanSource {
  MobileCameraSource({MobileScannerController? controller})
      : _controller = controller ?? _defaultController() {
    _controller.addListener(_onControllerChanged);
  }

  /// The controller the preview is built from.
  final MobileScannerController _controller;

  final ValueNotifier<CameraStatus> _status =
      ValueNotifier<CameraStatus>(const CameraStatus());

  @override
  Stream<BarcodeCapture> get detections => _controller.barcodes;

  @override
  ValueListenable<CameraStatus> get status => _status;

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> stop() => _controller.stop();

  @override
  Future<void> setTorch(bool on) async {
    if (_status.value.torchOn == on) return;
    await _controller.toggleTorch();
  }

  @override
  Widget buildPreview(BuildContext context, Rect? scanWindow) {
    return MobileScanner(
      controller: _controller,
      scanWindow: scanWindow,
      fit: BoxFit.cover,
    );
  }

  /// Follows the platform's own state, so the torch button tells the truth and
  /// a camera that has failed says so.
  void _onControllerChanged() {
    final MobileScannerState state = _controller.value;
    _status.value = CameraStatus(
      torchOn: state.torchState == TorchState.on,
      hasTorch: state.torchState != TorchState.unavailable,
      failure: _failureFor(state.error),
    );
  }

  /// Maps a platform error onto the failure the screen can talk about.
  static CameraFailure? _failureFor(MobileScannerException? error) {
    if (error == null) return null;
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return CameraFailure.permissionDenied;
    }
    return CameraFailure.unavailable;
  }

  /// Releases the camera and the channel this source owns.
  Future<void> dispose() async {
    _controller.removeListener(_onControllerChanged);
    _status.dispose();
    await _controller.dispose();
  }

  /// The camera the app ships with.
  ///
  /// Restricted to the symbologies a shop actually stocks: accepting every
  /// format ML Kit supports costs decode time per frame and occasionally wins
  /// the race against the code the operator meant.
  static MobileScannerController _defaultController() {
    return MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      formats: const <BarcodeFormat>[
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.itf14,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.pdf417,
      ],
    );
  }
}
