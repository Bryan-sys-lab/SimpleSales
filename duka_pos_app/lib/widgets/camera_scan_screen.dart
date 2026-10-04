import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode/barcode_service.dart' as barcode_rules;

import '../../services/barcode/scan_input_service.dart';
import '../../theme/app_theme.dart';

/// Camera barcode scanning.
///
/// [onDetected] is called at most once per open sheet and then the scanner
/// closes — a till operator has already looked at the product they scanned, and
/// a scanner that keeps firing hands the same code back two seconds later while
/// they are serving the next customer.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, required this.onDetected});

  final Future<void> Function(ScanResult result) onDetected;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Restricted to the symbologies a shop actually stocks. Accepting every
    // format ML Kit supports costs decode time per frame and occasionally
    // wins the race against the code the operator meant.
    formats: const [
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

  StreamSubscription<Object?>? _subscription;
  bool _handled = false;
  bool _permissionDenied = false;
  String? _detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_onBarcode);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.start();
      if (!mounted) return;
      if (!_controller.value.hasCameraPermission && mounted) {
        setState(() => _permissionDenied = true);
      }
    } catch (error) {
      if (!mounted) return;
      // mobile_scanner throws rather than reporting when the platform refuses
      // the camera, so the failure is caught here and shown as the same
      // screen the operator would see for a refused prompt. A till with a
      // broken camera must still be able to sell by name.
      setState(() {
        _permissionDenied = true;
        _detail = '$error';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller.value;
    if (!controller.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
        _subscription ??= _controller.barcodes.listen(_onBarcode);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(_controller.stop());
    }
  }

  Future<void> _onBarcode(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere((value) => value != null && value.trim().isNotEmpty,
            orElse: () => null);
    if (raw == null) return;

    final normalised = barcode_rules.Barcode.normalise(raw);
    if (normalised.isEmpty) return;

    // Camera frames arrive far faster than a human can act on them, so the
    // first plausible code wins the sheet and everything after is dropped.
    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    await widget.onDetected(ScanResult(
      raw: raw,
      normalised: normalised,
      source: ScanSource.camera,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: SafeArea(
        child: _permissionDenied ? _buildDenied() : _buildScanner(),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onBarcodeCapture),
        Center(
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: DukaColors.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Semantics(
            liveRegion: true,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Hold the barcode inside the frame',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// `onDetect` receives raw captures; the stream subscription above does the
  /// normalising and the once-only gate. This exists so the widget has a
  /// detector too (the controller needs one for the overlay preview) and both
  /// paths funnel into the same handler.
  void _onBarcodeCapture(BarcodeCapture capture) => unawaited(_onBarcode(capture));

  Widget _buildDenied() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 48, color: DukaColors.danger),
            const SizedBox(height: 16),
            const Text(
              'The camera is not available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can still sell this product — search for it by name on the Sell screen, '
              'or use a Bluetooth or USB barcode scanner, which types the code straight into the till.',
              textAlign: TextAlign.center,
            ),
            if (_detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _detail!,
                  style: const TextStyle(fontSize: 11, color: DukaColors.mutedInk),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to selling'),
            ),
          ],
        ),
      ),
    );
  }
}