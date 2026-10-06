import 'dart:math' as math;
import 'dart:typed_data';

import 'receipt_builder.dart';

/// Turns a laid-out receipt into ESC/POS bytes.
///
/// Pure: a list of [ReceiptLine] in, a byte list out. There is no socket, no
/// printer and no state here, so the byte output can be asserted in a unit test
/// on a machine that has never seen a thermal printer.
///
/// Command reference is the ESC/POS "Model 2" dialect every 58mm receipt
/// printer in this market implements (Epson TM-series clones in particular).
/// Dialects differ, which is why the printer to target is the one the shop
/// actually owns and not a datasheet.
class EscPosEncoder {
  const EscPosEncoder();

  static const int _esc = 0x1b;
  static const int _gs = 0x1d;
  static const int _lf = 0x0a;

  /// Initialise the printer: reset modes, clear the buffer.
  static const List<int> _initialise = [_esc, 0x40];

  /// Print and feed `n` lines.
  static List<int> _feed(int lines) => [_esc, 0x64, lines.clamp(0, 255)];

  static List<int> _align(ReceiptAlignment alignment) => [
        _esc,
        0x61,
        switch (alignment) {
          ReceiptAlignment.left => 0,
          ReceiptAlignment.center => 1,
          ReceiptAlignment.right => 2,
        },
      ];

  static List<int> _bold(bool on) => [_esc, 0x45, on ? 1 : 0];

  /// Character magnification. Width lives in the low nibble, height in the high
  /// nibble, each as "scale minus one".
  static List<int> _scale(int scale) => [
        _gs,
        0x21,
        (scale.clamp(1, 2) - 1) | ((scale.clamp(1, 2) - 1) << 4),
      ];

  /// Advance the paper to the cut position and cut.
  ///
  /// There is deliberately no cash-drawer kick here: the drawer pulse is a
  /// different pin on the same port, and driving it from a receipt would open
  /// the drawer on every reprint.
  static const List<int> _cut = [_gs, 0x56, 0x42, 0x00];

  /// Encodes [lines] for one receipt, ending with a paper cut.
  ///
  /// [columnBudget] must be the same budget the builder laid the receipt out
  /// against. It is passed again rather than stored on each line because it is
  /// a property of the paper the printer is loaded with, not of the content —
  /// the same layout object prints correctly on 58mm or 80mm.
  Uint8List encode(
    List<ReceiptLine> lines, {
    int columnBudget = k58mmColumnBudget,
  }) {
    final out = BytesBuilder(copy: false);

    void emit(List<int> bytes) => out.add(bytes);

    void emitText(ReceiptLine line) {
      emit(_encodeText(line.render(columnBudget)));
      emit(const [_lf]);
    }

    emit(_initialise);
    emit(_align(ReceiptAlignment.left));
    emit(_bold(false));
    emit(_scale(1));

    for (final line in lines) {
      switch (line) {
        case ReceiptText():
          emit(_align(line.alignment));
          emit(_bold(line.bold));
          emit(_scale(line.scale));
          emitText(line);
          emit(_bold(false));
          emit(_scale(1));
        case ReceiptColumns():
          emit(_align(ReceiptAlignment.left));
          emit(_bold(line.bold));
          emitText(line);
          emit(_bold(false));
        case ReceiptRule():
          emit(_align(ReceiptAlignment.left));
          emitText(line);
        case ReceiptFeed():
          // A one-line feed is the line feed that ends the previous text line,
          // so only the extra lines need an explicit command.
          final extra = math.max(0, line.lines - 1);
          if (extra > 0) emit(_feed(extra));
        case ReceiptQr():
          emit(_align(ReceiptAlignment.center));
          emit(_qr(line.payload, moduleSize: line.moduleSize));
      }
    }

    emit(_feed(3));
    emit(_cut);
    return out.takeBytes();
  }

  /// Byte output for text.
  ///
  /// ESC/POS's default code page is single-byte, so the payload is emitted as
  /// Latin-1. Characters outside that range — an emoji in a product name, a
  /// character in an Indic script — become `?` rather than throwing: a mangled
  /// character on a receipt is recoverable, and a receipt that fails to print
  /// because of one is not.
  static List<int> _encodeText(String text) {
    final normalised = text
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u00b7', '-')
        .replaceAll('\u2026', '...');
    final out = <int>[];
    for (final unit in normalised.codeUnits) {
      out.add(unit <= 0xff ? unit : 0x3f /* '?' */);
    }
    return out;
  }

  /// Model 2 QR: select model, set module size, store the payload, print.
  ///
  /// The length fields are `(len + 3) / 256` and `(len + 3) % 256`, where the
  /// three is the `pL pH cn fn` header. Getting that wrong is the classic way
  /// to emit a QR that decodes to a truncated URL, which would verify against
  /// the wrong receipt — silently, because a truncated URL usually still loads.
  static List<int> _qr(String payload, {required int moduleSize}) {
    final data = _encodeText(payload);
    if (data.isEmpty) return const [];
    final length = data.length + 3;
    return [
      _gs, 0x28, 0x6b, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // model 2
      _gs, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, moduleSize.clamp(1, 16), // size
      _gs, 0x28, 0x6b, length ~/ 256, length % 256, 0x31, 0x50, 0x30, ...data,
      _gs, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30, // print
    ];
  }
}
