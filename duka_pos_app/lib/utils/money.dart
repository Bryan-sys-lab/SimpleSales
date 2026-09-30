import 'package:intl/intl.dart';

final _kenyaMoney =
    NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0);

String formatMoney(num amount) => _kenyaMoney.format(amount);
