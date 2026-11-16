import 'package:eco_budget/data/repository.dart';
import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/currency.dart';
import 'package:eco_budget/models/debt.dart';
import 'package:eco_budget/models/deposit.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/savings_goal.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/budget_math.dart';
import 'package:eco_budget/state/app_state.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Storage that really keeps deposits and debts, so the wallet side of each
/// debt can be checked after a reload.
class _Repo implements BudgetRepository {
  _Repo(List<Wallet> wallets, {List<Deposit> deposits = const []})
      : _wallets = [...wallets],
        _deposits = {for (final d in deposits) d.id: d};

  final List<Wallet> _wallets;
  final Map<String, Deposit> _deposits;
  final Map<String, Debt> _debts = {};
  final Map<String, double> _budgets = {};
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
  Future<Map<String, double>> budgets() async => Map.of(_budgets);
  @override
  Future<void> setBudget(String key, double amount) async =>
      amount <= 0 ? _budgets.remove(key) : _budgets[key] = amount;
  @override
  Future<List<SavingsGoal>> goals() async => [];
  @override
  Future<String> insertGoal(SavingsGoal g) async => '${_n++}';
  @override
  Future<void> updateGoal(SavingsGoal g) async {}
  @override
  Future<void> deleteGoal(String id) async {}
  @override
  Future<List<Wallet>> wallets() async => [..._wallets];
  @override
  Future<void> saveWallet(Wallet w) async {}
  @override
  Future<void> deleteWallet(String id, {required String moveTo}) async => _wallets.removeWhere((w) => w.id == id);
  @override
  Future<List<ExpenseCategory>> categories() async => [];
  @override
  Future<void> saveCategory(ExpenseCategory c) async {}
  @override
  Future<void> deleteCategory(String id) async {}
  @override
  Future<List<Deposit>> deposits() async => _deposits.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  @override
  Future<void> saveDeposit(Deposit d) async => _deposits[d.id] = d;
  @override
  Future<void> deleteDeposit(String id) async => _deposits.remove(id);
  @override
  Future<List<Debt>> debts() async => [..._debts.values];
  @override
  Future<void> saveDebt(Debt d) async => _debts[d.id] = Debt.fromMap(d.toMap());
  @override
  Future<void> deleteDebt(String id) async => _debts.remove(id);
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
}

