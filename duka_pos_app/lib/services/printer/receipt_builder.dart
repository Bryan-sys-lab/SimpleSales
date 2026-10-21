import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../utils/money.dart';

/// Characters printable at the default ESC/POS font on a 58mm roll.
///
/// Every fixed-width font is 32 characters across a 58mm paper at its default
/// pitch; 80mm is 48. This is the budget the builder lays the receipt out
/// against, so a long product name is truncated by *us* rather than wrapping
/// half-way through the price by the printer.
const int k58mmColumnBudget = 32;
const int k80mmColumnBudget = 48;

/// Kenya's standard VAT rate. Zero is a valid shop setting and means the goods
/// are exempt, in which case the receipt carries no VAT lines at all rather
/// than a line reading "VAT 0.00".
const int kDefaultVatRatePercent = 16;

/// One printed line of a receipt.
///
/// This is the hand-off point between [ReceiptBuilder] (which decides what the
/// receipt says) and [EscPosEncoder] (which decides how ESC/POS says it). The
/// builder is pure and the encoder is pure, so the layout can be asserted in a
/// unit test without a printer and the bytes can be asserted without a layout.
sealed class ReceiptLine {
  const ReceiptLine();

  /// The line as it will be printed, for tests and for the on-screen preview.
  String render(int columnBudget);
}

/// Free text on one line.
final class ReceiptText extends ReceiptLine {
  const ReceiptText(
    this.text, {
    this.alignment = ReceiptAlignment.left,
    this.bold = false,
    this.scale = 1,
  });

  final String text;
  final ReceiptAlignment alignment;
  final bool bold;

  /// Character magnification, 1 or 2. Only the shop name uses 2.
  final int scale;

  @override
  String render(int columnBudget) =>
      _fit(text, columnBudget ~/ scale, alignment);
}

/// A left-hand label and a right-hand figure on the same physical line.
///
/// This is the shape of every money line on a receipt, and it is why the
/// builder owns the truncation policy: an amount that wraps onto the next line
/// is unreadable and, worse, ambiguous about which item it belongs to.
final class ReceiptColumns extends ReceiptLine {
  const ReceiptColumns(this.left, this.right, {this.bold = false});

  final String left;
  final String right;
  final bool bold;

  @override
  String render(int columnBudget) {
    // The right-hand figure is never truncated mid-number: it is the number the
    // customer is checking. But it is CLAMPED, and that guard is new.
    //
    // When the figure alone is wider than the paper — a long staff name, a long
    // confirmation reference, a long eTIMS number — `rightWidth` becomes
    // `columnBudget` and `room` becomes -1. Both `padRight(-1)` and
    // `padLeft(-1)` return their input unchanged, because Dart guards
    // `delta <= 0`. So the emitted line was the FULL right string, i.e.
    // `right.length - columnBudget` characters over the paper, and the printer
    // wrapped the amount onto the next physical line: unreadable, and
    // ambiguous about which item it belonged to — the exact failure the class
    // doc describes, just reached from the other side.
    //
    // The clamp keeps the TRAILING characters, which is where a reference or a
    // check digit lives.
    final shownRight =
        right.length <= columnBudget ? right : _keepTail(right, columnBudget);
    final rightWidth = shownRight.length;
    final room = columnBudget - rightWidth - 1;
    final trimmed = room <= 0 ? '' : _truncateEnd(left, room);
    return trimmed.padRight(room.clamp(0, columnBudget)) +
        shownRight.padLeft(rightWidth);
  }
}

/// A horizontal rule the width of the paper.
final class ReceiptRule extends ReceiptLine {
  const ReceiptRule({this.character = '-'});

  final String character;

  @override
  String render(int columnBudget) => character * columnBudget;
}

/// Blank paper, for spacing blocks apart.
final class ReceiptFeed extends ReceiptLine {
  const ReceiptFeed([this.lines = 1]);

  final int lines;

  @override
  String render(int columnBudget) => '\n' * (lines - 1);
}

/// A QR code. Carries the eTIMS verification payload when the shop has eTIMS
/// switched on, and nothing otherwise.
final class ReceiptQr extends ReceiptLine {
  const ReceiptQr(this.payload, {this.moduleSize = 4});

  final String payload;

  /// QR module size in printer dots. 4 is legible at 58mm for a payload this
  /// long; printers clamp it themselves when a code will not fit the roll.
  final int moduleSize;

  @override
  String render(int columnBudget) => '[qr:${payload.length}]';
}

enum ReceiptAlignment { left, center, right }

