import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/currency.dart';

Currency _currency = Currency.byCode('MAD');

/// Number style per language. Arabic keeps Latin digits with the French
/// grouping, as is usual in the Maghreb.
String get _numberLocale => appLanguage == AppLanguage.en ? 'en' : 'fr';

final _formats = <String, NumberFormat>{};

NumberFormat _formatFor(Currency c) {
  final pattern = c.decimals == 0 ? '#,##0' : '#,##0.${'#' * c.decimals}';
  return _formats.putIfAbsent('$pattern|$_numberLocale', () => NumberFormat(pattern, _numberLocale));
}

/// The currency of the signed-in user. Amounts are stored as plain numbers;
/// changing the currency relabels them, it does not convert them.
Currency get activeCurrency => _currency;

set activeCurrency(Currency c) => _currency = c;

String get currencySymbol => _currency.symbol;

/// Keeps "35 000 DA" in that order inside right-to-left text, where the
/// number and the symbol would otherwise swap places.
String _ltr(String s) => appLanguage.isRtl ? '\u2066$s\u2069' : s;

/// Non-breaking space so an amount never wraps away from its symbol.
String money(double value) => _ltr('${_formatFor(_currency).format(value)} ${_currency.symbol}');

/// Amount in a given currency (a wallet in euros while the account is in dinars).
String moneyIn(double value, Currency c) => _ltr('${_formatFor(c).format(value)} ${c.symbol}');

/// Exchange rate, e.g. "1 € = 250 DA".
String rateLabel(Currency from, double rate) =>
    _ltr('1 ${from.symbol} = ${NumberFormat('#,##0.####', _numberLocale).format(rate)} ${_currency.symbol}');

/// For estimates (averages, projections): rounded to the whole unit.
String moneyApprox(double value) => money(value.roundToDouble());

/// Amount without the symbol, for large display where the symbol is styled apart.
String amountOnly(double value, [Currency? currency]) => _formatFor(currency ?? _currency).format(value);

String percent(double ratio) =>
    appLanguage == AppLanguage.fr ? '${(ratio * 100).round()} %' : '${(ratio * 100).round()}%';

/// One decimal, with the language's separator: "2,5" or "2.5".
String decimal1(double v) {
  final s = v.toStringAsFixed(1);
  return appLanguage == AppLanguage.en ? s : s.replaceAll('.', ',');
}

DateFormat _date(String pattern) => DateFormat(pattern, appLanguage.dateLocale);

/// "15/11/2026".
String fullDate(DateTime d) => _date('dd/MM/yyyy').format(d);

String shortDate(DateTime d) => _date('d MMM').format(d);

String longDate(DateTime d) => _date('EEEE d MMMM').format(d);

String monthName(DateTime d) => _date('MMMM').format(d);

String monthYear(DateTime d) {
  final s = _date('MMMM yyyy').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String shortMonth(DateTime d) => _date('MMM').format(d);

/// Parses user input such as "1 200,50", "1200.5" or "1,200.50".
double? parseAmount(String input) {
  var cleaned = input.replaceAll(RegExp(r'[\s  ]'), '');
  if (cleaned.contains(',') && cleaned.contains('.')) {
    // Both: the last one is the decimal separator.
    final decimalComma = cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.');
    cleaned = decimalComma ? cleaned.replaceAll('.', '').replaceAll(',', '.') : cleaned.replaceAll(',', '');
  } else if (appLanguage == AppLanguage.en && RegExp(r',\d{3}$').hasMatch(cleaned)) {
    cleaned = cleaned.replaceAll(',', '');
  } else {
    cleaned = cleaned.replaceAll(',', '.');
  }
  final v = double.tryParse(cleaned);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}
