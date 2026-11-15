import 'package:eco_budget/models/deposit.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/wallet_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cash = Wallet(id: 'cash', name: 'Espèces', type: WalletType.cash, createdAt: DateTime(2026));
  final bank = Wallet(id: 'bank', name: 'Compte bancaire', type: WalletType.bank, createdAt: DateTime(2026));
  final paysera = Wallet(
      id: 'pay', name: 'Paysera', type: WalletType.mobile, createdAt: DateTime(2026), currencyCode: 'EUR', rate: 250);

  Expense spend(String wallet, double amount, DateTime date, {double? eur}) => Expense(
        amount: amount,
        categoryId: 'food',
        date: date,
        walletId: wallet,
        originalAmount: eur,
        originalCurrency: eur == null ? null : 'EUR',
      );

  Deposit add(String to, double amount, DateTime date, {DepositKind kind = DepositKind.income, String? from, double? sent}) =>
      Deposit(id: '$to$date$amount', walletId: to, amount: amount, date: date, kind: kind, sourceWalletId: from, sourceAmount: sent);

  test('no money added yet: the balance is unknown', () {
    expect(WalletMath.balance(cash, [spend('cash', 300, DateTime(2026, 11, 2))], const [], 'DZD'), isNull);
  });

  test('take 5 000 DA, spend it over 5 days, then take 7 000 DA', () {
    final deposits = [
      add('cash', 5000, DateTime(2026, 11, 1, 9)),
      add('cash', 7000, DateTime(2026, 11, 7, 9)),
    ];
    final expenses = [
      for (var d = 1; d <= 5; d++) spend('cash', 1000, DateTime(2026, 11, d, 12)),
      spend('cash', 800, DateTime(2026, 11, 7, 13)),
    ];
    expect(WalletMath.balance(cash, expenses, deposits.sublist(0, 1), 'DZD'), 5000 - 5000 + -800);
    expect(WalletMath.balance(cash, expenses, deposits, 'DZD'), 5000 + 7000 - 5800);
  });

  test('expenses before the first deposit do not count', () {
    final deposits = [add('cash', 2000, DateTime(2026, 11, 10))];
    final expenses = [spend('cash', 9999, DateTime(2026, 10, 1)), spend('cash', 500, DateTime(2026, 11, 11))];
    expect(WalletMath.balance(cash, expenses, deposits, 'DZD'), 1500);
  });

  test('a transfer moves money from the bank to cash', () {
    final deposits = [
      add('bank', 20000, DateTime(2026, 11, 1), kind: DepositKind.adjustment),
      add('cash', 5000, DateTime(2026, 11, 2), kind: DepositKind.transfer, from: 'bank'),
    ];
    expect(WalletMath.balance(bank, const [], deposits, 'DZD'), 15000);
    expect(WalletMath.balance(cash, const [], deposits, 'DZD'), 5000);
    // A transfer is not income.
    expect(WalletMath.incomeIn(cash, deposits, DateTime(2026, 11)), 0);
  });

  test('changing 100 € from Paysera gives 25 000 DA in cash', () {
    final deposits = [
      add('pay', 300, DateTime(2026, 11, 1)),
      add('cash', 25000, DateTime(2026, 11, 3), kind: DepositKind.transfer, from: 'pay', sent: 100),
    ];
    final expenses = [spend('pay', 5000, DateTime(2026, 11, 4), eur: 20)];
    expect(WalletMath.balance(paysera, expenses, deposits, 'DZD'), 300 - 100 - 20);
    expect(WalletMath.balance(cash, expenses, deposits, 'DZD'), 25000);
  });

  test('a correction can lower the balance', () {
    final deposits = [
      add('cash', 3000, DateTime(2026, 11, 1)),
      add('cash', -400, DateTime(2026, 11, 5), kind: DepositKind.adjustment),
    ];
    expect(WalletMath.balance(cash, const [], deposits, 'DZD'), 2600);
  });

  test('a withdrawal takes money out without being an expense', () {
    final deposits = [
      add('cash', 7000, DateTime(2026, 11, 1)),
      add('cash', 2000, DateTime(2026, 11, 3), kind: DepositKind.withdrawal),
    ];
    final expenses = [spend('cash', 500, DateTime(2026, 11, 4))];
    expect(WalletMath.balance(cash, expenses, deposits, 'DZD'), 4500);
    final flows = WalletMath.flowsSince(cash, expenses, deposits, DateTime(2026, 11), 'DZD');
    expect(flows.received, 7000);
    expect(flows.spent, 500);
    expect(flows.withdrawn, 2000);
  });
}
