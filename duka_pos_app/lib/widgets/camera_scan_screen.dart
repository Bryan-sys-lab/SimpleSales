// The camera scanning screen.
//
// WHY IT NEVER STOPS TO ASK
//
// The screen used to treat a scan as the END of the session: the first code
// stopped the camera, popped the route, and handed one result back to the
// till. The till then added that one item to the cart — and to scan the next
// item the cashier had to press the till's scan button again, wait for the
// camera to open, and aim at the next label. A till that stops and asks
// permission between every item is a till that cannot scan a trolley.
//
// So the camera now keeps looking. A code is read, confirmed, handed to the
// till, and the camera carries on reading the next one. The only thing between
// two scans is a re-read guard, and its whole job is to stop the SAME label
// being charged for twice while it is still in frame.
//
// WHY THE DELIVERY IS A SESSION
//
// The till has to receive codes WHILE this screen is open, because the screen
// does not close when a code is read. A route that pops a value can only pop
// once, so the channel is a [ScanSession] the till owns and hands in — and the
// scanner writes to it as it reads. The screen still pops the codes it read on
// the way out, for a route that was opened without a till behind it; the till
// ignores that copy, because it has already had the live one.
//
// WHAT THE SCREEN IS
//
// A near-black instrument panel with the camera as the hero. The frame the
// operator aims at is drawn over the feed, the area around it is dimmed so the
// eye goes to the frame and nowhere else, and the controls are quiet: a torch
// toggle, a way to type a code that will not scan, and the one saturated
// action on the screen.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/barcode/barcode_service.dart' as barcode_rules;
import '../services/barcode/scan_input_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import 'camera_scan_source.dart';

/// The frame the operator aims at, published so a test can find it.
///
/// A plain [ValueKey], not a [GlobalKey]: the frame's identity is "the frame",
/// not "this particular element in this particular tree", and nothing in the
/// app needs to reach it from outside.
const ValueKey<String> kCameraScanReticleKey =
    ValueKey<String>('camera-scan-reticle');

