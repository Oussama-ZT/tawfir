import 'package:eco_budget/data/repository.dart';
import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/models/deposit.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/savings_goal.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/envelope_math.dart';
import 'package:eco_budget/state/app_state.dart';
import 'package:eco_budget/utils/dates.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _spend(String id, double amount, String wallet, DateTime date) =>
    Expense(id: id, amount: amount, categoryId: 'food', date: date, walletId: wallet);

/// In-memory storage, so AppState can be tested without a database.
class _MemoryRepo implements BudgetRepository {
  _MemoryRepo({required this.wallets_, this.expenses_ = const [], this.deposits_ = const [], this.goals_ = const []});

  final List<Wallet> wallets_;
  final List<Expense> expenses_;
  final List<Deposit> deposits_;
  final List<SavingsGoal> goals_;
  final Map<String, double> stored = {};

  @override
  Future<List<Expense>> expenses() async => [...expenses_];
  @override
  Future<String> insertExpense(Expense e) async => 'x${stored.length}';
  @override
  Future<void> updateExpense(Expense e) async {}
  @override
  Future<void> deleteExpense(String id) async {}
  @override
  Future<Map<String, double>> budgets() async => Map.of(stored);
  @override
  Future<void> setBudget(String key, double amount) async =>
      amount <= 0 ? stored.remove(key) : stored[key] = amount;
  @override
  Future<List<SavingsGoal>> goals() async => [...goals_];
  @override
  Future<String> insertGoal(SavingsGoal g) async => 'g';
  @override
  Future<void> updateGoal(SavingsGoal g) async {}
  @override
  Future<void> deleteGoal(String id) async {}
  @override
  Future<List<Wallet>> wallets() async => [...wallets_];
  @override
  Future<void> saveWallet(Wallet w) async {}
  @override
  Future<void> deleteWallet(String id, {required String moveTo}) async {}
  @override
  Future<List<ExpenseCategory>> categories() async => [];
  @override
  Future<void> saveCategory(ExpenseCategory c) async {}
  @override
  Future<void> deleteCategory(String id) async {}
  @override
  Future<List<Deposit>> deposits() async => [...deposits_];
  @override
  Future<void> saveDeposit(Deposit d) async {}
  @override
  Future<void> deleteDeposit(String id) async {}
  @override
  Future<void> replaceAll({
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required List<Wallet> wallets,
    required List<ExpenseCategory> categories,
    required List<Deposit> deposits,
  }) async {}
}

