import 'dart:typed_data';

import 'esc_pos_encoder.dart';
import 'esc_pos_printer.dart';
import 'printer_config.dart';
import 'printer_service.dart';

/// Best-effort drawer control behind the same paired printer as receipts.
/// Drawer failure never turns a completed sale into a failed sale.
class CashDrawerService {
  CashDrawerService({PrinterService? printer})
      : _printer = printer ?? EscPosPrinter();

  final PrinterService _printer;

  Future<bool> open({int pin = 0, int onMs = 50, int offMs = 500}) async {
    final config = await PrinterConfig.load();
    if (!config.isConfigured) return false;
    try {
      await _printer.connect(config.macAddress);
      await _printer.send(Uint8List.fromList(EscPosEncoder.drawerPulse(
        pin: pin,
        onMs: onMs,
        offMs: offMs,
      )));
      return true;
    } on PrinterException {
      return false;
    }
  }
}
