import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/services/auth/auth_backend.dart';
import 'package:eco_budget/services/auth/local_auth_backend.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => activeCurrency = Currency.byCode('MAD'));

  group('currency formatting', () {
    String clean(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');

    test('uses the active currency symbol', () {
      activeCurrency = Currency.byCode('EUR');
      expect(clean(money(1200.5)), '1 200,5 €');
      activeCurrency = Currency.byCode('USD');
      expect(clean(money(30)), '30 \$');
    });

    test('respects currency decimals', () {
      activeCurrency = Currency.byCode('JPY');
      expect(clean(money(1234.56)), '1 235 ¥');
      activeCurrency = Currency.byCode('TND');
      expect(clean(money(10.125)), '10,125 DT');
    });

    test('unknown codes fall back, country guesses work', () {
      expect(Currency.byCode('???').code, 'USD');
      expect(Currency.forCountry('ma').code, 'MAD');
      expect(Currency.forCountry('FR').code, 'EUR');
      expect(Currency.forCountry(null).code, 'USD');
    });

    test('every currency code is unique', () {
      final codes = Currency.all.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
    });
  });

  group('auth helpers', () {
    test('hash is salted and deterministic', () {
      final salt = LocalAuthBackend.newSalt();
      expect(LocalAuthBackend.hashPassword('secret1', salt), LocalAuthBackend.hashPassword('secret1', salt));
      expect(LocalAuthBackend.hashPassword('secret1', salt), isNot(LocalAuthBackend.hashPassword('secret2', salt)));
      expect(LocalAuthBackend.hashPassword('secret1', salt),
          isNot(LocalAuthBackend.hashPassword('secret1', LocalAuthBackend.newSalt())));
      expect(LocalAuthBackend.hashPassword('secret1', salt), isNot(contains('secret1')));
    });

    test('validators', () {
      expect(AuthValidators.email('a@b.co'), isNull);
      expect(AuthValidators.email('not-an-email'), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.password('12345'), isNotNull);
      expect(AuthValidators.password('123456'), isNull);
      expect(AuthValidators.name('  '), isNotNull);
    });
  });
}
