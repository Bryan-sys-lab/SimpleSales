// Projecting a stored ISO timestamp into words a person reads.
//
// Two rules, both learned the hard way in POS software:
//
//   * **Never throw.** A timestamp this app did not write — a restored backup
//     from an older build, a row a spreadsheet importer produced — must not be
//     the reason a cashier cannot see their shift. An unparseable value comes
//     back as itself, which is ugly and honest; an exception is neither.
//   * **Project, never store.** What is in the database is an ISO-8601 instant.
//     Its wording, its ordering and its calendar are decided here, at the
//     render edge, from the locale in scope. Nothing here writes back.
//
// The optional [locale] exists so a translated app gets a translated date
// without any call site learning an `intl` API: a caller that has a
// `BuildContext` passes `Localizations.localeOf(context).toString()` and never
// touches this file again.

import 'package:intl/intl.dart';

/// The instant a shift opened, as the owner reads it: "4 Oct, 14:32".
///
/// Falls back to the stored value rather than a placeholder, because a row this
/// app cannot date is still a real shift and hiding it is worse than showing it
/// raw.
String formatInstant(String iso, {String? locale}) {
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return _format(parsed.toLocal(), 'd MMM, HH:mm', locale);
}

/// The window a shift covers, as "4 Oct, 14:32 – 19:05".
///
/// The closing time is deliberately WITHOUT the date. A shift that starts at
/// 23:00 and ends at 01:10 crosses midnight, and printing "5 Oct, 01:10" beside
/// "4 Oct, 23:00" reads as if the shift ran backwards. Repeating the date on a
/// same-day window is pure noise; on a window that actually crossed midnight the
/// date matters more than the tidiness, so the second date is printed and the
/// narrow case is the one that pays.
String formatWindow({
  required String startIso,
  String? endIso,
  String? locale,
}) {
  final DateTime? start = DateTime.tryParse(startIso);
  if (start == null) return startIso;

  final DateTime? end =
      (endIso == null || endIso.isEmpty) ? null : DateTime.tryParse(endIso);
  if (end == null) return formatInstant(startIso, locale: locale);

  final DateTime localStart = start.toLocal();
  final DateTime localEnd = end.toLocal();
  final bool crossesMidnight = localEnd.day != localStart.day;

  return crossesMidnight
      ? '${_format(localStart, 'd MMM, HH:mm', locale)} – '
          '${_format(localEnd, 'd MMM, HH:mm', locale)}'
      : '${_format(localStart, 'd MMM, HH:mm', locale)} – '
          '${_format(localEnd, 'HH:mm', locale)}';
}

/// Builds a formatter, degrading to the English pattern rather than throwing.
///
/// `DateFormat` throws for a locale `intl` carries no calendar data for, and it
/// throws while PAINTING — inside a `build`, on the frame a row appears. The
/// fallback is a deliberate over-approximation: showing a Latin-pattern date to
/// one user is a defect; crashing the screen for all of them is not a trade this
/// function is allowed to make on its own.
String _format(DateTime local, String pattern, String? locale) {
  if (locale != null) {
    try {
      return DateFormat(pattern, locale).format(local);
    } on Exception {
      // Falls through to the pattern below rather than returning nothing: a
      // date in the wrong language is still a date.
    }
  }
  return DateFormat(pattern).format(local);
}
