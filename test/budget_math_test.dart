import 'package:eco_budget/data/repository.dart';
import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/debt.dart';
import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/models/deposit.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/savings_goal.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/budget_math.dart';
import 'package:eco_budget/state/app_state.dart';
import 'package:eco_budget/utils/dates.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _e(String id, double amount, DateTime date, {String category = 'food', String wallet = 'cash'}) =>
    Expense(id: id, amount: amount, categoryId: category, date: date, walletId: wallet);

/// In-memory storage, so AppState can be tested without a database.
class _Repo implements BudgetRepository {
  _Repo({this.wallets_ = const [], this.deposits_ = const [], this.expenses_ = const [], Map<String, double>? budgets})
    : stored = {...?budgets};

  final List<Wallet> wallets_;
  final List<Deposit> deposits_;
  final List<Expense> expenses_;
  final Map<String, double> stored;
  var _n = 100;

  @override
  Future<List<Expense>> expenses() async => [...expenses_];
  @override
  Future<String> insertExpense(Expense e) async => '${_n++}';
  @override
  Future<void> updateExpense(Expense e) async {}
  @override
  Future<void> deleteExpense(String id) async {}
  @override
  Future<Map<String, double>> budgets() async => Map.of(stored);
  @override
  Future<void> setBudget(String key, double amount) async => amount <= 0 ? stored.remove(key) : stored[key] = amount;
  @override
  Future<List<SavingsGoal>> goals() async => [];
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
    List<Debt> debts = const [],
  }) async {}
  @override
  Future<List<Debt>> debts() async => [];
  @override
  Future<void> saveDebt(Debt d) async {}
  @override
  Future<void> deleteDebt(String id) async {}
}