void main() {
  setUp(() => activeCurrency = Currency.byCode('DZD'));
  tearDown(() => activeCurrency = Currency.byCode('MAD'));

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  final cash = Wallet(id: 'cash', name: 'Espèces', type: WalletType.cash, createdAt: DateTime(2026));
  final bank = Wallet(id: 'bank', name: 'Banque', type: WalletType.bank, createdAt: DateTime(2026, 2));
  Deposit start(String wallet, double amount) => Deposit(
      id: 'start-$wallet', walletId: wallet, amount: amount, date: DateTime(now.year, now.month), kind: DepositKind.adjustment);

  Future<(AppState, _Repo)> load({List<Wallet>? wallets}) async {
    final repo = _Repo(wallets ?? [cash, bank], deposits: [start('cash', 20000), start('bank', 50000)]);
    final app = AppState(repo);
    await app.load();
    app.setPlan(Plan.premium);
    return (app, repo);
  }

  Debt lend(String person, double amount, {String? wallet = 'cash', DebtDirection direction = DebtDirection.lent}) => Debt(
        id: 'debt-$person',
        person: person,
        direction: direction,
        createdAt: today,
        entries: [DebtEntry(id: 'e-$person', kind: DebtEntryKind.start, amount: amount, date: today, walletId: wallet)],
      );

  test('lending takes money from the wallet, without being an expense or income', () async {
    final (app, _) = await load();
    await app.setBudgetConfig(const BudgetConfig(mode: BudgetMode.manual, manualBudget: 30000));
    await app.saveDebt(lend('Karim', 5000));

    expect(app.balanceOf(cash), 15000);
    expect(app.owedToMe, 5000);
    expect(app.owedByMe, 0);
    expect(app.budgetStatus(now).spent, 0, reason: 'a loan is not spending');
    expect(app.incomeInMonth(now), 0, reason: 'nor is it income');
    final d = app.deposits.firstWhere((d) => d.id == 'e-Karim');
    expect(d.kind, DepositKind.debt);
    expect(app.debtOfDeposit(d)?.person, 'Karim');
  });

  test('repayments bring the money back, to any wallet, until the debt is settled', () async {
    final (app, _) = await load();
    await app.saveDebt(lend('Karim', 5000));
    var debt = app.debts.single;
    await app.addDebtEntry(debt, DebtEntry(id: 'r1', kind: DebtEntryKind.repayment, amount: 2000, date: today, walletId: 'bank'));
    debt = app.debts.single;
    expect(debt.remaining, 3000);
    expect(app.balanceOf(bank), 52000);
    expect(app.balanceOf(cash), 15000);

    await app.addDebtEntry(debt, DebtEntry(id: 'r2', kind: DebtEntryKind.repayment, amount: 3000, date: today, walletId: 'cash'));
    debt = app.debts.single;
    expect(debt.isSettled, isTrue);
    expect(app.owedToMe, 0);
    expect(app.balanceOf(cash), 18000);
  });

  test('borrowing puts money in the wallet; paying it back takes it out', () async {
    final (app, _) = await load();
    await app.saveDebt(lend('Yacine', 10000, direction: DebtDirection.borrowed));
    expect(app.balanceOf(cash), 30000);
    expect(app.owedByMe, 10000);

    await app.addDebtEntry(
        app.debts.single, DebtEntry(id: 'r', kind: DebtEntryKind.repayment, amount: 4000, date: today, walletId: 'bank'));
    expect(app.balanceOf(bank), 46000);
    expect(app.owedByMe, 6000);

    await app.addDebtEntry(
        app.debts.single, DebtEntry(id: 'm', kind: DebtEntryKind.more, amount: 1000, date: today, walletId: 'cash'));
    expect(app.owedByMe, 7000);
    expect(app.balanceOf(cash), 31000);
  });

  test('a debt from before the app changes no balance', () async {
    final (app, _) = await load();
    await app.saveDebt(lend('Sami', 8000, wallet: null));
    expect(app.balanceOf(cash), 20000);
    expect(app.deposits.where((d) => d.kind == DepositKind.debt), isEmpty);
    expect(app.owedToMe, 8000);
  });

  test('editing a debt moves its wallet movement, or removes it', () async {
    final (app, _) = await load();
    await app.saveDebt(lend('Karim', 5000));
    final debt = app.debts.single;
    final moved = debt.copyWith(entries: [debt.start!.copyWith(amount: 6000, walletId: 'bank')]);
    await app.saveDebt(moved);
    expect(app.balanceOf(cash), 20000);
    expect(app.balanceOf(bank), 44000);

    await app.saveDebt(moved.copyWith(entries: [moved.start!.copyWith(clearWallet: true)]));
    expect(app.balanceOf(bank), 50000);
    expect(app.deposits.where((d) => d.kind == DepositKind.debt), isEmpty);
  });

  test('removing a repayment, or the whole debt, removes its wallet movements', () async {
    final (app, repo) = await load();
    await app.saveDebt(lend('Karim', 5000));
    final r = DebtEntry(id: 'r1', kind: DebtEntryKind.repayment, amount: 2000, date: today, walletId: 'cash');
    await app.addDebtEntry(app.debts.single, r);
    await app.removeDebtEntry(app.debts.single, r);
    expect(app.debts.single.remaining, 5000);
    expect(app.balanceOf(cash), 15000);

    await app.deleteDebt(app.debts.single);
    expect(app.debts, isEmpty);
    expect(app.balanceOf(cash), 20000);
    expect((await repo.deposits()).where((d) => d.kind == DepositKind.debt), isEmpty);
  });

  test('deleting a wallet keeps what is owed and the money', () async {
    final (app, _) = await load();
    await app.saveDebt(lend('Karim', 5000, wallet: 'bank'));
    await app.deleteWallet(bank, moveTo: cash);
    expect(app.debts.single.remaining, 5000);
    expect(app.debts.single.start!.walletId, isNull);
    expect(app.balanceOf(cash), 20000 + 45000, reason: 'what was left in the bank arrives in cash');
  });

  test('everything survives a reload', () async {
    final (app, repo) = await load();
    await app.saveDebt(lend('Karim', 5000).copyWith(dueDate: DateTime(2026, 12, 31), note: 'Pour la voiture'));
    await app.addDebtEntry(app.debts.single, DebtEntry(id: 'r1', kind: DebtEntryKind.repayment, amount: 1500, date: today));
    final again = AppState(repo);
    await again.load();
    final debt = again.debts.single;
    expect(debt.person, 'Karim');
    expect(debt.remaining, 3500);
    expect(debt.dueDate, DateTime(2026, 12, 31));
    expect(debt.note, 'Pour la voiture');
    expect(again.balanceOf(cash), 15000);
  });

  test('late, settled and people suggested again', () async {
    final (app, _) = await load();
    final yesterday = today.subtract(const Duration(days: 1));
    await app.saveDebt(lend('Karim', 5000).copyWith(dueDate: yesterday));
    await app.saveDebt(lend('Amina', 2000, direction: DebtDirection.borrowed));
    expect(app.debts.firstWhere((d) => d.person == 'Karim').isOverdue(now), isTrue);
    expect(app.debts.firstWhere((d) => d.person == 'Amina').isOverdue(now), isFalse);
    expect(app.debtPeople.toSet(), {'Karim', 'Amina'});
  });
}
