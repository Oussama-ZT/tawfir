import 'dart:convert';

/// What could be read from a scanned QR code: any field may be missing.
class ScannedReceipt {
  const ScannedReceipt({this.amount, this.currency, this.merchant, this.date});

  /// Total paid, always positive.
  final double? amount;

  /// ISO 4217 alphabetic code ("DZD", "EUR"), when the code states it.
  final String? currency;
  final String? merchant;
  final DateTime? date;

  bool get isEmpty => amount == null && merchant == null && date == null;
}

/// Reads the receipt and payment QR codes people actually meet:
///
/// - EMVCo merchant QR codes (bank and wallet payments, "000201…"),
/// - Saudi ZATCA e-invoices (Base64 TLV: seller, date, total),
/// - payment links and receipt query strings (`upi://pay?am=…`,
///   `t=20240115T1530&s=1250.00&fn=…`, `?amount=…`),
/// - JSON (`{"total": 1250, "store": "…"}`),
/// - plain text ("TOTAL TTC 1 250,00 DA", or just "1250").
///
/// Nothing is guessed: a field is filled only when the code states it.
class QrReceipt {
  static ScannedReceipt parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const ScannedReceipt();
    return _emv(text) ?? _zatca(text) ?? _json(text) ?? _query(text) ?? _plain(text);
  }

  // ---------------------------------------------------------------- EMVCo

  /// Two-digit tag, two-digit length, value; tag 54 is the amount, 53 the
  /// numeric currency, 59 the merchant name.
  static ScannedReceipt? _emv(String s) {
    if (!s.startsWith('000201')) return null;
    final tags = <String, String>{};
    var i = 0;
    while (i + 4 <= s.length) {
      final tag = s.substring(i, i + 2);
      final len = int.tryParse(s.substring(i + 2, i + 4));
      if (len == null || i + 4 + len > s.length) return null;
      tags[tag] = s.substring(i + 4, i + 4 + len);
      i += 4 + len;
    }
    return ScannedReceipt(
      amount: _positive(double.tryParse(tags['54'] ?? '')),
      currency: _numericCurrencies[tags['53']],
      merchant: _clean(tags['59']),
    );
  }

  // ---------------------------------------------------------------- ZATCA

  /// Base64 of one-byte tag, one-byte length, UTF-8 value: 1 seller,
  /// 3 timestamp, 4 total with VAT. Always in riyals.
  static ScannedReceipt? _zatca(String s) {
    if (!RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s) || s.length < 16) return null;
    List<int> bytes;
    try {
      bytes = base64.decode(s.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      return null;
    }
    if (bytes.isEmpty || bytes[0] != 1) return null;
    final tags = <int, String>{};
    var i = 0;
    while (i + 2 <= bytes.length) {
      final tag = bytes[i], len = bytes[i + 1];
      if (i + 2 + len > bytes.length) return null;
      try {
        tags[tag] = utf8.decode(bytes.sublist(i + 2, i + 2 + len));
      } on FormatException {
        return null;
      }
      i += 2 + len;
    }
    if (!tags.containsKey(4)) return null;
    return ScannedReceipt(
      amount: _positive(double.tryParse(tags[4]!.trim())),
      currency: 'SAR',
      merchant: _clean(tags[1]),
      date: _date(tags[3]),
    );
  }

  // ----------------------------------------------------------------- JSON

  static ScannedReceipt? _json(String s) {
    if (!s.startsWith('{')) return null;
    Object? data;
    try {
      data = jsonDecode(s);
    } on FormatException {
      return null;
    }
    if (data is! Map) return null;
    final map = {for (final e in data.entries) e.key.toString().toLowerCase(): e.value};
    Object? pick(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null && v.toString().trim().isNotEmpty) return v;
      }
      return null;
    }

    final amount = pick(_amountKeys);
    final currency = pick(_currencyKeys)?.toString();
    return ScannedReceipt(
      amount: _positive(amount is num
          ? amount.toDouble()
          : double.tryParse(amount?.toString().trim() ?? '') ?? _number(amount?.toString() ?? '')),
      currency: _currencyCode(currency),
      merchant: _clean(pick(_merchantKeys)?.toString()),
      date: _date(pick(_dateKeys)?.toString()),
    );
  }

  // ------------------------------------------------- Links, query strings

  static ScannedReceipt? _query(String s) {
    Map<String, String> params;
    if (s.contains('://')) {
      final uri = Uri.tryParse(s);
      if (uri == null || uri.queryParameters.isEmpty) return null;
      params = uri.queryParameters;
    } else if (RegExp(r'^[\w.-]+=[^&]*(&[\w.-]+=[^&]*)+$').hasMatch(s)) {
      try {
        params = Uri.splitQueryString(s);
      } on FormatException {
        return null;
      }
    } else {
      return null;
    }
    final p = {for (final e in params.entries) e.key.toLowerCase(): e.value};
    String? first(List<String> keys) {
      for (final k in keys) {
        final v = p[k];
        if (v != null && v.trim().isNotEmpty) return v;
      }
      return null;
    }

    // "s" is the sum only on fiscal receipts, which also carry "t" (time).
    final amount = first([..._amountKeys, 'am']) ?? (p.containsKey('t') ? first(['s']) : null);
    final result = ScannedReceipt(
      // Links use a decimal point ("12.500" is twelve and a half).
      amount: _positive(double.tryParse(amount?.trim() ?? '') ?? _number(amount ?? '')),
      currency: _currencyCode(first([..._currencyKeys, 'cu'])),
      merchant: _clean(first([..._merchantKeys, 'pn'])),
      date: _date(first([..._dateKeys, 't'])),
    );
    // A link with nothing useful (a website, a menu) is not a receipt.
    return result.isEmpty ? const ScannedReceipt() : result;
  }

  // ----------------------------------------------------------- Plain text

  static ScannedReceipt _plain(String s) {
    final bare = RegExp(r'^([\d\s.,]+)\s*([^\d\s.,]{1,4})?$').firstMatch(s);
    if (bare != null) {
      final unit = _currencyCode(bare.group(2));
      if (bare.group(2) == null || unit != null) {
        return ScannedReceipt(amount: _positive(_number(bare.group(1)!)), currency: unit);
      }
    }
    // The last total on a ticket comes after the subtotals.
    final total = RegExp(
      r'(net\s*à\s*payer|à\s*payer|total(?:\s*ttc)?|ttc|montant|somme|amount|sum|المبلغ|المجموع|الإجمالي|إجمالي)'
      // The number stays on its line: spaces, not line breaks, group digits.
      r'[^\d\n]{0,20}?(\d[\d   .,]*\d|\d)[  ]*([^\d\s.,]{1,4})?',
      caseSensitive: false,
    ).allMatches(s).lastOrNull;
    return ScannedReceipt(
      amount: total == null ? null : _positive(_number(total.group(2)!)),
      currency: total == null ? null : _currencyCode(total.group(3)),
      date: _date(RegExp(r'\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?|\b\d{1,2}[/.-]\d{1,2}[/.-]\d{4}\b').firstMatch(s)?.group(0)),
    );
  }

  // -------------------------------------------------------------- Helpers

  static const _amountKeys = ['amount', 'total', 'montant', 'sum', 'somme', 'ttc', 'total_amount', 'totalamount', 'amt', 'price', 'prix'];
  static const _currencyKeys = ['currency', 'devise', 'cur'];
  static const _merchantKeys = ['merchant', 'store', 'shop', 'seller', 'vendor', 'magasin', 'commerce', 'company'];
  static const _dateKeys = ['date', 'datetime', 'timestamp', 'time'];

  /// ISO 4217 numeric codes used by EMV QR codes.
  static const _numericCurrencies = {
    '012': 'DZD', '978': 'EUR', '840': 'USD', '826': 'GBP', '756': 'CHF', '124': 'CAD',
    '504': 'MAD', '788': 'TND', '818': 'EGP', '682': 'SAR', '784': 'AED', '634': 'QAR',
    '414': 'KWD', '048': 'BHD', '512': 'OMR', '400': 'JOD', '949': 'TRY', '156': 'CNY',
    '392': 'JPY', '356': 'INR', '643': 'RUB', '986': 'BRL', '484': 'MXN', '036': 'AUD',
  };

  static const _symbols = {'da': 'DZD', 'دج': 'DZD', 'د.ج': 'DZD', '€': 'EUR', r'$': 'USD', '£': 'GBP', 'ر.س': 'SAR', 'dh': 'MAD', 'dt': 'TND'};

  static String? _currencyCode(String? s) {
    if (s == null) return null;
    final t = s.trim();
    final symbol = _symbols[t.toLowerCase()];
    if (symbol != null) return symbol;
    if (RegExp(r'^[A-Za-z]{3}$').hasMatch(t)) return t.toUpperCase();
    return _numericCurrencies[t];
  }

  /// "1 250,50", "1,250.50", "1250.5" → 1250.5. A lone separator followed
  /// by exactly three digits ("1.250") is a thousands separator.
  static double? _number(String s) {
    var c = s.replaceAll(RegExp(r'[\s  ]'), '');
    if (c.isEmpty) return null;
    final hasComma = c.contains(','), hasDot = c.contains('.');
    if (hasComma && hasDot) {
      final decimalComma = c.lastIndexOf(',') > c.lastIndexOf('.');
      c = decimalComma ? c.replaceAll('.', '').replaceAll(',', '.') : c.replaceAll(',', '');
    } else if (hasComma || hasDot) {
      final sep = hasComma ? ',' : '.';
      final parts = c.split(sep);
      final thousands = parts.length > 2 || (parts.last.length == 3 && parts.first != '0');
      c = thousands ? parts.join() : parts.join('.');
    }
    return double.tryParse(c);
  }

  static double? _positive(double? v) => v == null || v.isNaN || v <= 0 || v >= 100000000 ? null : v;

  static String? _clean(String? s) {
    final t = s?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t == null || t.isEmpty ? null : t;
  }

  /// ISO 8601, fiscal "20240115T1530", or "15/01/2024". Never in the future.
  static DateTime? _date(String? s) {
    if (s == null) return null;
    final t = s.trim();
    DateTime? d = DateTime.tryParse(t);
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?$').firstMatch(t);
    if (compact != null) {
      final g = [for (var i = 1; i <= 6; i++) int.tryParse(compact.group(i) ?? '0') ?? 0];
      d = DateTime(g[0], g[1], g[2], g[3], g[4], g[5]);
    }
    final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!), month = int.parse(dmy.group(2)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      d = DateTime(int.parse(dmy.group(3)!), month, day);
    }
    if (d == null) return null;
    d = d.toLocal();
    final now = DateTime.now();
    if (d.isAfter(now.add(const Duration(minutes: 5))) || d.isBefore(DateTime(now.year - 5))) return null;
    return d;
  }
}
