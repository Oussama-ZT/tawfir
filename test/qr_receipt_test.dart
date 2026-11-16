import 'dart:convert';

import 'package:eco_budget/services/qr_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an EMV tag: two-digit id, two-digit length, value.
String _tlv(String id, String value) => '$id${value.length.toString().padLeft(2, '0')}$value';

/// Builds a ZATCA e-invoice code: Base64 of one-byte tag, one-byte length.
String _zatca(Map<int, String> tags) => base64.encode([
      for (final e in tags.entries) ...[e.key, utf8.encode(e.value).length, ...utf8.encode(e.value)],
    ]);

void main() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  final ymd = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

  test('EMV merchant QR: amount, currency and merchant', () {
    final code = '000201010212${_tlv('53', '012')}${_tlv('54', '1250.50')}${_tlv('58', 'DZ')}${_tlv('59', 'Superette El Amel')}${_tlv('60', 'Alger')}6304ABCD';
    final r = QrReceipt.parse(code);
    expect(r.amount, 1250.50);
    expect(r.currency, 'DZD');
    expect(r.merchant, 'Superette El Amel');
  });

  test('a static EMV QR has the merchant but no amount', () {
    final r = QrReceipt.parse('000201010211${_tlv('53', '978')}${_tlv('59', 'Café Paris')}6304ABCD');
    expect(r.amount, isNull);
    expect(r.currency, 'EUR');
    expect(r.merchant, 'Café Paris');
  });

  test('ZATCA e-invoice: seller, date and total in riyals', () {
    final r = QrReceipt.parse(_zatca({1: 'متجر النور', 2: '310122393500003', 3: '${ymd}T10:30:00', 4: '115.00', 5: '15.00'}));
    expect(r.amount, 115);
    expect(r.currency, 'SAR');
    expect(r.merchant, 'متجر النور');
    expect(r.date?.day, yesterday.day);
  });

  test('payment links and fiscal receipt query strings', () {
    final upi = QrReceipt.parse('upi://pay?pa=shop@bank&pn=Fresh%20Mart&am=349.00&cu=INR');
    expect(upi.amount, 349);
    expect(upi.currency, 'INR');
    expect(upi.merchant, 'Fresh Mart');

    final y = yesterday;
    final t = '${y.year}${y.month.toString().padLeft(2, '0')}${y.day.toString().padLeft(2, '0')}T1530';
    final fiscal = QrReceipt.parse('t=$t&s=1234.50&fn=9289000100&i=12&fp=345&n=1');
    expect(fiscal.amount, 1234.50);
    expect(fiscal.date, DateTime(y.year, y.month, y.day, 15, 30));

    expect(QrReceipt.parse('https://shop.example/pay?amount=12.500').amount, 12.5);
  });

  test('a website link is not a receipt', () {
    expect(QrReceipt.parse('https://example.com/menu').isEmpty, isTrue);
    expect(QrReceipt.parse('https://example.com/?lang=fr&ref=table4').isEmpty, isTrue);
  });

  test('JSON receipts', () {
    final r = QrReceipt.parse('{"store": "Ardis", "Total": "2 450,00", "currency": "DZD", "date": "$ymd"}');
    expect(r.amount, 2450);
    expect(r.currency, 'DZD');
    expect(r.merchant, 'Ardis');
    expect(r.date, DateTime(yesterday.year, yesterday.month, yesterday.day));
    expect(QrReceipt.parse('{"amount": 99.9}').amount, 99.9);
  });

  test('plain text: the last total wins, with its currency', () {
    final r = QrReceipt.parse('Sous-total 1 000,00\nRemise 50\nTOTAL TTC 1 250,00 DA\nMerci');
    expect(r.amount, 1250);
    expect(r.currency, 'DZD');
    expect(QrReceipt.parse('المبلغ: 3500 دج').amount, 3500);
    expect(QrReceipt.parse('Amount: 1,250.75').amount, 1250.75);
  });

  test('a bare amount, with or without a currency', () {
    expect(QrReceipt.parse('1250').amount, 1250);
    expect(QrReceipt.parse('1 250,50 €').amount, 1250.5);
    expect(QrReceipt.parse('1 250,50 €').currency, 'EUR');
    expect(QrReceipt.parse('1.250').amount, 1250, reason: 'three digits after a lone separator are thousands');
  });

  test('nothing is guessed', () {
    expect(QrReceipt.parse('').isEmpty, isTrue);
    expect(QrReceipt.parse('WIFI:S:Maison;T:WPA;P:secret;;').isEmpty, isTrue);
    expect(QrReceipt.parse('0661234567').amount, isNull, reason: 'a phone number is not an amount');
    expect(QrReceipt.parse('{"total": -20}').amount, isNull);
    final future = DateTime.now().add(const Duration(days: 3));
    expect(QrReceipt.parse('{"total": 10, "date": "${future.toIso8601String()}"}').date, isNull);
  });
}
