import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => activeCurrency = Currency.byCode('DZD'));
  tearDown(() => activeCurrency = Currency.byCode('MAD'));

  // Amounts use non-breaking spaces; compare with plain ones.
  String clean(String s) => s.replaceAll(RegExp('[  ]'), ' ');

  final paysera = Wallet(
    id: 'w2',
    name: 'Paysera',
    type: WalletType.mobile,
    createdAt: DateTime(2026),
    currencyCode: 'EUR',
    rate: 250,
  );

  test('a wallet in another currency with a rate is foreign', () {
    expect(paysera.isForeign('DZD'), isTrue);
    expect(paysera.currencyOr(activeCurrency).code, 'EUR');
    // Same currency as the account, or no rate: no conversion.
    expect(paysera.isForeign('EUR'), isFalse);
    expect(paysera.copyWith(mainCurrency: true).isForeign('DZD'), isFalse);
  });

  test('an expense keeps what was paid and the converted value', () {
    final e = Expense(
      amount: 5000,
      categoryId: 'food',
      date: DateTime(2026, 11, 15),
      walletId: 'w2',
      originalAmount: 20,
      originalCurrency: 'EUR',
    );
    expect(e.isConverted, isTrue);
    expect(e.rate, 250);
    final back = Expense.fromMap(e.toMap());
    expect(back.originalAmount, 20);
    expect(back.originalCurrency, 'EUR');
    expect(back.amount, 5000);
    // Moving or recategorising keeps the original amount.
    expect(e.copyWith(categoryId: 'leisure').originalAmount, 20);
  });

  test('formatting in the wallet currency and the rate label', () {
    expect(clean(moneyIn(20, Currency.byCode('EUR'))), '20 €');
    expect(clean(rateLabel(Currency.byCode('EUR'), 250)), '1 € = 250 DA');
  });

  test('wallet currency settings survive storage', () {
    final back = Wallet.fromMap(paysera.toMap());
    expect(back.currencyCode, 'EUR');
    expect(back.rate, 250);
  });

  test('only Premium allows wallets in another currency', () {
    expect(Plan.starter.foreignCurrencyWallets, isFalse);
    expect(Plan.pro.foreignCurrencyWallets, isFalse);
    expect(Plan.premium.foreignCurrencyWallets, isTrue);
  });
}