/// Everything the receipt says, as a value.
///
/// Deliberately a plain value with no reference to `AppState`, the database, or
/// the theme: that is what keeps [ReceiptBuilder] a pure function of its
/// argument, and therefore testable without a till.
@immutable
class ReceiptInput {
  const ReceiptInput({
    required this.shopName,
    required this.receiptNumber,
    required this.issuedAt,
    required this.cashierName,
    required this.cashierRole,
    required this.items,
    required this.total,
    required this.amountTendered,
    required this.changeGiven,
    this.paymentMethodLabel = 'Cash',
    this.vatRatePercent = kDefaultVatRatePercent,
    this.pricesIncludeVat = true,
    this.etimsReceiptNumber,
    this.etimsVerificationPayload,
    this.etimsPending = false,
  });

  final String shopName;
  final String receiptNumber;
  final DateTime issuedAt;
  final String cashierName;
  final String cashierRole;
  final List<SaleItem> items;

  /// The recorded sale total. The builder prints this figure and asserts the
  /// printed item lines sum to it, rather than recomputing it and hoping the
  /// two agree — the recorded total is what the ledger and the till agree on.
  final Money total;
  final Money amountTendered;
  final Money changeGiven;
  final String paymentMethodLabel;

  /// Whole percent. Zero is valid and means exempt.
  final int vatRatePercent;

  /// Whether prices already include VAT. When false, VAT is added on top of
  /// the printed line totals rather than extracted from them.
  final bool pricesIncludeVat;

  final String? etimsReceiptNumber;
  final String? etimsVerificationPayload;

  /// When the inline eTIMS attempt timed out, the receipt prints a pending
  /// line instead of a QR so the customer knows the invoice is still coming.
  final bool etimsPending;

  bool get isVatExempt => vatRatePercent == 0;
}

/// Lays a receipt out as a list of printable lines.
///
/// Pure: same input, same output, no clock, no I/O, no globals. Every customer-
/// facing string on the receipt lives in this one file, so adding a language
/// later is a single-file change rather than a hunt through the screens.
class ReceiptBuilder {
  const ReceiptBuilder({this.columnBudget = k58mmColumnBudget});

  final int columnBudget;

  /// Builds the receipt.
  ///
  /// Lines are emitted as a flat list rather than a tree so the encoder can
  /// stream them and a test can assert the exact print order.
  List<ReceiptLine> build(ReceiptInput input) {
    assert(input.items.isNotEmpty,
        'a receipt with no item lines is not a receipt');
    assert(input.vatRatePercent >= 0, 'a negative VAT rate is not a rate');
    assert(columnBudget >= ReceiptBuilder.minimumColumnBudget,
        'a receipt this narrow cannot hold a price and a label');

    final lines = <ReceiptLine>[];

    lines.add(ReceiptText(_oneLine(input.shopName),
        alignment: ReceiptAlignment.center,
        bold: true,
        scale: input.shopName.trim().length <= columnBudget ~/ 2 ? 2 : 1));
    lines.add(
        const ReceiptText('SALES RECEIPT', alignment: ReceiptAlignment.center));

    lines.add(const ReceiptRule());
    lines.add(ReceiptColumns('Date', _date(input.issuedAt)));
    lines.add(ReceiptColumns('Receipt No.', input.receiptNumber));
    if (input.cashierName.trim().isNotEmpty) {
      lines.add(ReceiptColumns('Served by',
          '${_oneLine(input.cashierName)} (${input.cashierRole})'));
    }
    lines.add(const ReceiptRule());

    // Itemised lines, then the VAT figure, per line.
    //
    // The per-line VAT is printed rather than a single derived-from-the-total
    // figure because an auditor adds up what is printed. Summing the printed
    // components is what makes the VAT line reconcile with the printed total.
    var printedLineTotal = Money.zero;
    var printedVatTotal = Money.zero;
    for (final item in input.items) {
      final lineTotal = item.total;
      final vat = vatComponentOf(lineTotal,
          ratePercent: input.vatRatePercent,
          pricesIncludeVat: input.pricesIncludeVat);
      printedLineTotal = printedLineTotal + lineTotal;
      printedVatTotal = printedVatTotal + vat;

      lines.add(ReceiptColumns(_lineLabel(item), _money(lineTotal)));
      lines.add(ReceiptColumns(
        '  ${_qty(item.qty)} x ${_money(item.unitPrice)}',
        input.isVatExempt ? '' : 'VAT ${_money(vat)}',
      ));
    }

    // The recorded total is the authority. If the printed lines and the
    // recorded total disagree, the receipt is wrong whichever one it prints,
    // so the mismatch is thrown in development and the recorded figure is
    // printed in production rather than a total that matches nothing.
    assert(printedLineTotal == input.total,
        'printed item lines must sum to the recorded sale total');

    lines.add(const ReceiptRule());
    lines.add(ReceiptColumns('Subtotal', _money(input.total)));
    if (!input.isVatExempt) {
      lines.add(ReceiptColumns(
          'VAT (${input.vatRatePercent}%)', _money(printedVatTotal)));
    }
    lines.add(const ReceiptRule());
    lines.add(ReceiptColumns('TOTAL', _money(input.total), bold: true));
    lines.add(
        ReceiptColumns(input.paymentMethodLabel, _money(input.amountTendered)));
    if (!input.changeGiven.isZero) {
      lines.add(ReceiptColumns('Change', _money(input.changeGiven)));
    }

    if (input.etimsReceiptNumber != null &&
        input.etimsReceiptNumber!.trim().isNotEmpty) {
      lines.add(const ReceiptRule());
      lines.add(ReceiptColumns('eTIMS No.', input.etimsReceiptNumber!));
      if (input.etimsVerificationPayload != null &&
          input.etimsVerificationPayload!.trim().isNotEmpty) {
        lines.add(const ReceiptText('Scan to verify',
            alignment: ReceiptAlignment.center));
        lines.add(ReceiptQr(input.etimsVerificationPayload!));
      } else if (input.etimsPending) {
        lines.add(const ReceiptText('eTIMS pending — official copy reprints',
            alignment: ReceiptAlignment.center));
      }
    } else if (input.etimsPending) {
      lines.add(const ReceiptRule());
      lines.add(const ReceiptText('eTIMS pending — official copy reprints',
          alignment: ReceiptAlignment.center));
    }

    lines.add(const ReceiptFeed());
    lines.add(const ReceiptText('Thank you for your business',
        alignment: ReceiptAlignment.center));
    lines.add(const ReceiptText('Goods once sold are not returnable',
        alignment: ReceiptAlignment.center));

    return lines;
  }

