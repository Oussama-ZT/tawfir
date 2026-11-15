import 'package:eco_budget/data/repository.dart';
import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/models/deposit.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/savings_goal.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/subscription_service.dart';
import 'package:eco_budget/state/app_state.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// In-memory storage so AppState can be tested without a database.
class _MemoryRepo implements BudgetRepository {
  _MemoryRepo({this.wallets_ = const [], this.goals_ = const [], this.budgets_ = const {}, this.categories_ = const []});

  final List<Wallet> wallets_;
  final List<SavingsGoal> goals_;
  final Map<String, double> budgets_;
  final List<ExpenseCategory> categories_;
  var _n = 0;

  @override
  Future<List<Expense>> expenses() async => [];
  @override
  Future<String> insertExpense(Expense e) async => '${_n++}';
  @override
  Future<void> updateExpense(Expense e) async {}
  @override
  Future<void> deleteExpense(String id) async {}
  @override
  Future<Map<String, double>> budgets() async => Map.of(budgets_);
  @override
  Future<void> setBudget(String key, double amount) async {}
  @override
  Future<List<SavingsGoal>> goals() async => [...goals_];
  @override
  Future<String> insertGoal(SavingsGoal g) async => '${_n++}';
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
  Future<List<ExpenseCategory>> categories() async => [...categories_];
  @override
  Future<void> saveCategory(ExpenseCategory c) async {}
  @override
  Future<void> deleteCategory(String id) async {}
  @override
  Future<List<Deposit>> deposits() async => [];
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

Wallet _w(String id, WalletType type, int month, {String? currency, double? rate}) =>
    Wallet(id: id, name: id, type: type, createdAt: DateTime(2026, month), currencyCode: currency, rate: rate);

void main() {
  setUp(() => activeCurrency = Currency.byCode('DZD'));
  tearDown(() {
    activeCurrency = Currency.byCode('MAD');
    ExpenseCategory.customList = const [];
    ExpenseCategory.customEnabled = true;
  });

  Future<AppState> stateWith(_MemoryRepo repo, Plan plan) async {
    final app = AppState(repo);
    await app.load();
    app.setPlan(plan);
    return app;
  }

  final cash = _w('cash', WalletType.cash, 1);
  final bank = _w('bank', WalletType.bank, 2);
  final paysera = _w('paysera', WalletType.mobile, 3, currency: 'EUR', rate: 250);

  test('Premium: nothing is frozen', () async {
    final app = await stateWith(_MemoryRepo(wallets_: [cash, bank, paysera]), Plan.premium);
    expect(app.frozenWalletIds, isEmpty);
  });

  test('back to Pro: the euro mobile wallet freezes, cash and bank stay', () async {
    final app = await stateWith(_MemoryRepo(wallets_: [cash, bank, paysera]), Plan.pro);
    expect(app.frozenWalletIds, {'paysera'});
    expect(app.planToUnfreeze(paysera), Plan.premium);
    expect(app.activeWallets.map((w) => w.id), ['cash', 'bank']);
  });

  test('back to Starter: only the oldest allowed wallet stays usable', () async {
    final app = await stateWith(_MemoryRepo(wallets_: [cash, bank, paysera]), Plan.starter);
    expect(app.frozenWalletIds, {'bank', 'paysera'});
    expect(app.defaultWallet.id, 'cash');
    expect(app.planToUnfreeze(bank), Plan.pro);
    expect(app.planToUnfreeze(paysera), Plan.premium);
  });

  test('a cancelled plan stays active until the end of the paid period', () async {
    await initializeDateFormatting('fr');
    final end = DateTime(2026, 11, 15);
    expect(PlanStatus(Plan.pro, expiresAt: end, willRenew: false).endsSoon, isTrue);
    expect(PlanStatus(Plan.pro, expiresAt: end).endsSoon, isFalse, reason: 'still renewing');
    expect(PlanStatus.free.endsSoon, isFalse);
    expect(fullDate(end), '15/11/2026');
  });

  test('a single wallet is never frozen, even if the plan does not allow it', () async {
    final app = await stateWith(_MemoryRepo(wallets_: [paysera]), Plan.starter);
    expect(app.frozenWalletIds, isEmpty);
  });

  test('the main wallet stays active even when Starter would not allow its type', () async {
    final mainEuro = _w('main', WalletType.mobile, 1, currency: 'EUR', rate: 250);
    final app = await stateWith(_MemoryRepo(wallets_: [mainEuro, _w('cash', WalletType.cash, 2)]), Plan.starter);
    expect(app.mainWallet!.id, 'main');
    expect(app.frozenWalletIds, {'cash'});
    expect(app.planToUnfreeze(app.walletById('cash')), Plan.pro);
  });

  test('goals beyond the Starter limit freeze, newest first', () async {
    final goals = [
      for (var i = 0; i < 4; i++)
        SavingsGoal(id: 'g$i', name: 'Objectif $i', target: 1000, createdAt: DateTime(2026, i + 1)),
    ];
    final app = await stateWith(_MemoryRepo(wallets_: [cash], goals_: goals), Plan.starter);
    expect([for (final g in app.goals) app.isGoalFrozen(g)], [false, false, true, true]);
    app.setPlan(Plan.pro);
    expect(app.goals.any(app.isGoalFrozen), isFalse);
  });

  test('custom categories and extra budgets freeze on Starter and are ignored', () async {
    final pets = ExpenseCategory.custom(id: 'c1', label: 'Animaux', iconKey: 'pets', color: const Color(0xFF2E7D32));
    final budgets = {'total': 9000.0, 'food': 2000.0, 'restaurant': 500.0, 'transport': 300.0, 'leisure': 400.0, 'c1': 200.0};
    final app = await stateWith(
        _MemoryRepo(wallets_: [cash], budgets_: budgets, categories_: [pets]), Plan.starter);

    expect(ExpenseCategory.visible.any((c) => c.id == 'c1'), isFalse, reason: 'not offered for new expenses');
    expect(ExpenseCategory.byId('c1').label, 'Animaux', reason: 'past expenses keep it');
    // 3 category budgets allowed, in category order: food, restaurant, transport.
    expect(app.frozenBudgetKeys, {'leisure', 'c1'});
    expect(app.activeBudgets.containsKey('leisure'), isFalse);
    expect(app.activeBudgets['total'], 9000);

    app.setPlan(Plan.pro);
    expect(app.frozenBudgetKeys, isEmpty);
    expect(ExpenseCategory.visible.any((c) => c.id == 'c1'), isTrue);
  });
}
