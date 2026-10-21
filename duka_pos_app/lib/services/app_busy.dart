// Whether the app is in the middle of something that must not be interrupted.
//
// A till signs itself out after fifteen minutes of no tapping — the idle
// guard, and a good idea on a counter. But an import is the one operation
// that is legitimately long AND silent: the owner picks a file and then
// watches, because there is nothing to tap.
//
// So the guard asks this first. An import in flight is not an idle till; it is
// a till doing the longest thing it does, and a session that ends in the
// middle of it is a half-imported catalogue and a locked screen.
//
// It is a counter rather than a flag because two things can be busy at once —
// an import and an update download — and a flag set twice and cleared once
// would let the guard through early.

/// Whether the app is busy with work that must not be interrupted.
class AppBusy {
  const AppBusy._();

  static int _depth = 0;

  /// Whether something is in flight.
  static bool get isBusy => _depth > 0;

  /// Marks the start of a long operation.
  static void begin() => _depth++;

  /// Marks its end.
  static void end() {
    if (_depth > 0) _depth--;
  }

  /// Runs [action] with the app marked busy, and unmarked whatever happens.
  ///
  /// The `finally` is the point: an operation that throws must not leave the
  /// till permanently "busy", or the idle guard would never sign it out again
  /// and the shop's till would be open to whoever walks past.
  static Future<T> during<T>(Future<T> Function() action) async {
    begin();
    try {
      return await action();
    } finally {
      end();
    }
  }
}
