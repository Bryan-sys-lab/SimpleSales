import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_builder.dart';

/// Paper the printer is loaded with.
///
/// A setting rather than a constant because a shop that loads 80mm roll should
/// not have its prices wrap onto a second line, and because the cheap printers
/// sold alongside 58mm ones are frequently mislabelled by the shop that bought
/// them.
enum PrinterPaperWidth {
  mm58(58, k58mmColumnBudget),
  mm80(80, k80mmColumnBudget);

  const PrinterPaperWidth(this.mm, this.columnBudget);

  final int mm;

  /// Characters across the roll at the printer's default font.
  final int columnBudget;

  static PrinterPaperWidth fromName(String? name) => values.firstWhere(
        (width) => width.name == name,
        orElse: () => PrinterPaperWidth.mm58,
      );
}

/// The shop's printer setup, persisted in SharedPreferences.
///
/// Defaults are the safe ones: printing off, print-after-sale off. A shop that
/// has not paired a printer yet must not get a failure message on every sale,
/// and the only way to guarantee that is for the default to be *inert* rather
/// than to swallow failures at the call site.
class PrinterConfig {
  const PrinterConfig({
    this.enabled = false,
    this.macAddress = '',
    this.paperWidth = PrinterPaperWidth.mm58,
    this.printAfterSale = false,
  });

  /// Whether this till prints at all. Independent of [printAfterSale] so a
  /// shop can keep the pairing and use reprint without every sale producing
  /// paper.
  final bool enabled;

  final String macAddress;
  final PrinterPaperWidth paperWidth;

  /// Whether a completed sale prints automatically. Off by default: a shop that
  /// wants to hand the customer the change first should choose to print.
  final bool printAfterSale;

  bool get isConfigured => enabled && macAddress.trim().isNotEmpty;

  static const _enabledKey = 'printer_enabled';
  static const _addressKey = 'printer_mac_address';
  static const _paperKey = 'printer_paper_width';
  static const _printAfterSaleKey = 'printer_print_after_sale';

  static Future<PrinterConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PrinterConfig(
      enabled: prefs.getBool(_enabledKey) ?? false,
      macAddress: prefs.getString(_addressKey) ?? '',
      paperWidth: PrinterPaperWidth.fromName(prefs.getString(_paperKey)),
      printAfterSale: prefs.getBool(_printAfterSaleKey) ?? false,
    );
  }

  /// Persists each field that changed.
  ///
  /// Field-by-field rather than a single blob so adding a setting later cannot
  /// clobber an unrelated one written by a newer version of the app, and so a
  /// partial write still leaves the pairing intact.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setString(_addressKey, macAddress);
    await prefs.setString(_paperKey, paperWidth.name);
    await prefs.setBool(_printAfterSaleKey, printAfterSale);
  }

  PrinterConfig copyWith({
    bool? enabled,
    String? macAddress,
    PrinterPaperWidth? paperWidth,
    bool? printAfterSale,
  }) =>
      PrinterConfig(
        enabled: enabled ?? this.enabled,
        macAddress: macAddress ?? this.macAddress,
        paperWidth: paperWidth ?? this.paperWidth,
        printAfterSale: printAfterSale ?? this.printAfterSale,
      );
}