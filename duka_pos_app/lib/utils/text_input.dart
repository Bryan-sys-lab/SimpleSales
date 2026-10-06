// Folding a soft keyboard's numerals into ASCII.
//
// A till is used on whatever phone the shop already owns, which in Kenya means
// Arabic and Persian keyboards are one tap away on the lock screen. A cashier
// who switches to one to type a price gets U+0660-U+0669 digits back, and
// `double.tryParse` returns null for every one of them — the app then reports
// "Enter a number, 0 or more" for a number that looks perfectly valid on the
// glass.
//
// This is the ONE place that fold happens. Every parse in the app goes through
// it, so adding a locale adds a digit block here rather than a guard at every
// field. The accepted-character patterns live here beside the fold, because a
// field that ACCEPTS only ASCII digits while the parser claims to understand
// Arabic ones is the worse bug of the two: the cashier simply cannot type.

/// The characters a money field accepts: ASCII digits, Arabic-Indic, Extended
/// Arabic-Indic, and the three separators a locale keyboard may produce.
///
/// Used as `FilteringTextInputFormatter.allow(userNumberPattern)`. Deliberately
/// not `digitsOnly`: that formatter is ASCII-only by name and would make every
/// field in this app unusable on a device whose keyboard is set to anything but
/// Latin.
final RegExp userNumberPattern = RegExp('[0-9٠-٩۰-۹.,٫٬\\u00A0\\u0020]');

/// The same, for a field that takes a whole count: no decimal separator.
final RegExp userDigitsPattern = RegExp('[0-9٠-٩۰-۹٬\\u00A0\\u0020]');

/// Rewrites any numeral system a soft keyboard can produce into ASCII digits and
/// ASCII separators.
///
/// Both halves are required, and the separator half is the one that bites:
///
///  * `١٢٣` (Arabic-Indic) and `۱۲۳` (Extended Arabic-Indic, Persian) are
///    DIFFERENT Unicode blocks. Folding digits but not separators leaves
///    `1٫5`, which parses as 15 in most parsers — a 10x error written into the
///    ledger.
///  * `٫` U+066B is the Arabic decimal separator and must become `.`.
///  * `٬` U+066C is the Arabic thousands separator and must be DROPPED, never
///    translated to a comma: a comma is not the decimal point, and a value that
///    arrived as `1٬200` is one thousand two hundred, not one point two.
///
/// Everything else passes through untouched, so a product name, a reference code
/// or an email address is never mangled by a call to this function.
String normalizeToAsciiNumerals(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      // Arabic-Indic ٠-٩ (U+0660-0669) -> 0-9.
      out.writeCharCode(0x30 + (rune - 0x0660));
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      // Extended Arabic-Indic / Persian ۰-۹ (U+06F0-06F9) -> 0-9.
      out.writeCharCode(0x30 + (rune - 0x06F0));
    } else if (rune == 0x066B) {
      out.write('.');
    } else if (rune == 0x066C) {
      continue;
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Parses an amount a user typed, or null when it is not one.
///
/// Null rather than a throw or a zero: every caller has to decide what an
/// unusable figure means (reject the field, keep the previous value, refuse to
/// save), and that decision does not belong in a parse.
///
/// A grouping comma or space is stripped rather than rejected, because it is
/// how most people type `1,000` and refusing it reads as a broken keyboard.
double? parseUserNumber(String raw) {
  final String folded = normalizeToAsciiNumerals(raw.trim())
      .replaceAll(',', '')
      // Non-breaking space first: a phone keyboard's number row and most
      // "1 000" conventions insert U+00A0, not U+0020.
      .replaceAll('\u00A0', '')
      .replaceAll('\u0020', '');
  if (folded.isEmpty) return null;
  return double.tryParse(folded);
}

/// Parses a whole number a user typed: a pile count, a quantity, a reorder
/// level.
///
/// Not [parseUserNumber]'s `double` cast, because "3.5 bottles" is a legitimate
/// stock quantity in this app and must not be silently truncated to 3 on the way
/// into the ledger.
int? parseUserCount(String raw) {
  final double? value = parseUserNumber(raw);
  if (value == null) return null;
  if (value != value.roundToDouble()) return null;
  return value.toInt();
}