/// The camera scanning screen.
///
/// [session] is where the codes go. [source] and [clock] are the seams a test
/// drives: a real till has a lens and a wall clock, a test has a stream of
/// detections and a clock it can step.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({
    super.key,
    this.session,
    this.source,
    this.clock,
  });

  /// The till's channel. Null when the screen was opened without one.
  final ScanSession? session;

  /// The camera. Null means the real one.
  final CameraScanSource? source;

  /// The clock. Null means the wall clock.
  final DateTime Function()? clock;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
  late final CameraScanSource _camera;
  late final ScanGate _gate;

  StreamSubscription<BarcodeCapture>? _codes;

  /// The codes read since the screen opened, in the order they were read.
  final List<ScanResult> _read = <ScanResult>[];

  /// The last code read. The confirmation, and the only thing on screen that
  /// changes when a scan lands.
  String? _lastRead;

  /// How many decode failures in a row the camera has reported.
  ///
  /// ONE failed frame is nothing — a damaged label, a glare, a frame the
  /// platform read badly. A run of them means the camera is not decoding at
  /// all, and the operator is standing there pointing at a label that will
  /// never be read. That is the point where a retry appears.
  int _decodeFailures = 0;

  _Stage _stage = _Stage.starting;

  /// Which failure the screen is showing, when it is showing one.
  _Failure _failure = _Failure.unavailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = widget.source ?? MobileCameraSource();
    _gate = ScanGate(clock: widget.clock);
    _codes = _camera.detections.listen(_onCapture, onError: _onDecodeError);
    _camera.status.addListener(_onStatusChanged);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_codes?.cancel());
    _camera.status.removeListener(_onStatusChanged);
    final CameraScanSource camera = _camera;
    if (camera is MobileCameraSource) {
      unawaited(camera.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (_stage == _Stage.scanning) unawaited(_start());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_camera.stop());
    }
  }

  /// Opens the camera, and decides what the screen is.
  ///
  /// The camera either opens or it does not, and the two failures it can fail
  /// with are different problems with different words: permission refused, or
  /// no camera at all. Both are ERROR PATHS with a retry — never a screen that
  /// pretends to be scanning.
  Future<void> _start() async {
    try {
      await _camera.start();
    } catch (_) {
      _fail(_Failure.unavailable);
      return;
    }
    if (!mounted) return;
    final CameraFailure? failure = _camera.status.value.failure;
    if (failure != null) {
      _fail(_failureOf(failure));
      return;
    }
    setState(() => _stage = _Stage.scanning);
  }

  /// The camera's state changed. A failure that arrives while the camera is
  /// running is the camera saying it cannot continue.
  void _onStatusChanged() {
    if (!mounted) return;
    final CameraFailure? failure = _camera.status.value.failure;
    if (failure == null) return;
    if (_stage == _Stage.failed) return;
    _fail(_failureOf(failure));
  }

  /// Maps the camera's reason onto the screen's.
  static _Failure _failureOf(CameraFailure failure) =>
      failure == CameraFailure.permissionDenied
          ? _Failure.permissionDenied
          : _Failure.unavailable;

  /// Puts the screen into its error state, with a way out.
  void _fail(_Failure failure) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _failure = failure;
    });
  }

  /// Tries the camera again, from the error state's retry.
  Future<void> _retry() async {
    if (!mounted) return;
    setState(() => _stage = _Stage.starting);
    await _start();
  }

  /// A code arrived.
  void _onCapture(BarcodeCapture capture) {
    // A frame the platform could read at all is a camera that is working.
    _decodeFailures = 0;
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) continue;
      final String normalised = barcode_rules.Barcode.normalise(raw);
      if (normalised.isEmpty) continue;
      // The re-read guard. A label held in frame is reported again and again;
      // this is the line between "the same label" and "the next item".
      if (!_gate.accept(normalised)) continue;
      _record(raw, normalised, ScanSource.camera);
    }
  }

  /// The platform could not decode a frame.
  ///
  /// One of these is a bad label or a bad moment. A run of them is a camera
  /// that is not decoding, and the operator deserves a retry instead of a
  /// screen that quietly never reads anything.
  void _onDecodeError(Object error) {
    _decodeFailures++;
    if (_decodeFailures < 3) return;
    _fail(_Failure.unavailable);
  }

  /// Records a code, confirms it, and hands it to the till.
  void _record(String raw, String normalised, ScanSource source) {
    final ScanResult result =
        ScanResult(raw: raw, normalised: normalised, source: source);
    setState(() {
      _read.add(result);
      _lastRead = raw;
    });
    widget.session?.add(result);
    _announce(result);
  }

  /// Says the code was read, for an operator who cannot see the screen.
  void _announce(ScanResult result) {
    if (!mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.scanCodesRead(_read.length),
      Directionality.of(context),
    ));
  }

  /// Closes the screen, handing back the codes it read.
  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop(_read);
  }

  /// Types a code the camera cannot read — a damaged label, a washed-out one.
  Future<void> _enterManually() async {
    final String? typed = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _ManualCodeDialog(),
    );
    if (typed == null || !mounted) return;
    final String normalised = barcode_rules.Barcode.normalise(typed);
    if (normalised.isEmpty) return;
    // A typed code is deliberate: it goes straight in, with no re-read guard.
    _record(typed, normalised, ScanSource.manual);
  }

  Future<void> _toggleTorch(bool lit) async {
    try {
      await _camera.setTorch(!lit);
    } catch (_) {
      // A torch that will not light is not worth an error state: the screen
      // keeps scanning, which is what the operator came for.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context),
            Expanded(
              child: _stage == _Stage.failed
                  ? _failureView(context)
                  : _panel(context),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  /// The compact title.
  ///
  /// NOT a [ScreenTitle]: this screen is mostly a camera, and a screen-sized
  /// title would spend the top of the display on words. It still names the
  /// screen, because a screen that does not say what it is makes the operator
  /// wonder whether they opened the right thing.
  Widget _header(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);
    final EdgeInsets gutter = PageGutter.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: gutter.left,
        end: gutter.right,
        top: spacing.sm,
        bottom: spacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.scanTitle,
              style: type.titleLarge,
            ),
          ),
          SizedBox(width: spacing.sm),
          _QuietIconButton(
            icon: Icons.close,
            tooltip: l10n.scanBackToSelling,
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  /// The camera, in a frame, with the reticle drawn over it.
  Widget _panel(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final EdgeInsets gutter = PageGutter.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: gutter.left,
        end: gutter.right,
      ),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        clipContent: true,
        color: colors.surfaceSunken,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Rect reticle = _reticleFor(constraints, spacing);
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _camera.buildPreview(context, reticle),
                Positioned.fill(
                  child: CustomPaint(
                    key: kCameraScanReticleKey,
                    painter: _ReticlePainter(
                      reticle: reticle,
                      scrim: colors.mediaScrim,
                      frame: colors.onMediaScrim,
                      corner: spacing.xl,
                      radius: AppShapes.of(context).cardRadius.topLeft,
                    ),
                  ),
                ),
                if (_camera.status.value.hasTorch)
                  PositionedDirectional(
                    top: spacing.md,
                    end: spacing.md,
                    child: _torchButton(context),
                  ),
                PositionedDirectional(
                  bottom: spacing.md,
                  start: spacing.md,
                  end: spacing.md,
                  child: _readout(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The confirmation and the instruction, over the feed.
  Widget _readout(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_lastRead != null) ...<Widget>[
          _confirmation(context),
          SizedBox(height: spacing.sm),
        ],
        Text(
          l10n.scanPointAtBarcode,
          style: AppTypography.of(context).bodyMedium?.copyWith(
                color: AppColors.of(context).onMediaScrim,
              ),
        ),
      ],
    );
  }

  /// The brief confirmation that a code was read.
  ///
  /// It says the count and the word, and the code itself sits under it, so the
  /// operator can see WHAT was read without the screen having to resolve it
  /// into a product — resolving is the till's job.
  Widget _confirmation(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StatusChip(
          tone: StatusTone.success,
          text: l10n.scanCodesRead(_read.length),
        ),
        SizedBox(height: spacing.xs),
        Text(
          _lastRead ?? '',
          style: type.bodyMedium?.copyWith(color: colors.onMediaScrim),
        ),
      ],
    );
  }

  /// The torch, over the feed, in the corner.
  ///
  /// It follows the platform: a phone with no torch never shows the button, and
  /// a torch that will not light goes back to showing as off.
  Widget _torchButton(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<CameraStatus>(
      valueListenable: _camera.status,
      builder: (BuildContext context, CameraStatus status, Widget? child) {
        final String label =
            status.torchOn ? l10n.scanFlashOffTooltip : l10n.scanFlashOnTooltip;
        return _QuietIconButton(
          icon: status.torchOn ? Icons.flash_on : Icons.flash_off,
          tooltip: label,
          onPressed: () => _toggleTorch(status.torchOn),
        );
      },
    );
  }

  /// The controls under the camera.
  Widget _footer(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EdgeInsets gutter = PageGutter.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: gutter.left,
        end: gutter.right,
        top: spacing.md,
        bottom: spacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextButton.icon(
            onPressed: _enterManually,
            icon: const Icon(Icons.keyboard_alt_outlined),
            label: Text(l10n.scanEnterCodeManually),
          ),
          SizedBox(height: spacing.xs),
          FilledButton(
            onPressed: _close,
            child: Text(l10n.scanDone),
          ),
        ],
      ),
    );
  }

  /// What the screen shows when the camera will not run.
  Widget _failureView(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return ErrorStateView(
      icon: Icons.no_photography_outlined,
      message: _failure == _Failure.permissionDenied
          ? l10n.scanPermissionDeniedTitle
          : l10n.scanUnavailableTitle,
      detail: _failure == _Failure.permissionDenied
          ? l10n.scanPermissionDeniedMessage
          : l10n.scanUnavailableMessage,
      retryLabel: l10n.scanRetryCamera,
      onRetry: _retry,
    );
  }

  /// The frame the operator aims at.
  ///
  /// A barcode is wide and short, so the frame is twice as wide as it is tall,
  /// and it is measured from the space the panel actually has rather than
  /// assumed — which is what keeps it right on a 320dp phone and on a tablet.
  Rect _reticleFor(BoxConstraints constraints, AppSpacing spacing) {
    final double availableWidth =
        math.max(0, constraints.maxWidth - spacing.xl * 2);
    final double availableHeight =
        math.max(0, constraints.maxHeight - spacing.xl * 2);
    double width = availableWidth;
    double height = width / 2;
    if (height > availableHeight) {
      height = availableHeight;
      width = height * 2;
    }
    return Rect.fromCenter(
      center: constraints.biggest.center(Offset.zero),
      width: width,
      height: height,
    );
  }
}

