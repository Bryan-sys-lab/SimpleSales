import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../db/database_helper.dart';
import '../../models/models.dart';
import 'barcode_service.dart';

/// How a barcode reached the app.
enum ScanSource {
  /// A hardware wedge scanner: a device that behaves like a keyboard and types
  /// the digits into whatever has focus.
  wedge,

  /// The handset camera.
  camera,

  /// Typed or pasted by hand.
  manual,
}

/// One decoded code, already normalised.
///
/// [raw] is kept alongside the normalised form so the UI can show what the
/// scanner actually said when it does not resolve to a product — the owner
/// needs to see the label's code to know which label is wrong.
@immutable
class ScanResult {
  const ScanResult(
      {required this.raw, required this.normalised, required this.source});

  final String raw;
  final String normalised;
  final ScanSource source;

  bool get isEmpty => normalised.isEmpty;
}

/// Filters keyboard input down to wedge-scanner traffic.
///
/// The hard part of a wedge scanner is not decoding — the scanner has already
/// done that — it is *not mistaking a human for a scanner*. A cashier typing a
/// product name into the search box must never be read as a barcode, and a
/// cashier using the on-screen keyboard must never have the soft keyboard
/// swallowed by a scan handler.
///
/// Three signals separate the two, and all three are required:
///
///  1. the buffer is only fed by printable characters, so a stray modifier key
///     never poisons it;
///  2. the buffer is only considered on Enter, because a wedge always sends a
///     terminator and a human almost never finishes typing a 13-digit number
///     and presses Enter mid-word;
///  3. the character run since the last reset is *fast*. A human types at
///     200–400 ms per character; a wedge scanner delivers a label at
///     keyboard-scan rate, orders of magnitude faster. Timing is the signal
///     that survives a scanner configured for slow keystrokes, which defeats a
///     pure interval-per-character test.
class WedgeScannerBuffer {
  WedgeScannerBuffer({
    this.minLength = Barcode.minLength,
    this.maxLength = Barcode.maxLength,
    this.maxInterKeyGap = const Duration(milliseconds: 60),
    this.maxDuration = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int minLength;
  final int maxLength;

  /// The longest gap between two characters still counted as one scan.
  final Duration maxInterKeyGap;

  /// The longest a whole scan may take. A wedge reading a damaged label can
  /// retry for a while; a human pause-and-resume is not a scan.
  final Duration maxDuration;

  final DateTime Function() _clock;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _firstKeyAt;

  /// Characters buffered but not yet resolved.
  String get pending => _buffer.toString();

  /// Feeds one key event, returning a completed scan when the run terminated.
  ///
  /// Returns null for every keystroke that is not the end of a plausible scan,
  /// so the caller can pass everything through untouched. A wedge scanner
  /// typing into a focused search box will still appear in that box — which is
  /// why the screen disables the field before arming this.
  ScanResult? onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _resolve();
    }

    // A modifier key is *not* part of the code, and it must not disturb what
    // has already been captured: a Code-128 scanner configured to emit
    // uppercase sends shift with every letter, so treating shift as a reset
    // would make every alphanumeric scanner fail silently. Keys that cannot be
    // part of a label (arrows, backspace) do reset, because they mean the run
    // in progress was actually a human navigating the screen.
    if (_isModifier(key)) return null;
    if (_isIgnorable(key)) {
      _reset();
      return null;
    }

    final now = _clock();
    final char = _characterFor(event);
    if (char == null) {
      _reset();
      return null;
    }

    final firstKeyAt = _firstKeyAt;
    if (firstKeyAt == null) _firstKeyAt = now;
    final sinceLast =
        _buffer.isEmpty ? Duration.zero : now.difference(_lastKeyAt ?? now);
    final elapsed = now.difference(firstKeyAt ?? now);

    // Too slow to be a machine: this is a human, so the run is discarded and
    // the character that revealed it becomes the first of the *next* run.
    // Throwing that character away too would cost a real scanner a digit
    // whenever it retried a damaged label with a gap in the middle.
    if (_buffer.isNotEmpty &&
        (sinceLast > maxInterKeyGap || elapsed > maxDuration)) {
      _reset();
      _firstKeyAt = now;
    }

    _lastKeyAt = now;
    _buffer.write(char);

    // Over-long run: a stuck key or a wedge in a different keyboard layout.
    // Drop it now rather than growing without bound.
    if (_buffer.length > maxLength) _reset();
    return null;
  }

