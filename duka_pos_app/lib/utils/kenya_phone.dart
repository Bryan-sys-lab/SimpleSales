/// Kenyan phone numbers: how the shop types them in, how the app keeps them.
///
/// One normalisation for every phone a shop writes down — a supplier's number
/// on a delivery, a customer's number on an account — because "0712 345 678",
/// "+254712345678" and "254712345678" are all the same person, and three ways
/// of storing that would make the shop's book three ways of disagreeing.
library;

/// Canonicalises a Kenyan number to +2547…/+2541…, or null when it is not one.
///
/// Accepts the three ways the shop types a number: local `07…`/`01…` (nine
/// digits), national `254…` (twelve), and international `+254…`. Spaces, dashes
/// and stray punctuation between digits are fine; anything else — too short,
/// letters, a foreign calling code — is refused, not guessed at. Null in (no
/// number typed) is null out, so an optional field stays optional.
String? normaliseKenyanPhone(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return null;
  String body;
  if (digits.startsWith('254')) {
    body = digits.substring(3);
  } else if (digits.startsWith('0')) {
    // The local form: a leading trunk 0 before the subscriber number.
    body = digits.substring(1);
  } else if (digits.startsWith('7') || digits.startsWith('1')) {
    // Typed without the trunk: 712 345 678.
    body = digits;
  } else {
    return null;
  }
  // A Kenyan subscriber number is nine digits: 7XXXXXXXX or 1XXXXXXXX.
  if (body.length != 9) return null;
  if (body.startsWith('0')) return null;
  return '+254$body';
}

/// How the shop shows a +254… number: the familiar 07…/01… local form.
///
/// Canonical numbers are for LINKS (wa.me, sms:) because they survive the
/// phone's own dialling conventions; the display form is for people reading
/// the list, who read "0712…" far faster than "+254712…".
String phoneDisplayForm(String canonical) {
  if (canonical.startsWith('+254') && canonical.length == 13) {
    return '0${canonical.substring(4)}';
  }
  return canonical;
}

/// Builds the phone part of a share link from the canonical number: bare
/// digits for `https://wa.me/<digits>`, and the canonical signed form for
/// `sms:<number>`. Null when there is no number to share to.
String? phoneComposeTarget(String? canonicalPhone, {required bool whatsapp}) {
  final digits = canonicalPhone?.replaceAll(RegExp(r'[^\d]'), '');
  if (digits == null || digits.isEmpty) return null;
  return whatsapp ? digits : canonicalPhone;
}
