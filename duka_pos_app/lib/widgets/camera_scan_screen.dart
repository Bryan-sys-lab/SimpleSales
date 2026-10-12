import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode/barcode_service.dart' as barcode_rules;

import '../../services/barcode/scan_input_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';
import '../../theme/typography.dart';

/// Camera barcode scanning.
///
/// POPS a [ScanResult] rather than calling a callback, and that is the whole
/// design of this screen.
///
/// It used to take an `onDetected` closure that the caller was expected to use to
/// close it, which couples three things that should not be coupled: what was
/// scanned, how the route closes, and the caller's state. A popped VALUE crosses
/// the route boundary, so the caller writes `final scan = await context.push(
/// ScanResult, Routes.cameraScan)` and the result is inspectable in a test
/// instead of being a side effect on a widget instance.
///
/// Popping at most once, immediately, is also why it closes: a till operator has
/// already seen the product they scanned, and a scanner that keeps firing hands
/// the same code back two seconds later while they serve the next customer.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

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

  Future<void> _retryCamera() async {
    setState(() {
      _permissionDenied = false;
      _detail = null;
      _handled = false;
    });
    await _start();
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
    final raw = capture.barcodes.map((barcode) => barcode.rawValue).firstWhere(
        (value) => value != null && value.trim().isNotEmpty,
        orElse: () => null);
    if (raw == null) return;

    final normalised = barcode_rules.Barcode.normalise(raw);
    if (normalised.isEmpty) return;

    // Camera frames arrive far faster than a human can act on them, so the
    // first plausible code wins the sheet and everything after is dropped.
    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    Navigator.of(context).pop(ScanResult(
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).scanTitle)),
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
                border:
                    Border.all(color: AppColors.of(context).accent, width: 2),
                borderRadius: AppShapes.of(context).controlRadius,
              ),
            ),
          ),
        ),
        PositionedDirectional(
          // `start: 0, end: 0` rather than `left: 0, right: 0`: the banner is
          // full-width and bottom-anchored, so it is its own mirror — the reticle
          // and the feed it sits on are direction-neutral content that must NOT
          // flip with the locale.
          start: 0,
          end: 0,
          bottom: 24,
          child: Semantics(
            liveRegion: true,
            child: Container(
              color: AppColors.of(context).mediaScrim,
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context).scanHoldInsideFrame,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.of(context).onMediaScrim),
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
  void _onBarcodeCapture(BarcodeCapture capture) =>
      unawaited(_onBarcode(capture));

  Widget _buildDenied() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: AppColors.of(context).danger,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).scanUnavailableTitle,
              textAlign: TextAlign.center,
              style: AppTypography.of(context).titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).scanUnavailableMessage,
              textAlign: TextAlign.center,
            ),
            if (_detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _detail!,
                  style: AppTypography.of(context).bodySmall,
                  textAlign: TextAlign.center,
                  // No maxLines. This is the scanned code or the reason the scan
                  // failed — the two things a person reads to decide what to do
                  // next. Truncating it removes the information at the exact
                  // moment it is needed.
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retryCamera,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).scanRetryCamera),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).scanBackToSelling),
            ),
          ],
        ),
      ),
    );
  }
}