  /// Narrowest layout that can still hold a label, a figure and the gap
  /// between them. Below this a money line cannot be rendered at all, which is
  /// why it is asserted rather than silently producing a truncated total.
  static const int minimumColumnBudget = 12;

  String _lineLabel(SaleItem item) {
    final portion = _portionSuffix(item);
    final raw =
        item.productName.trim().isEmpty ? 'Item' : item.productName.trim();
    final base = _oneLine(raw);
    return portion.isEmpty ? base : '$base ($portion)';
  }

  static String _portionSuffix(SaleItem item) {
    switch (item.portion) {
      case 'half':
        return 'half';
      case 'quarter':
        return 'quarter';
      case 'measured':
        return '${item.portionMl}ml';
      default:
        return '';
    }
  }

  static String _qty(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);

  /// Receipt money is fixed-width by design: two decimals, no thousands
  /// separator.
  ///
  /// A grouping separator changes the character count with the magnitude of the
  /// figure, which would make the column budget unpredictable exactly where it
  /// matters most — the thousands case — and a comma or period is itself a
  /// symbol in some printer code pages.
  static String _money(Money amount) {
    final negative = amount.isNegative;
    final abs = negative ? Money.fromMinor(-amount.minorUnits) : amount;
    final major = abs.minorUnits ~/ kMinorUnitsPerMajor;
    final minor = abs.minorUnits % kMinorUnitsPerMajor;
    final text = '$major.${minor.toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  static String _date(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(when.day)}-${two(when.month)}-${when.year} '
        '${two(when.hour)}:${two(when.minute)}';
  }

  /// Collapses whitespace so a name containing a newline cannot break the
  /// receipt's fixed line structure.
  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _fit(String text, int width, ReceiptAlignment alignment) {
  final trimmed = text.length <= width ? text : _truncateEnd(text, width);
  switch (alignment) {
    case ReceiptAlignment.left:
      return trimmed;
    case ReceiptAlignment.center:
      final pad = width - trimmed.length;
      final left = (pad ~/ 2).clamp(0, pad);
      return ' ' * left + trimmed + ' ' * (pad - left);
    case ReceiptAlignment.right:
      return trimmed.padLeft(width);
  }
}

/// Trims from the *end* and marks the cut with an ellipsis, so a reader can see
/// that text was dropped rather than silently believing a name ended there.
String _truncateEnd(String text, int width) {
  if (text.length <= width) return text;
  if (width <= 3) return text.substring(0, width.clamp(0, text.length));
  return '${text.substring(0, width - 3)}...';
}

/// Keeps the *tail* of [text] to [width] characters.
///
/// The counterpart to [_truncateEnd], for the right-hand column. A reference or
/// a check digit lives at the END of the string, so that is the end to keep:
/// an M-Pesa reference truncated from the left still identifies the
/// transaction, while one truncated from the right does not.
String _keepTail(String text, int width) {
  if (text.length <= width) return text;
  if (width <= 3) return text.substring(text.length - width);
  return '...${text.substring(text.length - (width - 3))}';
}