void main() {
  setUp(() => activeCurrency = Currency.byCode('DZD'));
  tearDown(() => activeCurrency = Currency.byCode('MAD'));

  final now = DateTime.now();
  final cash = Wallet(id: 'cash', name: 'Espèces', type: WalletType.cash, createdAt: DateTime(2026));
  final bank = Wallet(id: 'bank', name: 'Banque', type: WalletType.bank, createdAt: DateTime(2026, 2));
  Deposit income(String wallet, double amount) => Deposit(
      id: 'in-$wallet', walletId: wallet, amount: amount, date: monthStart(now), kind: DepositKind.income);

  group('EnvelopeMath', () {
    test('each wallet pays from its own share, then outside the budget', () {
      const env = Envelope(total: 30000, funds: {'cash': 20000, 'bank': 10000});
      final m = EnvelopeMath.compute(env, [
        _spend('1', 15000, 'cash', DateTime(2026, 11, 2)),
        _spend('2', 8000, 'cash', DateTime(2026, 11, 5)), // 5 000 inside, 3 000 outside
        _spend('3', 4000, 'bank', DateTime(2026, 11, 6)),
      ]);
      expect(m.used, 24000);
      expect(m.outside, 3000);
      expect(m.left, 6000);
      expect(m.leftByWallet, {'cash': 0, 'bank': 6000});
      expect(m.outsideExpenseIds, {'2'});
      expect(m.exceeded, isFalse, reason: 'the bank share is not used up');
    });

    test('a wallet that does not fund the envelope spends outside the budget', () {
      const env = Envelope(total: 10000, funds: {'cash': 10000});
      final m = EnvelopeMath.compute(env, [_spend('1', 500, 'paysera', DateTime(2026, 11, 2))]);
      expect(m.used, 0);
      expect(m.outside, 500);
    });

    test('a shared envelope counts every wallet, like the old budget', () {
      const env = Envelope(total: 1000);
      final m = EnvelopeMath.compute(env, [
        _spend('1', 700, 'cash', DateTime(2026, 11, 2)),
        _spend('2', 500, 'bank', DateTime(2026, 11, 3)),
      ]);
      expect(m.used, 1000);
      expect(m.outside, 200);
      expect(m.exceeded, isTrue);
      expect(m.leftByWallet, isEmpty);
    });
  });

  group('AppState envelope', () {
    test('75 000 DA in cash, 35 000 reserved, a 2 000 DA purchase', () async {
      final repo = _MemoryRepo(
        wallets_: [cash],
        deposits_: [income('cash', 75000)],
        expenses_: [_spend('1', 2000, 'cash', now)],
      );
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.starter);
      await app.setEnvelope({'cash': 35000});

      expect(app.totalBudget, 35000);
      expect(app.balanceOf(cash), 73000, reason: 'what is really in the wallet');
      expect(app.reservedIn(cash), 33000);
      expect(app.freeIn(cash), 40000);
      expect(app.envelopeIn(now).left, 33000);
    });

    test('a month ends: what is left can go into a savings goal', () async {
      final last = addMonths(monthStart(now), -1);
      final goal = SavingsGoal(id: 'trip', name: 'Voyage', target: 100000, saved: 10000, createdAt: DateTime(2026));
      final repo = _MemoryRepo(
        wallets_: [cash],
        deposits_: [
          Deposit(id: 'in', walletId: 'cash', amount: 75000, date: last, kind: DepositKind.income),
        ],
        expenses_: [_spend('1', 30000, 'cash', last.add(const Duration(days: 3)))],
        goals_: [goal],
      )..stored.addAll({
          'total': 35000,
          '${AppState.fundPrefix}cash': 35000,
          AppState.sinceKey: (last.year * 100 + last.month).toDouble(),
        });
      final app = AppState(repo);
      await app.load();

      final pending = app.monthToClose!;
      expect(pending.left, 5000);
      await app.closeMonth(pending.month, goal: goal);

      expect(app.goals.single.saved, 15000);
      expect(app.balanceOf(cash), 75000 - 30000 - 5000);
      expect(app.monthToClose, isNull, reason: 'asked only once');
    });

    test('months before the envelope existed are never asked about', () async {
      final repo = _MemoryRepo(wallets_: [cash], deposits_: [income('cash', 75000)]);
      final app = AppState(repo);
      await app.load();
      await app.setEnvelope({'cash': 35000});
      expect(app.monthToClose, isNull);
    });

    test('deleting a wallet: what was left arrives in the chosen wallet', () async {
      final repo = _MemoryRepo(
        wallets_: [cash, bank],
        deposits_: [income('cash', 5000), income('bank', 2000)],
        expenses_: [_spend('1', 500, 'bank', now)],
      );
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      expect(app.balanceOf(bank), 1500);
      await app.deleteWallet(bank, moveTo: cash);
      expect(app.balanceOf(cash), 6500);
      expect(app.expenses.single.walletId, 'cash', reason: 'its expenses are kept');
    });

    test('deleting a wallet in euros converts its money at its rate', () async {
      final paysera = Wallet(
        id: 'paysera', name: 'Paysera', type: WalletType.mobile, createdAt: DateTime(2026, 3),
        currencyCode: 'EUR', rate: 250);
      final repo = _MemoryRepo(wallets_: [cash, paysera], deposits_: [income('cash', 1000), income('paysera', 10)]);
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      await app.deleteWallet(paysera, moveTo: cash);
      expect(app.balanceOf(cash), 1000 + 10 * 250);
    });

    test('deleting a wallet leaves the other wallets as they were', () async {
      final other = Wallet(id: 'other', name: 'Carte', type: WalletType.card, createdAt: DateTime(2026, 4));
      final repo = _MemoryRepo(
        wallets_: [cash, bank, other],
        deposits_: [
          income('cash', 5000),
          income('other', 3000),
          Deposit(
            id: 't', walletId: 'bank', amount: 1000, date: monthStart(now).add(const Duration(hours: 1)),
            kind: DepositKind.transfer, sourceWalletId: 'other'),
        ],
      );
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      expect(app.balanceOf(other), 2000);
      await app.deleteWallet(bank, moveTo: cash);
      expect(app.balanceOf(other), 2000, reason: 'what it sent stays sent');
      expect(app.balanceOf(cash), 6000);
    });

    test('a wallet whose balance is not tracked receives the money without other changes', () async {
      final repo = _MemoryRepo(
        wallets_: [cash, bank],
        deposits_: [income('bank', 2000)],
        expenses_: [_spend('1', 300, 'cash', now.subtract(const Duration(minutes: 5)))],
      );
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      expect(app.balanceOf(cash), isNull);
      await app.deleteWallet(bank, moveTo: cash);
      expect(app.balanceOf(cash), 2000);
    });

    test('deleting a wallet moves its share to the wallet that gets its expenses', () async {
      final repo = _MemoryRepo(wallets_: [cash, bank]);
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      await app.setEnvelope({'cash': 20000, 'bank': 10000});
      await app.deleteWallet(bank, moveTo: cash);
      expect(app.envelope.funds, {'cash': 30000});
      expect(app.totalBudget, 30000);
    });
  });
}