  DateTime? _lastKeyAt;

  /// Modifier keys carry no character and are legal *within* a scan.
  static bool _isModifier(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.capsLock;

  /// Keys that can never appear in a barcode, and that mean whatever was being
  /// captured was not a barcode at all.
  ///
  /// Escape is included here rather than in [_isModifier]: a scanner using an
  /// escape prefix/suffix would put its own configured bytes in the buffer, and
  /// the code would then be rejected as unprintable at the till. Excluding it
  /// from the ignorable set would mean a human pressing Escape mid-search
  /// silently continues the buffer.
  static bool _isIgnorable(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.backspace ||
      key == LogicalKeyboardKey.tab ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.home ||
      key == LogicalKeyboardKey.end ||
      key == LogicalKeyboardKey.pageUp ||
      key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.escape;

  /// The printable character an event carries, or null when it carries none.
  static String? _characterFor(KeyEvent event) {
    final char = event.character;
    if (char == null || char.isEmpty) return null;
    final code = char.codeUnitAt(0);
    // Control characters normally mean a shortcut rather than a label, with one
    // exception: GS1 scanners emit FNC1 (ASCII 29) as a real character to
    // separate variable-length fields. Rejecting it would kill every
    // GS1-formatted label, and `Barcode.normalise` strips it before the code is
    // ever compared or stored.
    if (code == Barcode.gs1Separator) return char;
    if (code < 0x20 || code == 0x7f) return null;
    return char;
  }

  ScanResult? _resolve() {
    final raw = _buffer.toString();
    _reset();
    if (raw.isEmpty) return null;
    final normalised = Barcode.normalise(raw);
    if (normalised.length < minLength || normalised.length > maxLength) {
      return null;
    }
    return ScanResult(
        raw: raw, normalised: normalised, source: ScanSource.wedge);
  }

  void _reset() {
    _buffer.clear();
    _firstKeyAt = null;
    _lastKeyAt = null;
  }

  void reset() => _reset();
}

/// Resolves a scanned code to a product, or explains why it did not.
///
/// The one place a scan becomes a cart action, so the wedge listener, the
/// camera screen and a hand-typed code all behave identically.
typedef ScanLookup = Future<ScanOutcome> Function(String normalised);

/// What a scan produced.
class ScanOutcome {
  const ScanOutcome._({
    required this.raw,
    required this.normalised,
    this.product,
    this.reason,
  });

  /// The code the scanner emitted.
  final String raw;
  final String normalised;

  /// The product it resolved to, or null.
  final Product? product;

  /// Why nothing resolved, when nothing did.
  final String? reason;

  bool get matched => product != null;

  /// [ScanLookup] builds one of these.
  factory ScanOutcome.found({
    required String raw,
    required String normalised,
    required Product product,
  }) =>
      ScanOutcome._(raw: raw, normalised: normalised, product: product);

  factory ScanOutcome.unmatched({
    required String raw,
    required String normalised,
    required String reason,
  }) =>
      ScanOutcome._(raw: raw, normalised: normalised, reason: reason);
}

/// Resolves codes against the local catalogue.
///
/// Offline by construction: a barcode lookup never touches the network, so a
/// scan works in exactly the conditions a sale does.
class BarcodeLookup {
  BarcodeLookup({ScanLookup? lookup}) : _lookup = lookup;

  final ScanLookup? _lookup;

  Future<ScanOutcome> resolve(ScanResult scan) async {
    final custom = _lookup;
    if (custom != null) return custom(scan.normalised);
    return resolveNormalised(scan.normalised, raw: scan.raw);
  }

  /// The database-backed resolution used in the app.
  static Future<ScanOutcome> resolveNormalised(String normalised,
      {String? raw}) async {
    final db = DatabaseHelper.instance;
    final product = await db.getProductByBarcode(normalised);
    if (product != null) {
      return ScanOutcome.found(
        raw: raw ?? normalised,
        normalised: normalised,
        product: product,
      );
    }
    final problem = Barcode.rejectionReason(normalised);
    return ScanOutcome.unmatched(
      raw: raw ?? normalised,
      normalised: normalised,
      reason: problem ??
          'No product carries that barcode. Add it in Inventory, or pick the '
              'product by name.',
    );
  }
}