/// What the screen is showing.
enum _Stage {
  /// The camera is opening.
  starting,

  /// The camera is running and looking for codes.
  scanning,

  /// The camera will not run. A retry is on screen.
  failed,
}

/// Which camera failure the screen is showing.
enum _Failure {
  /// The platform will not let the app use the camera.
  permissionDenied,

  /// There is no camera, or it could not be opened.
  unavailable,
}

/// The reticle, drawn over the feed.
///
/// Two parts, and they do different jobs:
///
/// * the scrim, which dims everything EXCEPT the frame, so the eye goes to
///   the frame and to nothing else — the same job a viewfinder does on a
///   camera;
/// * the corner brackets, which say "aim here" in the one shape that means
///   that. They are drawn in the media ink, NOT in the accent: the accent on
///   this screen belongs to the one thing the operator presses.
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({
    required this.reticle,
    required this.scrim,
    required this.frame,
    required this.corner,
    required this.radius,
  });

  final Rect reticle;
  final Color scrim;
  final Color frame;

  /// How far each bracket arm runs.
  final double corner;

  final Radius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (reticle.isEmpty || size.isEmpty) return;

    // The dimming: the whole panel, minus the frame.
    final Path mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(reticle, radius));
    canvas.drawPath(mask, Paint()..color = scrim);

    // The brackets.
    final Paint stroke = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final Path brackets = Path()
      ..moveTo(reticle.left, reticle.top + corner)
      ..lineTo(reticle.left, reticle.top)
      ..lineTo(reticle.left + corner, reticle.top)
      ..moveTo(reticle.right - corner, reticle.top)
      ..lineTo(reticle.right, reticle.top)
      ..lineTo(reticle.right, reticle.top + corner)
      ..moveTo(reticle.right, reticle.bottom - corner)
      ..lineTo(reticle.right, reticle.bottom)
      ..lineTo(reticle.right - corner, reticle.bottom)
      ..moveTo(reticle.left + corner, reticle.bottom)
      ..lineTo(reticle.left, reticle.bottom)
      ..lineTo(reticle.left, reticle.bottom - corner);

    canvas.drawPath(brackets, stroke);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.reticle != reticle ||
      old.scrim != scrim ||
      old.frame != frame ||
      old.corner != corner;
}

/// A round, quiet button over a camera feed.
///
/// Icon-only, so it carries a tooltip — which is also its semantic label: the
/// platform announces the tooltip's words for the button, so an icon with
/// neither is a control nobody can find.
class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: colors.onMediaScrim),
      iconSize: 20,
      tooltip: tooltip,
      constraints: BoxConstraints.tightFor(
        width: spacing.minTapTarget,
        height: spacing.minTapTarget,
      ),
      style: IconButton.styleFrom(
        backgroundColor: colors.mediaScrim,
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Typing a code the camera cannot read.
///
/// A damaged label, a washed-out one, a code printed on a receipt: the camera
/// is the fast way and this is the way that always works.
class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();

  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.scanManualTitle),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: l10n.scanManualLabel,
            hintText: l10n.scanManualHint,
          ),
          validator: (String? value) {
            final String normalised =
                barcode_rules.Barcode.normalise(value ?? '');
            if (normalised.isEmpty) return l10n.scanManualInvalidCode;
            if (barcode_rules.Barcode.rejectionReason(normalised) != null) {
              return l10n.scanManualInvalidCode;
            }
            return null;
          },
          onFieldSubmitted: (String _) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.scanManualAdd),
        ),
      ],
    );
  }
}
