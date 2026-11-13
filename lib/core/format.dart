import 'package:intl/intl.dart';

/// An exact decimal amount with its ISO 4217 currency. The amount stays a
/// string end to end; it is parsed for display only.
class Money {
  const Money(this.amount, this.currency);
  final String amount;
  final String currency;
}

final _whole = NumberFormat.decimalPattern('en');

/// "USD 385,000". The currency code is always shown because markets and
/// currencies are mixed across the platform.
String formatMoney(Money money) =>
    '${money.currency} ${_whole.format(double.parse(money.amount).round())}';

String formatArea(int squareMetres) => '${_whole.format(squareMetres)} m²';
