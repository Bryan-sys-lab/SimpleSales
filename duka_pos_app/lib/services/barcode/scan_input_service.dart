import 'dart:async';

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

/// The live channel between a camera scan and the till that opened it.
///
/// The camera screen does not stop to ask the till what to do with a code: it
/// reads one, hands it over, and keeps reading. That means the till has to
/// receive codes WHILE the scanner is open, not as a bundle when it closes —
/// so the two share a session, and the session IS the channel.
///
/// The till creates the session, hands it to the scanner route, and adds each
/// code to the cart as it arrives. The scanner never writes to the cart: it
/// does not know what a code means, and a scanner that resolved products would
/// give the app two answers to "what does this barcode mean?".
class ScanSession {
  ScanSession();

  final StreamController<ScanResult> _codes =
      StreamController<ScanResult>.broadcast();

  /// The codes, as they are read.
  Stream<ScanResult> get codes => _codes.stream;

  int _count = 0;

  /// How many codes have been read through this session.
  int get count => _count;

  /// Hands a code to the till.
  ///
  /// A code handed over after the session is closed is dropped rather than
  /// thrown: the scanner may still be shutting down when the till gives up on
  /// it, and a scan that arrives after the till stopped listening is a scan
  /// nobody wants.
  void add(ScanResult result) {
    if (_codes.isClosed) return;
    _count++;
    _codes.add(result);
  }

  /// Closes the channel. The till owns the session, so the till closes it.
  Future<void> dispose() => _codes.close();
}

/// How long a scanned code must be OUT OF VIEW before the camera will read it
/// again.
///
/// Half a second, and the reason is the platform's own throttle: a camera
/// reports the same label every 250ms for as long as that label stays in
/// frame. Half a second is twice that interval, so a label held in frame is
/// read exactly once and stays read-once however fast the frames come — and it
/// is still short enough that a till reads two items a second, three times
/// faster than the one item a second a till actually needs.
const Duration kScanRereadWindow = Duration(milliseconds: 500);

/// The camera's re-read guard.
///
/// A camera reports the same label over and over: the platform's throttle lets
/// a code through every 250ms for as long as the label stays in frame. A till
/// that added every one of those would charge the customer three times for one
/// item, so a code is only accepted again after it has been OUT OF VIEW for
/// [window].
///
/// The rule is deliberately about being SEEN rather than about being ACCEPTED:
/// a code still in frame is seen on every frame, and that is exactly what
/// keeps it suppressed until the cashier takes it away.
class ScanGate {
  ScanGate({this.window = kScanRereadWindow, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// How long a code must be out of view before it counts again.
  final Duration window;

  final DateTime Function() _clock;

  /// When each code was last SEEN.
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  /// Whether [code] is a NEW reading, rather than the same label again.
  bool accept(String code) {
    final DateTime now = _clock();
    _forget(now);
    final DateTime? seen = _lastSeen[code];
    _lastSeen[code] = now;
    if (seen == null) return true;
    return now.difference(seen) >= window;
  }

  /// Drops the codes that have been out of view long enough to be forgotten.
  ///
  /// Without this the map would grow for as long as the till is open, holding
  /// one entry per code the shop has ever scanned.
  void _forget(DateTime now) {
    _lastSeen.removeWhere(
      (String code, DateTime seen) => now.difference(seen) >= window,
    );
  }
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