void main() {
  setUp(() => activeCurrency = Currency.byCode('DZD'));
  tearDown(() => activeCurrency = Currency.byCode('MAD'));

  final nov = DateTime(2026, 11);
  final cash = Wallet(id: 'cash', name: 'Espèces', type: WalletType.cash, createdAt: DateTime(2026));
  final bank = Wallet(id: 'bank', name: 'Banque', type: WalletType.bank, createdAt: DateTime(2026, 2));

  group('Daily allowance', () {
    test('60 000 budget, 4 000 spent, 27 days left: about 2 074 a day', () {
      final st = BudgetMath.status(
        budget: 60000,
        expenses: [_e('1', 2500, DateTime(2026, 11, 2)), _e('2', 1500, DateTime(2026, 11, 3))],
        month: nov,
        today: DateTime(2026, 11, 4), // November has 30 days: 27 left, today included.
      );
      expect(st.spent, 4000);
      expect(st.remaining, 56000);
      expect(st.daysLeft, 27);
      expect(st.dailyAllowance, closeTo(2074.07, 0.01));
      expect(st.level, BudgetLevel.within);
    });

    test('first day of the month: the whole budget over every day', () {
      final st = BudgetMath.status(budget: 31000, expenses: [], month: DateTime(2026, 12), today: DateTime(2026, 12, 1));
      expect(st.daysLeft, 31);
      expect(st.dailyAllowance, 1000);
    });

    test('last day: what is left is for today; a finished month gives nothing, without dividing by zero', () {
      final expenses = [_e('1', 50000, DateTime(2026, 11, 10))];
      final last = BudgetMath.status(budget: 60000, expenses: expenses, month: nov, today: DateTime(2026, 11, 30));
      expect(last.daysLeft, 1);
      expect(last.dailyAllowance, 10000);
      final after = BudgetMath.status(budget: 60000, expenses: expenses, month: nov, today: DateTime(2026, 12, 1));
      expect(after.daysLeft, 0);
      expect(after.dailyAllowance, 0);
    });

    test('spending less raises the allowance, spending more lowers it', () {
      final day10 = DateTime(2026, 11, 10);
      final frugal = BudgetMath.status(budget: 30000, expenses: [_e('1', 4000, DateTime(2026, 11, 5))], month: nov, today: day10);
      final lavish = BudgetMath.status(budget: 30000, expenses: [_e('1', 16000, DateTime(2026, 11, 5))], month: nov, today: day10);
      expect(frugal.dailyAllowance, greaterThan(1000));
      expect(lavish.dailyAllowance, lessThan(1000));
    });

    test('overspending never makes the remaining negative: it is shown apart', () {
      final st = BudgetMath.status(
        budget: 10000,
        expenses: [_e('1', 12500, DateTime(2026, 11, 3))],
        month: nov,
        today: DateTime(2026, 11, 4),
      );
      expect(st.remaining, 0);
      expect(st.overspent, 2500);
      expect(st.dailyAllowance, 0);
      expect(st.level, BudgetLevel.exceeded);
    });

    test('from 80 % used, the month is approaching its limit', () {
      final st = BudgetMath.status(
        budget: 10000,
        expenses: [_e('1', 8000, DateTime(2026, 11, 3))],
        month: nov,
        today: DateTime(2026, 11, 4),
      );
      expect(st.level, BudgetLevel.approaching);
    });

    test('other months do not count, and today\'s spending is known', () {
      final st = BudgetMath.status(
        budget: 10000,
        expenses: [_e('1', 900, DateTime(2026, 10, 31)), _e('2', 300, DateTime(2026, 11, 4)), _e('3', 200, DateTime(2026, 11, 3))],
        month: nov,
        today: DateTime(2026, 11, 4),
      );
      expect(st.spent, 500);
      expect(st.spentToday, 300);
    });

    test('expenses beyond the budget are the ones flagged, in the order spent', () {
      final ids = BudgetMath.overBudgetIds(1000, [
        _e('2', 600, DateTime(2026, 11, 5)),
        _e('1', 700, DateTime(2026, 11, 2)),
        _e('3', 100, DateTime(2026, 11, 6)),
      ]);
      expect(ids, {'2', '3'});
    });

    test('a refund is never flagged over the budget, and lowers what was spent', () {
      final ids = BudgetMath.overBudgetIds(1000, [
        _e('1', 1500, DateTime(2026, 11, 2)),
        _e('2', -200, DateTime(2026, 11, 3)), // still 300 over
        _e('3', -400, DateTime(2026, 11, 4)), // back under
        _e('4', 50, DateTime(2026, 11, 5)),
      ]);
      expect(ids, {'1'});
    });

    test('a refund in another currency keeps the rate it was recorded with', () {
      final refund = Expense(amount: -5000, originalAmount: -20, originalCurrency: 'EUR', categoryId: 'food', date: DateTime(2026, 11, 2));
      expect(refund.rate, 250);
    });
  });

  group('Automatic budget', () {
    test('income minus savings, as a share or an amount', () {
      expect(const BudgetConfig(income: 80000, savingsPercent: 25).budget, 60000);
      expect(const BudgetConfig(income: 80000, savingsAmount: 20000).budget, 60000);
      expect(const BudgetConfig(income: 80000, savingsAmount: 20000).savings, 20000);
      expect(const BudgetConfig(income: 80000).budget, 80000, reason: 'no savings asked');
    });

    test('without an income, no budget is invented', () {
      expect(const BudgetConfig().budget, isNull);
      expect(const BudgetConfig(savingsPercent: 20).budget, isNull);
    });

    test('savings never exceed the income', () {
      expect(const BudgetConfig(income: 1000, savingsAmount: 5000).budget, 0);
      expect(const BudgetConfig(income: 1000, savingsPercent: 150).budget, 0);
    });

    test('manual mode uses the typed amount only', () {
      expect(const BudgetConfig(mode: BudgetMode.manual, income: 80000, manualBudget: 45000).budget, 45000);
      expect(const BudgetConfig(mode: BudgetMode.manual).budget, isNull);
    });
  });

  group('Category budgets', () {
    test('they split the monthly budget and never add to it', () {
      final categories = {'food': 18000.0, 'transport': 8000.0, 'shopping': 20000.0};
      expect(BudgetMath.unallocated(60000, categories, except: 'leisure'), 14000);
      expect(BudgetMath.unallocated(60000, categories, except: 'food'), 32000, reason: 'its own amount is free to change');
      expect(BudgetMath.unallocated(40000, categories, except: 'leisure'), 0);
    });
  });

  group('Monthly report', () {
    test('figures of a past month', () {
      final r = MonthReport.build(
        month: DateTime(2026, 10),
        expenses: [
          _e('1', 3000, DateTime(2026, 10, 2)),
          _e('2', 12000, DateTime(2026, 10, 9), category: 'housing'),
          _e('3', 1500, DateTime(2026, 10, 20)),
          _e('4', 999, DateTime(2026, 11, 1)),
        ],
        income: 80000,
        budget: 50000,
        today: DateTime(2026, 11, 16),
      );
      expect(r.expenses, 16500);
      expect(r.count, 3);
      expect(r.net, 63500);
      expect(r.averagePerDay, closeTo(16500 / 31, 0.001));
      expect(r.topCategoryId, 'housing');
      expect(r.biggest!.id, '2');
      expect(r.budgetUsage, closeTo(0.33, 0.001));
    });

    test('the current month averages over the days so far', () {
      final r = MonthReport.build(
        month: nov,
        expenses: [_e('1', 1600, DateTime(2026, 11, 3))],
        income: 0,
        budget: 0,
        today: DateTime(2026, 11, 16),
      );
      expect(r.averagePerDay, 100);
      expect(r.budgetUsage, isNull);
    });

    test('change from the previous month', () {
      expect(MonthReport.change(12000, 10000), closeTo(0.2, 1e-9));
      expect(MonthReport.change(500, 0), isNull);
    });
  });

  group('AppState', () {
    final now = DateTime.now();
    Deposit dep(String id, String wallet, double amount, DepositKind kind, {String? from}) =>
        Deposit(id: id, walletId: wallet, amount: amount, date: monthStart(now), kind: kind, sourceWalletId: from);

    Future<AppState> load(_Repo repo) async {
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      return app;
    }

    test('adding, editing and deleting an expense update the month at once', () async {
      final app = await load(_Repo(wallets_: [cash]));
      await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 60000));
      expect(app.budgetStatus(now).remaining, 60000);

      await app.addExpense(_e('x', 4000, now));
      final added = app.expenses.single;
      expect(app.budgetStatus(now).spent, 4000);

      await app.updateExpense(added.copyWith(amount: 6000));
      expect(app.budgetStatus(now).spent, 6000);
      expect(app.budgetStatus(now).remaining, 54000);

      await app.deleteExpense(app.expenses.single);
      expect(app.budgetStatus(now).spent, 0);
    });

    test('every wallet counts; transfers, withdrawals and corrections do not', () async {
      final app = await load(
        _Repo(
          wallets_: [cash, bank],
          deposits_: [
            dep('i', 'bank', 80000, DepositKind.income),
            dep('t', 'cash', 5000, DepositKind.transfer, from: 'bank'),
            dep('w', 'cash', 1000, DepositKind.withdrawal),
            dep('a', 'cash', 300, DepositKind.adjustment),
          ],
          expenses_: [
            _e('1', 2000, now),
            _e('2', 3000, now, wallet: 'bank'),
          ],
        ),
      );
      await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 30000));
      expect(app.budgetStatus(now).spent, 5000);
      expect(app.incomeInMonth(now), 80000, reason: 'only money received from outside is income');
      expect(app.balanceOf(bank), 80000 - 5000 - 3000);
      expect(app.balanceOf(cash), 5000 - 1000 + 300 - 2000);
    });

    test('income in a foreign wallet is converted at its rate', () async {
      final paysera = Wallet(id: 'p', name: 'Paysera', type: WalletType.mobile, createdAt: DateTime(2026), currencyCode: 'EUR', rate: 250);
      final app = await load(_Repo(wallets_: [cash, paysera], deposits_: [dep('i', 'p', 100, DepositKind.income)]));
      expect(app.incomeInMonth(now), 25000);
    });

    test('automatic mode turns the configured income into the budget', () async {
      final app = await load(_Repo(wallets_: [cash]));
      await app.setBudgetConfig(const BudgetConfig(income: 80000, savingsAmount: 20000));
      expect(app.totalBudget, 60000);
      expect(app.budgetConfig.mode, BudgetMode.automatic);
      expect(app.budgetConfig.savings, 20000);
      await app.setBudgetConfig(const BudgetConfig(income: 0));
      expect(app.totalBudget, 0, reason: 'no income, no budget');
    });

    test('a budget set before modes existed stays as typed', () async {
      final app = await load(_Repo(wallets_: [cash], budgets: {'total': 35000}));
      expect(app.budgetConfig.mode, BudgetMode.manual);
      expect(app.budgetConfig.manualBudget, 35000);
      expect(app.totalBudget, 35000);
    });

    test('reports use the budget each month had', () async {
      final repo = _Repo(wallets_: [cash], budgets: {'total': 60000, 'hist:2026-01': 40000, 'hist:2026-03': 50000});
      final app = await load(repo);
      expect(app.monthlyBudgetFor(DateTime(2025, 12)), 0, reason: 'nothing recorded then');
      expect(app.monthlyBudgetFor(DateTime(2026, 2)), 40000, reason: 'unchanged since January');
      expect(app.monthlyBudgetFor(DateTime(2026, 3)), 50000);
      expect(app.monthlyBudgetFor(now), 60000);
      expect(repo.stored.keys.where((k) => k.startsWith('hist:')).length, 3, reason: 'this month recorded on load');
    });

    test('wallet reservations shrink when the budget no longer covers them', () async {
      final app = await load(_Repo(wallets_: [cash, bank], deposits_: [dep('i', 'cash', 90000, DepositKind.income)]));
      await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 60000), funds: {'cash': 40000, 'bank': 20000});
      await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 30000));
      expect(app.envelope.funds, {'cash': 20000, 'bank': 10000});
      expect(app.reservedIn(cash), 20000);
      expect(app.freeIn(cash), 70000);
    });

    test('category budgets cannot take more than what is left of the monthly budget', () async {
      final app = await load(_Repo(wallets_: [cash], budgets: {'total': 60000, 'food': 18000, 'transport': 8000}));
      expect(app.unallocatedFor('shopping'), 34000);
      expect(app.unallocatedFor('food'), 52000);
    });

    test('last month\'s leftover is offered once, from its own budget', () async {
      final last = addMonths(monthStart(now), -1);
      final repo = _Repo(
        wallets_: [cash],
        expenses_: [_e('1', 30000, last.add(const Duration(days: 2)))],
        budgets: {
          'total': 99000,
          'hist:${last.year}-${last.month.toString().padLeft(2, '0')}': 35000,
          AppState.sinceKey: (last.year * 100 + last.month).toDouble(),
        },
      );
      final app = await load(repo);
      expect(app.monthToClose!.left, 5000);
      await app.closeMonth(app.monthToClose!.month);
      expect(app.monthToClose, isNull);
    });
  });

  group('History, recorded income and refunds', () {
    final now = DateTime.now();
    final thisMonth = monthStart(now);
    Future<AppState> load(_Repo repo) async {
      final app = AppState(repo);
      await app.load();
      app.setPlan(Plan.premium);
      return app;
    }

    test('a budget from before monthly records applies from the first month with data', () async {
      final first = addMonths(thisMonth, -4);
      final app = await load(
        _Repo(wallets_: [cash], budgets: {'total': 35000}, expenses_: [_e('1', 1000, first.add(const Duration(days: 3)))]),
      );
      expect(app.monthlyBudgetFor(addMonths(thisMonth, -2)), 35000);
      expect(app.monthlyBudgetFor(addMonths(thisMonth, -5)), 0, reason: 'before any data, nothing is assumed');
    });

    test('category budgets keep the amount each month had', () async {
      final first = addMonths(thisMonth, -3);
      final app = await load(
        _Repo(wallets_: [cash], budgets: {'total': 60000, 'food': 18000}, expenses_: [_e('1', 1000, first.add(const Duration(days: 1)))]),
      );
      await app.setBudget('food', 20000);
      expect(app.categoryBudgetFor('food', now), 20000);
      expect(app.categoryBudgetFor('food', addMonths(thisMonth, -1)), 18000);
      await app.setBudget('food', 0);
      expect(app.categoryBudgetFor('food', now), 0);
      expect(app.categoryBudgetFor('food', addMonths(thisMonth, -1)), 18000, reason: 'removing it now keeps the past');
    });

    test('an automatic budget can follow the income actually recorded', () async {
      Deposit income(String id, int monthsAgo, double amount) => Deposit(
        id: id,
        walletId: 'cash',
        amount: amount,
        date: addMonths(thisMonth, -monthsAgo).add(const Duration(days: 1)),
        kind: DepositKind.income,
      );
      final app = await load(_Repo(wallets_: [cash], deposits_: [income('a', 1, 80000), income('b', 2, 70000), income('now', 0, 99999)]));
      expect(app.recordedIncomeAverage, 75000, reason: 'complete months only');
      await app.setBudgetConfig(const BudgetConfig(incomeFromRecords: true, savingsPercent: 10));
      expect(app.totalBudget, 67500);
      expect(app.budgetConfig.incomeFromRecords, isTrue);

      // New income recorded for a past month: the budget follows.
      await app.saveDeposit(income('c', 3, 75000));
      expect(app.recordedIncomeAverage, 75000);
      await app.saveDeposit(income('d', 1, 10000));
      expect(app.recordedIncomeAverage, closeTo((90000 + 70000 + 75000) / 3, 0.01));
      expect(app.totalBudget, closeTo((90000 + 70000 + 75000) / 3 * 0.9, 0.01));
    });

    test('without recorded income, a records-based budget stays empty', () async {
      final app = await load(_Repo(wallets_: [cash]));
      expect(app.recordedIncomeAverage, isNull);
      await app.setBudgetConfig(const BudgetConfig(incomeFromRecords: true));
      expect(app.totalBudget, 0);
    });

    test('a refund lowers the month, its category and goes back to the wallet', () async {
      final app = await load(
        _Repo(
          wallets_: [cash],
          deposits_: [Deposit(id: 'i', walletId: 'cash', amount: 10000, date: thisMonth, kind: DepositKind.income)],
          expenses_: [
            _e('1', 3000, now, category: 'shopping'),
            _e('2', -1000, now, category: 'shopping'),
          ],
        ),
      );
      await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 5000));
      expect(app.budgetStatus(now).spent, 2000);
      expect(app.spentIn(now, categoryId: 'shopping'), 2000);
      expect(app.balanceOf(cash), 8000);
      final r = app.report(now);
      expect(r.count, 1, reason: 'a refund is not an expense of its own');
      expect(r.biggest!.id, '1');
    });

    test('a category refunded beyond its spending is left out of the breakdown', () async {
      final app = await load(
        _Repo(
          wallets_: [cash],
          expenses_: [
            _e('1', -500, now, category: 'health'),
            _e('2', 800, now),
          ],
        ),
      );
      expect(app.byCategory(now).map((e) => e.key.id), ['food']);
    });
  });
}
