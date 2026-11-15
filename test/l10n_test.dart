import 'dart:io';

import 'package:eco_budget/l10n/ar.dart';
import 'package:eco_budget/l10n/en.dart';
import 'package:eco_budget/l10n/l10n.dart';
import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _placeholder = RegExp(r'\{\d\}');

void main() {
  setUpAll(() => initializeDateFormatting());
  tearDown(() {
    setAppLanguage(AppLanguage.fr);
    activeCurrency = Currency.byCode('MAD');
  });

  test('English and Arabic translate the same texts', () {
    expect(ar.keys.toSet(), en.keys.toSet());
  });

  test('every text shown with tr() has an English and an Arabic version', () {
    final call = RegExp(r"tr\('((?:[^'\\]|\\.)*)'");
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('l10n')) continue;
      for (final m in call.allMatches(file.readAsStringSync())) {
        final key = m[1]!.replaceAll(r"\'", "'").replaceAll(r'\$', r'$').replaceAll(r'\\', r'\');
        // Keys built at runtime ('{0} $noun') are checked through their parts.
        if (key.contains(r'$')) continue;
        if (!en.containsKey(key) || !ar.containsKey(key)) missing.add(key);
      }
    }
    expect(missing, isEmpty);
  });

  test('every translation keeps the values of its French text', () {
    for (final entry in en.entries) {
      final wanted = _placeholder.allMatches(entry.key).map((m) => m[0]).toSet();
      expect(_placeholder.allMatches(entry.value).map((m) => m[0]).toSet(), wanted, reason: entry.key);
      // Arabic singulars ("تنبيه واحد") write the number as a word.
      final arabic = _placeholder.allMatches(ar[entry.key]!).map((m) => m[0]).toSet();
      expect(arabic.difference(wanted), isEmpty, reason: entry.key);
    }
  });

  test('tr places values and falls back to French', () {
    setAppLanguage(AppLanguage.en);
    expect(tr('Il ne reste que {0} dans « {1} ». Le solde deviendra négatif. Continuer ?', ['5 DA', 'Cash'])
        .startsWith('Only 5 DA left in “Cash”'), isTrue);
    expect(tr('Texte sans traduction'), 'Texte sans traduction');
    setAppLanguage(AppLanguage.ar);
    expect(tr('Budget du mois'), 'ميزانية الشهر');
    expect(AppLanguage.ar.isRtl, isTrue);
  });

  test('each language has its own singular rule', () {
    expect(isSingular(0), isTrue, reason: 'French: 0 dépense');
    setAppLanguage(AppLanguage.en);
    expect(isSingular(0), isFalse, reason: 'English: 0 expenses');
    expect(isSingular(1), isTrue);
  });

  test('built-in labels follow the language, custom names stay as typed', () {
    final pets = ExpenseCategory.custom(id: 'c', label: 'Animaux', iconKey: 'pets', color: const Color(0xFF000000));
    setAppLanguage(AppLanguage.en);
    expect(ExpenseCategory.byId('food').label, 'Food');
    expect(pets.label, 'Animaux');
    expect(Currency.byCode('DZD').name, 'Algerian dinar');
  });

  test('numbers and dates follow the language', () {
    activeCurrency = Currency.byCode('DZD');
    setAppLanguage(AppLanguage.en);
    expect(money(35000), '35,000 DA');
    expect(percent(0.4), '40%');
    expect(parseAmount('1,200.50'), 1200.5);
    expect(monthName(DateTime(2026, 11)), 'November');
    setAppLanguage(AppLanguage.fr);
    expect(money(35000).replaceAll(RegExp('[  ]'), ' '), '35 000 DA');
    expect(parseAmount('1 200,50'), 1200.5);
    setAppLanguage(AppLanguage.ar);
    expect(monthName(DateTime(2026, 1)), 'جانفي', reason: 'Algerian month names');
    expect(fullDate(DateTime(2026, 11, 15)), '15/11/2026', reason: 'Latin digits');
  });
}
