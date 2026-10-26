import 'package:flutter/foundation.dart';

import '../../utils/money.dart';

/// The small amount of information needed to print one stock label.
@immutable
class BarcodeLabel {
  const BarcodeLabel({
    required this.name,
    required this.barcode,
    required this.price,
  });

  final String name;
  final String barcode;
  final Money price;
}
