/// Barcode normalisation and validation.
///
/// Pure string logic, kept away from the scanner and the database so the rules
/// that decide "is this code real?" can be tested exhaustively without a
/// handset. Every rule here exists because getting it wrong silently merges two
/// different products at the till.
class Barcode {
  const Barcode._();

  /// GS1 FNC1, the group separator between variable-length AI fields.
  ///
  /// Some scanners emit it as a real byte (ASCII 29) and some render it as an
  /// invisible character, so it has to be stripped before anything is compared.
  static const int gs1Separator = 0x1d;

  /// The shortest code accepted. Below this a stuck scanner firing keystrokes
  /// would fill the catalogue with two-digit noise.
  static const int minLength = 6;

  /// The longest code accepted. A barcoded excise serial is well inside this;
  /// nothing legitimate is close, and an unbounded column lets a malfunctioning
  /// wedge scanner write megabytes per scan.
  static const int maxLength = 64;

  /// GTIN lengths that share the mod-10 check digit.
  static const Set<int> gtinLengths = {8, 12, 13, 14};

  /// The canonical form of a scanned or typed code.
  ///
  /// Scanners emit what the label encoded, which is not what gets typed or
  /// stored, so this runs before *every* comparison and before every write.
  /// In order:
  ///
  ///  1. strip the GS1 FNC1 group separator, including the `<GS>` notation some
  ///     drivers emit in its place;
  ///  2. strip all whitespace and hyphens — humans add them, labels do not;
  ///  3. trim;
  ///  4. uppercase.
  ///
  /// Uppercasing matters because an alphanumeric Code-128 scanned in lowercase
  /// would otherwise never match a stored uppercase value, and the cashier
  /// would be told the product is unknown while standing in front of it.
  ///
  /// Leading zeros are deliberately preserved. `0123456789012` and
  /// `123456789012` are different products, and anything that routes a code
  /// through `int` drops the zeros and merges them. That is why nothing in the
  /// barcode path is allowed to touch `num`.
  static String normalise(String raw) {
    final withoutGroupSeparator = raw
        .replaceAll('<GS>', '')
        .replaceAll(String.fromCharCode(gs1Separator), '');
    final withoutSeparators =
        withoutGroupSeparator.replaceAll(RegExp(r'[\s\-]'), '');
    return withoutSeparators.trim().toUpperCase();
  }

  /// Whether [code] (already normalised) is a GTIN this app can check.
  static bool isGtin(String code) =>
      gtinLengths.contains(code.length) && _isAllDigits(code);

  static bool _isAllDigits(String value) =>
      value.isNotEmpty && RegExp(r'^\d+$').hasMatch(value);

  /// Whether [code] (already normalised) satisfies every structural rule.
  ///
  /// Validation is *by length family, rejected by charset*:
  ///
  ///  - a digit-only code of a GTIN length gets its check digit verified, and a
  ///    bad one is rejected here — at entry, with a message, rather than as a
  ///    mysterious miss at the till;
  ///  - a digit-only code of some other length is accepted without a check
  ///    digit test, because refusing it would reject a real code over a rule
  ///    the owner cannot see;
  ///  - an alphanumeric code is accepted unchecked, because an owner assigning
  ///    their own Code-128 value cannot be told their code is invalid on the
  ///    authority of a rule they have no way to satisfy.
  static bool isValid(String code) {
    if (code.length < minLength || code.length > maxLength) return false;
    if (_isAllDigits(code)) {
      if (!isGtin(code)) return true;
      return hasValidCheckDigit(code);
    }
    // Alphanumeric: restricted to the characters a Code-128 or DataMatrix
    // symbol can actually encode, so a keyboard mishap cannot be stored as a
    // "barcode" that no scanner will ever produce.
    return RegExp(r'^[A-Z0-9\-. $/+:=%_]+$').hasMatch(code);
  }

  /// The mod-10 (GS1) check digit for [code].
  ///
  /// Weights alternate 3,1 from the rightmost digit of the payload, and the
  /// check digit is whatever brings the total up to the next multiple of ten.
  static int checkDigit(String payload) {
    var sum = 0;
    var weight = 3;
    for (var i = payload.length - 1; i >= 0; i--) {
      sum += (payload.codeUnitAt(i) - 0x30) * weight;
      weight = weight == 3 ? 1 : 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  /// Whether [code]'s final digit is the correct check digit for its payload.
  static bool hasValidCheckDigit(String code) {
    if (code.isEmpty || !_isAllDigits(code)) return false;
    final payload = code.substring(0, code.length - 1);
    final stated = code.codeUnitAt(code.length - 1) - 0x30;
    return checkDigit(payload) == stated;
  }

  /// Why [code] was refused, for a message the owner can act on.
  ///
  /// Null when the code is fine. Distinct from `isValid` because "this code is
  /// not valid" is useless at a till and "that EAN's check digit is wrong —
  /// check you typed the last digit" is not.
  static String? rejectionReason(String code) {
    if (code.isEmpty) return 'Enter a barcode';
    if (code.length < minLength) {
      return 'A barcode must be at least $minLength characters';
    }
    if (code.length > maxLength) {
      return 'A barcode must be $maxLength characters or fewer';
    }
    if (_isAllDigits(code)) {
      if (isGtin(code) && !hasValidCheckDigit(code)) {
        return "That barcode's check digit is wrong - check the last digit";
      }
      return null;
    }
    if (!RegExp(r'^[A-Z0-9\-. $/+:=%_]+$').hasMatch(code)) {
      return 'A barcode may only use letters, digits and - . / \$ + : = % _';
    }
    return null;
  }
}
