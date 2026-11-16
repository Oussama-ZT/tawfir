import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/demo_data.dart';
import '../data/repository.dart';
import '../models/category.dart';
import '../models/debt.dart';
import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/insight.dart';
import '../models/plan.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';
import '../services/budget_math.dart';
import '../services/envelope_math.dart';
import '../services/insights_service.dart';
import '../services/wallet_math.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../utils/ids.dart';
import '../l10n/l10n.dart';

class AppState extends ChangeNotifier {
  AppState(this._repo);

  /// SQLite or Firestore, depending on the account type.
  final BudgetRepository _repo;
  bool _loaded = false;

  bool get loaded => _loaded;

  List<Expense> _expenses = [];
  Map<String, double> _budgets = {};
  List<SavingsGoal> _goals = [];
  List<Wallet> _wallets = [];
  List<Deposit> _deposits = [];
  List<Debt> _debts = [];
  List<Insight>? _insights;

  List<Expense> get expenses => _expenses;
  Map<String, double> get budgets => _budgets;
  List<SavingsGoal> get goals => _goals;

  /// Never empty once loaded: a new account gets a cash wallet.
  List<Wallet> get wallets => _wallets;
  bool get hasSeveralWallets => _wallets.length > 1;

  Wallet walletById(String? id) => _wallets.firstWhere((w) => w.id == id, orElse: () => _wallets.first);

  /// Money added to wallets, newest first.
  List<Deposit> get deposits => _deposits;

  /// What is left in a wallet, in its currency; null until money is added.
  double? balanceOf(Wallet w) => WalletMath.balance(w, _expenses, _deposits, activeCurrency.code);

  double incomeIn(Wallet w, DateTime month) => WalletMath.incomeIn(w, _deposits, month);

  /// Start of the period shown under a balance: this month, or when tracking
  /// began if that was later.
  DateTime? flowsStart(Wallet w) {
    final start = WalletMath.trackingStart(w, _deposits);
    if (start == null) return null;
    final month = monthStart(DateTime.now());
    return start.isAfter(month) ? start : month;
  }

  ({double received, double spent, double withdrawn}) flowsSince(Wallet w, DateTime since) =>
      WalletMath.flowsSince(w, _expenses, _deposits, since, activeCurrency.code);

  /// Deposits and expenses of a wallet, newest first.
  List<({DateTime date, Expense? expense, Deposit? deposit})> historyOf(Wallet w) {
    final items = <({DateTime date, Expense? expense, Deposit? deposit})>[
      for (final d in _deposits)
        if (d.walletId == w.id || d.sourceWalletId == w.id) (date: d.date, expense: null, deposit: d),
      for (final e in _expenses)
        if (e.walletId == w.id) (date: e.date, expense: e, deposit: null),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  bool get hasForeignWallets => _wallets.any((w) => w.isForeign(activeCurrency.code));

  /// What was spent from a wallet in its own currency (euros for a Paysera
  /// wallet). Expenses entered before the wallet changed currency are
  /// converted with its current rate.
  double spentInWalletCurrency(DateTime month, Wallet w) {
    final items = expensesIn(month, walletId: w.id);
    return items.fold(0.0, (s, e) => s + WalletMath.expenseIn(w, e, activeCurrency.code));
  }

  /// Custom categories of this account (the defaults live in code).
  List<ExpenseCategory> get customCategories => ExpenseCategory.customList;

  double get totalBudget => _budgets[InsightsService.totalBudgetKey] ?? 0;
  double budgetFor(String categoryId) => _budgets[categoryId] ?? 0;

  AppLanguage? _insightsLanguage;

  /// Tips are written in the current language: regenerated when it changes.
  List<Insight> get insights {
    if (_insightsLanguage != appLanguage) {
      _insights = null;
      _insightsLanguage = appLanguage;
    }
    return _insights ??= InsightsService.generate(
      expenses: _expenses,
      budgets: activeBudgets,
      goals: _goals,
      now: DateTime.now(),
    );
  }

  /// Number of categories with their own budget (the overall one excluded).
  int get categoryBudgetCount =>
      _budgets.keys.where((k) => k != InsightsService.totalBudgetKey && !k.contains(':')).length;

  Future<void> load() async {
    _expenses = await _repo.expenses();
    _budgets = await _repo.budgets();
    _goals = await _repo.goals();
    _wallets = await _repo.wallets();
    _deposits = await _repo.deposits();
    _debts = await _repo.debts();
    ExpenseCategory.customList = await _repo.categories();
    if (_wallets.isEmpty) {
      final first = Wallet.starter(newId('w'));
      await _repo.saveWallet(first);
      _wallets = [first];
    }
    // Expenses recorded before wallets existed go to the first wallet.
    final first = _wallets.first.id;
    final orphans = _expenses.where((e) => e.walletId == null || !_wallets.any((w) => w.id == e.walletId)).toList();
    for (final e in orphans) {
      await _repo.updateExpense(e.copyWith(walletId: first));
    }
    if (orphans.isNotEmpty) {
      _expenses = [for (final e in _expenses) orphans.contains(e) ? e.copyWith(walletId: first) : e];
    }
    await _snapshotBudget();
    await _refreshRecordedBudget();
    _loaded = true;
    _changed();
  }

  void _changed() {
    _insights = null;
    _envelopeMonths.clear();
    _statuses.clear();
    _overBudget.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------- freeze --
  //
  // When a subscription ends, whatever goes beyond the new plan is frozen:
  // still shown (balances, history, progress) but not usable or editable.
  // Nothing is deleted, and subscribing again unfreezes it at once.

  Plan? _plan;
  bool _disposed = false;

  Plan get plan => _plan ?? Plan.starter;

  /// Called by the provider whenever the plan changes.
  void setPlan(Plan p) {
    if (p == _plan) return;
    _plan = p;
    ExpenseCategory.customEnabled = p.customCategories;
    _insights = null;
    // Not during the build that delivered the new plan.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The first wallet created. It is never frozen, whatever the plan.
  Wallet? get mainWallet => _wallets.isEmpty ? null : _wallets.first;

  bool isMainWallet(Wallet w) => w.id == mainWallet?.id;

  /// Wallets the plan no longer covers. The main wallet always stays active;
  /// on Starter it is the only one. Pro keeps, after it, the oldest wallet
  /// it allows (cash or bank, main currency).
  Set<String> get frozenWalletIds => _frozenUnder(plan);

  Set<String> _frozenUnder(Plan p) {
    final frozen = <String>{};
    var active = 1;
    for (final w in _wallets.skip(1)) {
      final allowed = p.allowsWalletType(w.type) &&
          (p.foreignCurrencyWallets || !w.isForeign(activeCurrency.code)) &&
          (p.walletLimit == null || active < p.walletLimit!);
      if (allowed) {
        active++;
      } else {
        frozen.add(w.id);
      }
    }
    return frozen;
  }

  bool isWalletFrozen(Wallet w) => frozenWalletIds.contains(w.id);

  List<Wallet> get activeWallets {
    final frozen = frozenWalletIds;
    return _wallets.where((w) => !frozen.contains(w.id)).toList();
  }

  /// Wallet offered first for a new movement: the last one used if active.
  Wallet get defaultWallet {
    final active = activeWallets;
    return active.firstWhere((w) => w.id == lastWalletId, orElse: () => active.first);
  }

  /// Lowest plan under which this wallet would be usable again.
  Plan planToUnfreeze(Wallet w) => _frozenUnder(Plan.pro).contains(w.id) ? Plan.premium : Plan.pro;

  /// Goals beyond the plan's limit, newest first, are frozen.
  bool isGoalFrozen(SavingsGoal g) {
    final limit = plan.goalLimit;
    if (limit == null) return false;
    return _goals.indexWhere((x) => x.id == g.id) >= limit;
  }

  /// Category budgets beyond the plan's limit (in category order), and those
  /// of frozen custom categories. They are ignored by the alerts.
  Set<String> get frozenBudgetKeys {
    final limit = plan.categoryBudgetLimit;
    final frozen = <String>{};
    var kept = 0;
    for (final c in [...ExpenseCategory.defaults, ...ExpenseCategory.customList]) {
      if ((_budgets[c.id] ?? 0) <= 0) continue;
      if (c.isCustom && !plan.customCategories) {
        frozen.add(c.id);
      } else if (limit != null && kept >= limit) {
        frozen.add(c.id);
      } else {
        kept++;
      }
    }
    return frozen;
  }

  Map<String, double> get activeBudgets {
    final frozen = frozenBudgetKeys;
    return {
      for (final e in _budgets.entries)
        if (!frozen.contains(e.key) && !e.key.contains(':')) e.key: e.value,
    };
  }

  /// Recomputes texts that embed amounts, e.g. after a currency change.
  void refresh() => _changed();

  // ------------------------------------------------------------- queries --

  List<Expense> expensesIn(DateTime month, {String? categoryId, String? walletId}) => _expenses
      .where((e) =>
          sameMonth(e.date, month) &&
          (categoryId == null || e.categoryId == categoryId) &&
          (walletId == null || e.walletId == walletId))
      .toList();

  double spentIn(DateTime month, {String? categoryId, String? walletId}) =>
      expensesIn(month, categoryId: categoryId, walletId: walletId).fold(0.0, (s, e) => s + e.amount);

  /// Spending per category for a month, largest first, zero categories omitted.
  List<MapEntry<ExpenseCategory, double>> byCategory(DateTime month) {
    final totals = <String, double>{};
    for (final e in expensesIn(month)) {
      totals[e.categoryId] = (totals[e.categoryId] ?? 0) + e.amount;
    }
    // Refunds lower their category; one refunded beyond its spending is left out.
    final list = [
      for (final t in totals.entries)
        if (t.value > 0.005) MapEntry(ExpenseCategory.byId(t.key), t.value),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Totals for the last [count] months, oldest first, ending with [month].
  List<MapEntry<DateTime, double>> monthlyTotals(DateTime month, int count, {String? categoryId}) => [
        for (var i = count - 1; i >= 0; i--)
          MapEntry(addMonths(monthStart(month), -i), spentIn(addMonths(month, -i), categoryId: categoryId)),
      ];

  // ------------------------------------------------------------ expenses --

  /// Wallet of the last expense added, offered first for the next one.
  String? lastWalletId;

  Future<void> addExpense(Expense e) async {
    if (e.walletId == null) e = e.copyWith(walletId: defaultWallet.id);
    lastWalletId = e.walletId;
    final id = await _repo.insertExpense(e);
    _expenses = [e.copyWith(id: id), ..._expenses]..sort(_byDateDesc);
    _changed();
  }

  Future<void> updateExpense(Expense e) async {
    await _repo.updateExpense(e);
    _expenses = [for (final x in _expenses) x.id == e.id ? e : x]..sort(_byDateDesc);
    _changed();
  }

  Future<void> deleteExpense(Expense e) async {
    if (e.id == null) return;
    await _repo.deleteExpense(e.id!);
    _expenses = _expenses.where((x) => x.id != e.id).toList();
    _changed();
  }

  static int _byDateDesc(Expense a, Expense b) {
    final c = b.date.compareTo(a.date);
    if (c != 0) return c;
    // Same date: newest first. Local ids are numbers, cloud ids are random text.
    final ai = int.tryParse(a.id ?? ''), bi = int.tryParse(b.id ?? '');
    return ai != null && bi != null ? bi.compareTo(ai) : 0;
  }

  // ------------------------------------------------------------- budgets --

  Future<void> setBudget(String key, double amount) async {
    await _repo.setBudget(key, amount);
    final next = Map<String, double>.from(_budgets);
    if (amount <= 0) {
      next.remove(key);
    } else {
      next[key] = amount;
    }
    if (key != InsightsService.totalBudgetKey && !key.contains(':')) {
      await _put(next, _categoryHistKey(key, DateTime.now()), amount > 0 ? amount : _noBudget);
    }
    _budgets = next;
    _changed();
  }

  // -------------------------------------------------------------- budget --
  //
  // One monthly budget, decided automatically (income − savings) or typed in.
  // Every expense of the month counts against it, whatever the wallet;
  // transfers, withdrawals and corrections never do. What can be spent per
  // day is what is left divided by the days left. Part of the budget can be
  // reserved in wallets: their cards then show what is free and what is
  // reserved. At the end of a month, what is left goes back to the wallets
  // or into a savings goal.
  //
  // Everything is kept in the budget store (no schema change): `total` is
  // the budget in force, `cfg:` keys the preferences, `hist:YYYY-MM` the
  // budget each month had, `fund:<wallet>` the reservations.

  static const fundPrefix = 'fund:';
  static const closedPrefix = 'closed:';
  static const histPrefix = 'hist:';
  static const sinceKey = 'envelope:since';
  static const modeKey = 'cfg:mode';
  static const incomeKey = 'cfg:income';
  static const savingsPercentKey = 'cfg:savingsPct';
  static const savingsAmountKey = 'cfg:savingsAmt';
  static const manualKey = 'cfg:manual';
  static const incomeSourceKey = 'cfg:incomeSrc';
  static const categoryHistPrefix = 'histc:';

  /// Stands for "no budget" in a month snapshot: the store drops values <= 0.
  static const _noBudget = 0.0001;

  final Map<DateTime, EnvelopeMonth> _envelopeMonths = {};
  final Map<DateTime, BudgetStatus> _statuses = {};
  final Map<DateTime, Set<String>> _overBudget = {};

  BudgetConfig get budgetConfig {
    final mode = _budgets[modeKey];
    // Budgets set before modes existed were typed in: they stay manual.
    final legacy = mode == null && totalBudget > 0;
    final fromRecords = _budgets[incomeSourceKey] == 2;
    return BudgetConfig(
      mode: mode == 2 || legacy ? BudgetMode.manual : BudgetMode.automatic,
      incomeFromRecords: fromRecords,
      income: fromRecords ? recordedIncomeAverage : _budgets[incomeKey],
      savingsPercent: _budgets[savingsPercentKey],
      savingsAmount: _budgets[savingsAmountKey],
      manualBudget: _budgets[manualKey] ?? (legacy ? totalBudget : null),
    );
  }

  Future<void> _put(Map<String, double> next, String key, double? value) async {
    if (value == null || value <= 0) {
      if (next.containsKey(key)) await _repo.setBudget(key, 0);
      next.remove(key);
    } else {
      await _repo.setBudget(key, value);
      next[key] = value;
    }
  }

  /// Saves the budget preferences. The monthly budget becomes what they
  /// give (nothing when an automatic budget has no income). [funds] sets the
  /// reservation in each wallet; without it, existing reservations are kept,
  /// scaled down if they no longer fit in the budget.
  Future<void> setBudgetConfig(BudgetConfig c, {Map<String, double>? funds}) async {
    if (c.incomeFromRecords) {
      // The income is always the one actually recorded, whatever was passed.
      c = BudgetConfig(
        mode: c.mode,
        incomeFromRecords: true,
        income: recordedIncomeAverage,
        savingsPercent: c.savingsPercent,
        savingsAmount: c.savingsAmount,
        manualBudget: c.manualBudget,
      );
    }
    final next = Map<String, double>.from(_budgets);
    await _put(next, modeKey, c.mode == BudgetMode.manual ? 2 : 1);
    // The average of recorded income changes by itself: only a typed
    // income is stored.
    await _put(next, incomeSourceKey, c.incomeFromRecords ? 2 : null);
    if (!c.incomeFromRecords) await _put(next, incomeKey, c.income);
    await _put(next, savingsAmountKey, c.savingsAmount);
    await _put(next, savingsPercentKey, c.savingsAmount == null ? c.savingsPercent : null);
    await _put(next, manualKey, c.manualBudget);
    final budget = c.budget ?? 0;
    await _put(next, InsightsService.totalBudgetKey, budget);
    // The month's budget, for the reports of this month later on.
    await _put(next, _histKey(DateTime.now()), budget > 0 ? budget : _noBudget);
    if (budget > 0 && !next.containsKey(sinceKey)) {
      await _put(next, sinceKey, _monthNumber(DateTime.now()).toDouble());
    }

    var shares = funds ?? envelope.funds;
    final reserved = shares.values.fold(0.0, (s, v) => s + v);
    if (budget <= 0) {
      shares = const {};
    } else if (reserved > budget + 0.005) {
      shares = {for (final e in shares.entries) e.key: e.value * budget / reserved};
    }
    for (final key in next.keys.where((k) => k.startsWith(fundPrefix)).toList()) {
      if ((shares[key.substring(fundPrefix.length)] ?? 0) <= 0) await _put(next, key, null);
    }
    for (final e in shares.entries) {
      await _put(next, '$fundPrefix${e.key}', e.value);
    }
    _budgets = next;
    _changed();
  }

  /// Moves wallet reservations without touching the budget.
  Future<void> _setFunds(Map<String, double> funds) async {
    final next = Map<String, double>.from(_budgets);
    for (final key in next.keys.where((k) => k.startsWith(fundPrefix)).toList()) {
      if ((funds[key.substring(fundPrefix.length)] ?? 0) <= 0) await _put(next, key, null);
    }
    for (final e in funds.entries) {
      await _put(next, '$fundPrefix${e.key}', e.value);
    }
    _budgets = next;
    _changed();
  }

  static int _monthNumber(DateTime d) => d.year * 100 + d.month;
  static String _monthCode(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String _histKey(DateTime d) => '$histPrefix${_monthCode(d)}';
  static String _monthKey(DateTime d) => '$closedPrefix${_monthCode(d)}';

  /// Records the budget of the current month if it has not been yet, so
  /// that reports keep it once the month is over.
  Future<void> _snapshotBudget() async {
    final next = Map<String, double>.from(_budgets);
    // Before budgets were recorded month by month, one budget applied to
    // every month: it is recorded once from the first month with data, so
    // older reports keep the budget they were shown against.
    final first = _expenses.isEmpty
        ? monthStart(DateTime.now())
        : monthStart(_expenses.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b));
    if (totalBudget > 0 && !next.keys.any((k) => k.startsWith(histPrefix))) {
      await _put(next, _histKey(first), totalBudget);
    }
    for (final c in categoryBudgets.entries) {
      if (!next.keys.any((k) => k.startsWith('$categoryHistPrefix${c.key}@'))) {
        await _put(next, _categoryHistKey(c.key, first), c.value);
      }
    }
    final key = _histKey(DateTime.now());
    if (totalBudget > 0 && !next.containsKey(key)) await _put(next, key, totalBudget);
    _budgets = next;
  }

  static String _categoryHistKey(String categoryId, DateTime month) =>
      '$categoryHistPrefix$categoryId@${_monthCode(month)}';

  /// The latest value recorded under [prefix] (keys ending in YYYY-MM) at or
  /// before [month]; null if none.
  double? _recordedAt(String prefix, DateTime month) {
    final target = _monthNumber(month);
    int? best;
    double? value;
    for (final e in _budgets.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final parts = e.key.substring(prefix.length).split('-');
      if (parts.length != 2) continue;
      final n = int.parse(parts[0]) * 100 + int.parse(parts[1]);
      if (n <= target && (best == null || n > best)) {
        best = n;
        value = e.value;
      }
    }
    return value;
  }

  /// A category's budget in [month]: the current one for this month, the
  /// one in force at the time for a past month.
  double categoryBudgetFor(String categoryId, DateTime month) {
    final m = monthStart(month);
    if (!m.isBefore(monthStart(DateTime.now()))) return budgetFor(categoryId);
    final v = _recordedAt('$categoryHistPrefix$categoryId@', m) ?? 0;
    return v < 0.01 ? 0 : v;
  }

  /// Average monthly income actually recorded over the last three complete
  /// months that had income; null when none was recorded.
  double? get recordedIncomeAverage {
    final now = monthStart(DateTime.now());
    final totals = [
      for (var i = 1; i <= 3; i++) incomeInMonth(addMonths(now, -i)),
    ].where((v) => v > 0).toList();
    if (totals.isEmpty) return null;
    return totals.reduce((a, b) => a + b) / totals.length;
  }

  /// An automatic budget based on recorded income follows that income: it
  /// is worked out again when income is added, changed or removed.
  Future<void> _refreshRecordedBudget() async {
    final c = budgetConfig;
    if (c.mode != BudgetMode.automatic || !c.incomeFromRecords) return;
    if (((c.budget ?? 0) - totalBudget).abs() < 0.005) return;
    await setBudgetConfig(c);
  }

  /// The budget that applied to [month]: the current one for this month,
  /// the last recorded one for a past month (0 if none was recorded then).
  double monthlyBudgetFor(DateTime month) {
    final m = monthStart(month);
    if (!m.isBefore(monthStart(DateTime.now()))) return totalBudget;
    final v = _recordedAt(histPrefix, m) ?? 0;
    return v < 0.01 ? 0 : v;
  }

  /// [month]'s spending against its budget, on today's local date.
  BudgetStatus budgetStatus(DateTime month) {
    final m = monthStart(month);
    return _statuses[m] ??= BudgetMath.status(
      budget: monthlyBudgetFor(m),
      expenses: expensesIn(m),
      month: m,
      today: DateTime.now(),
    );
  }

  /// True for an expense that pushed its month past the budget.
  bool isOverBudget(Expense e) {
    if (e.id == null) return false;
    final m = monthStart(e.date);
    return (_overBudget[m] ??= BudgetMath.overBudgetIds(monthlyBudgetFor(m), expensesIn(m))).contains(e.id);
  }

  /// Category budgets (main currency), by category id.
  Map<String, double> get categoryBudgets => {
        for (final e in _budgets.entries)
          if (e.key != InsightsService.totalBudgetKey && !e.key.contains(':')) e.key: e.value,
      };

  /// What is left of the monthly budget for [categoryId] once the other
  /// categories have theirs.
  double unallocatedFor(String categoryId) =>
      BudgetMath.unallocated(totalBudget, categoryBudgets, except: categoryId);

  /// Money received in [month], all wallets, in the main currency. Transfers
  /// and balance corrections are not income.
  double incomeInMonth(DateTime month) {
    var total = 0.0;
    for (final d in _deposits) {
      if (d.kind != DepositKind.income || !sameMonth(d.date, month)) continue;
      if (!_wallets.any((w) => w.id == d.walletId)) continue;
      final w = walletById(d.walletId);
      total += w.isForeign(activeCurrency.code) ? d.amount * w.rate! : d.amount;
    }
    return total;
  }

  /// What all tracked wallets hold, in the main currency, and how many are
  /// tracked.
  ({double total, int tracked}) get totalBalance {
    var total = 0.0;
    var tracked = 0;
    for (final w in _wallets) {
      final b = balanceOf(w);
      if (b == null) continue;
      tracked++;
      total += w.isForeign(activeCurrency.code) ? b * w.rate! : b;
    }
    return (total: total, tracked: tracked);
  }

  MonthReport report(DateTime month) => MonthReport.build(
        month: month,
        expenses: expensesIn(month),
        income: incomeInMonth(month),
        budget: monthlyBudgetFor(month),
        today: DateTime.now(),
      );

  // Wallet reservations.

  Envelope get envelope => Envelope(
        total: totalBudget,
        funds: {
          for (final e in _budgets.entries)
            if (e.key.startsWith(fundPrefix) && _wallets.any((w) => '$fundPrefix${w.id}' == e.key))
              e.key.substring(fundPrefix.length): e.value,
        },
      );

  EnvelopeMonth envelopeIn(DateTime month) {
    final m = monthStart(month);
    return _envelopeMonths[m] ??= EnvelopeMath.compute(envelope, expensesIn(m));
  }

  /// What is still reserved for this month's budget in a wallet, in the
  /// wallet's currency. Zero when no reservation is set for it.
  double reservedIn(Wallet w) {
    final left = envelopeIn(DateTime.now()).leftByWallet[w.id] ?? 0;
    return w.isForeign(activeCurrency.code) ? left / w.rate! : left;
  }

  /// Balance minus what is reserved for the budget; null if not tracked.
  double? freeIn(Wallet w) {
    final b = balanceOf(w);
    return b == null ? null : b - reservedIn(w);
  }

  /// Last month's budget, if money was left in it and nobody has said yet
  /// where it goes.
  ({DateTime month, double left})? get monthToClose {
    final since = _budgets[sinceKey];
    if (since == null) return null;
    final last = addMonths(monthStart(DateTime.now()), -1);
    if (_monthNumber(last) < since || _budgets.containsKey(_monthKey(last))) return null;
    final left = budgetStatus(last).remaining;
    if (left < 1) return null;
    return (month: last, left: left);
  }

  /// Closes a month. Without [goal], what was left simply stops being
  /// reserved and is free in the wallets again. With [goal], it leaves the
  /// wallets that reserved it (or the main wallet) and is added to the goal.
  Future<void> closeMonth(DateTime month, {SavingsGoal? goal}) async {
    final left = budgetStatus(month).remaining;
    if (goal != null && left > 0) {
      var toTake = left;
      final shares = envelopeIn(month).leftByWallet;
      final sources = shares.isEmpty ? {mainWallet!.id: left} : shares;
      for (final share in sources.entries) {
        if (toTake < 0.005) break;
        if (share.value < 0.005 || !_wallets.any((w) => w.id == share.key)) continue;
        final w = walletById(share.key);
        if (balanceOf(w) == null) continue;
        final amount = share.value < toTake ? share.value : toTake;
        toTake -= amount;
        await saveDeposit(Deposit(
          id: newId('d'),
          walletId: w.id,
          amount: w.isForeign(activeCurrency.code) ? amount / w.rate! : amount,
          date: DateTime.now(),
          kind: DepositKind.withdrawal,
          note: tr('Vers l\'objectif « {0} »', [goal.name]),
        ));
      }
      await updateGoal(goal.copyWith(saved: goal.saved + left));
    }
    await _repo.setBudget(_monthKey(month), 1);
    _budgets = {..._budgets, _monthKey(month): 1};
    _changed();
  }

  // --------------------------------------------------------------- goals --

  Future<void> addGoal(SavingsGoal g) async {
    final id = await _repo.insertGoal(g);
    _goals = [..._goals, g.copyWith(id: id)];
    _changed();
  }

  Future<void> updateGoal(SavingsGoal g) async {
    await _repo.updateGoal(g);
    _goals = [for (final x in _goals) x.id == g.id ? g : x];
    _changed();
  }

  Future<void> deleteGoal(SavingsGoal g) async {
    if (g.id == null) return;
    await _repo.deleteGoal(g.id!);
    _goals = _goals.where((x) => x.id != g.id).toList();
    _changed();
  }

  /// Adds (or withdraws, if negative) money from a goal.
  Future<void> contribute(SavingsGoal g, double amount) =>
      updateGoal(g.copyWith(saved: (g.saved + amount).clamp(0.0, double.infinity)));

  // ------------------------------------------------------------- wallets --

  /// Creates or updates a wallet.
  Future<void> saveWallet(Wallet w) async {
    await _repo.saveWallet(w);
    final exists = _wallets.any((x) => x.id == w.id);
    _wallets = exists ? [for (final x in _wallets) x.id == w.id ? w : x] : [..._wallets, w];
    _changed();
  }

  /// Deletes a wallet (never the last one). What was left in it arrives in
  /// [moveTo], converted with the wallets' rates if their currencies differ;
  /// its expenses move there too, so totals and history keep them. The
  /// balances of the other wallets do not change.
  Future<void> deleteWallet(Wallet w, {required Wallet moveTo}) async {
    if (_wallets.length <= 1 || w.id == moveTo.id) return;
    final main = activeCurrency.code;
    double toMain(Wallet x, double v) => x.isForeign(main) ? v * x.rate! : v;
    double fromMain(Wallet x, double v) => x.isForeign(main) ? v / x.rate! : v;

    final left = balanceOf(w);
    final moved = _expenses.where((e) => e.walletId == w.id).toList();
    // The moved expenses were already paid from the deleted wallet: they
    // must not lower the receiving wallet's balance a second time.
    final targetStart = WalletMath.trackingStart(moveTo, _deposits) ?? DateTime.now();
    final alreadyPaid = moved
        .where((e) => !e.date.isBefore(targetStart))
        .fold(0.0, (s, e) => s + WalletMath.expenseIn(moveTo, e, main));
    await _repo.deleteWallet(w.id, moveTo: moveTo.id);

    final kept = <Deposit>[];
    for (final d in _deposits) {
      if (d.walletId == w.id) {
        // Money another wallet sent here stays gone from that wallet.
        if (d.sourceWalletId != null && _wallets.any((x) => x.id == d.sourceWalletId)) {
          final out = Deposit(
            id: d.id,
            walletId: d.sourceWalletId!,
            amount: d.sentAmount,
            date: d.date,
            kind: DepositKind.withdrawal,
            note: tr('Vers « {0} » (supprimé)', [w.name]),
          );
          await _repo.saveDeposit(out);
          kept.add(out);
        } else {
          await _repo.deleteDeposit(d.id);
        }
      } else if (d.sourceWalletId == w.id) {
        // Money it sent elsewhere stays in the wallet that received it.
        final received = Deposit(
          id: d.id,
          walletId: d.walletId,
          amount: d.amount,
          date: d.date,
          kind: DepositKind.transfer,
          note: d.note.isEmpty ? tr('Depuis « {0} » (supprimé)', [w.name]) : d.note,
        );
        await _repo.saveDeposit(received);
        kept.add(received);
      } else {
        kept.add(d);
      }
    }
    final arriving = (left == null ? 0.0 : fromMain(moveTo, toMain(w, left))) + alreadyPaid;
    if (arriving.abs() >= 0.005) {
      final carry = Deposit(
        id: newId('d'),
        walletId: moveTo.id,
        amount: arriving,
        date: DateTime.now(),
        kind: DepositKind.transfer,
        note: left == null ? tr('Dépenses de « {0} » déjà payées', [w.name]) : tr('Argent de « {0} » (supprimé)', [w.name]),
      );
      await _repo.saveDeposit(carry);
      kept.add(carry);
    }
    _deposits = kept..sort((a, b) => b.date.compareTo(a.date));
    final share = _budgets['$fundPrefix${w.id}'];
    if (share != null) {
      final funds = Map.of(envelope.funds)..remove(w.id);
      funds[moveTo.id] = (funds[moveTo.id] ?? 0) + share;
      await _setFunds(funds);
    }
    _wallets = _wallets.where((x) => x.id != w.id).toList();
    _expenses = [for (final e in _expenses) e.walletId == w.id ? e.copyWith(walletId: moveTo.id) : e];
    for (final debt in _debts.where((d) => d.entries.any((e) => e.walletId == w.id)).toList()) {
      final cleared = debt.copyWith(entries: [
        for (final e in debt.entries) e.walletId == w.id ? e.copyWith(clearWallet: true) : e,
      ]);
      await _repo.saveDebt(cleared);
      _debts = [for (final d in _debts) d.id == debt.id ? cleared : d];
    }
    _changed();
  }

  // ------------------------------------------------------------ deposits --

  /// Creates or updates money added to a wallet.
  Future<void> saveDeposit(Deposit d) async {
    await _repo.saveDeposit(d);
    _deposits = [d, ..._deposits.where((x) => x.id != d.id)]..sort((a, b) => b.date.compareTo(a.date));
    _changed();
    await _refreshRecordedBudget();
  }

  Future<void> deleteDeposit(Deposit d) async {
    await _repo.deleteDeposit(d.id);
    _deposits = _deposits.where((x) => x.id != d.id).toList();
    _changed();
    await _refreshRecordedBudget();
  }

  /// Records what the person really has in a wallet now. The first time,
  /// this starts balance tracking; afterwards it adds a correction.
  Future<void> setBalance(Wallet w, double real) async {
    final current = balanceOf(w);
    final diff = real - (current ?? 0);
    if (current != null && diff.abs() < 0.005) return;
    await saveDeposit(Deposit(
      id: newId('d'),
      walletId: w.id,
      amount: diff,
      date: DateTime.now(),
      kind: DepositKind.adjustment,
      note: current == null ? tr('Solde de départ') : tr('Correction du solde'),
    ));
  }

  // --------------------------------------------------------------- debts --

  /// Money lent and borrowed, oldest first.
  List<Debt> get debts => _debts;

  /// What people still owe me, in the main currency.
  double get owedToMe => _debts.where((d) => d.isLent).fold(0.0, (s, d) => s + d.remaining);

  /// What I still owe.
  double get owedByMe => _debts.where((d) => !d.isLent).fold(0.0, (s, d) => s + d.remaining);

  /// The debt a wallet movement belongs to, if any.
  Debt? debtOfDeposit(Deposit d) {
    if (d.kind != DepositKind.debt) return null;
    return _debts.where((x) => x.entries.any((e) => e.id == d.id)).firstOrNull;
  }

  /// Wallets a debt can move money in and out of: active ones in the main
  /// currency (debts are counted in the main currency).
  List<Wallet> get debtWallets =>
      activeWallets.where((w) => !w.isForeign(activeCurrency.code)).toList();

  /// People already met, most recent first, to suggest them again.
  List<String> get debtPeople {
    final seen = <String>{};
    final sorted = [..._debts]..sort((a, b) => b.date.compareTo(a.date));
    return [for (final d in sorted) if (seen.add(d.person.trim().toLowerCase())) d.person.trim()];
  }

  /// Creates or updates a debt, and makes the wallets match its history:
  /// each entry paid through a wallet has a deposit with the entry's id.
  Future<void> saveDebt(Debt debt) async {
    final previous = _debts.where((d) => d.id == debt.id).firstOrNull;
    await _repo.saveDebt(debt);
    _debts = previous == null ? [..._debts, debt] : [for (final d in _debts) d.id == debt.id ? debt : d];

    final wanted = <String, Deposit>{
      for (final e in debt.entries)
        if (e.walletId != null && _wallets.any((w) => w.id == e.walletId))
          e.id: Deposit(
            id: e.id,
            walletId: e.walletId!,
            amount: debt.walletEffect(e),
            date: e.date,
            kind: DepositKind.debt,
            note: debtEntryLabel(debt, e),
          ),
    };
    final stale = {...?previous?.entries.map((e) => e.id), ...debt.entries.map((e) => e.id)}
      ..removeAll(wanted.keys);
    var deposits = _deposits;
    for (final id in stale) {
      if (deposits.any((d) => d.id == id)) {
        await _repo.deleteDeposit(id);
        deposits = deposits.where((d) => d.id != id).toList();
      }
    }
    for (final d in wanted.values) {
      await _repo.saveDeposit(d);
      deposits = [d, ...deposits.where((x) => x.id != d.id)];
    }
    _deposits = deposits..sort((a, b) => b.date.compareTo(a.date));
    _changed();
  }

  /// Records a repayment, or more money lent or borrowed.
  Future<void> addDebtEntry(Debt debt, DebtEntry entry) =>
      saveDebt(debt.copyWith(entries: [...debt.entries, entry]));

  /// Removes a repayment or an addition; its wallet movement goes with it.
  Future<void> removeDebtEntry(Debt debt, DebtEntry entry) =>
      saveDebt(debt.copyWith(entries: debt.entries.where((e) => e.id != entry.id).toList()));

  /// Deletes a debt and the wallet movements it made.
  Future<void> deleteDebt(Debt debt) async {
    await _repo.deleteDebt(debt.id);
    final ids = debt.entries.map((e) => e.id).toSet();
    for (final d in _deposits.where((d) => ids.contains(d.id)).toList()) {
      await _repo.deleteDeposit(d.id);
    }
    _deposits = _deposits.where((d) => !ids.contains(d.id)).toList();
    _debts = _debts.where((d) => d.id != debt.id).toList();
    _changed();
  }

  // ---------------------------------------------------------- categories --

  /// Creates or updates a custom category.
  Future<void> saveCategory(ExpenseCategory c) async {
    await _repo.saveCategory(c);
    final list = ExpenseCategory.customList;
    final exists = list.any((x) => x.id == c.id);
    ExpenseCategory.customList = exists ? [for (final x in list) x.id == c.id ? c : x] : [...list, c];
    _changed();
  }

  /// Its expenses move to "Autre" and its budget is removed.
  Future<void> deleteCategory(ExpenseCategory c) async {
    await _repo.deleteCategory(c.id);
    ExpenseCategory.customList = ExpenseCategory.customList.where((x) => x.id != c.id).toList();
    _expenses = [
      for (final e in _expenses) e.categoryId == c.id ? e.copyWith(categoryId: ExpenseCategory.otherId) : e,
    ];
    _budgets = Map.of(_budgets)..remove(c.id);
    _changed();
  }

  // ---------------------------------------------------------------- data --

  Future<void> loadDemoData() async {
    final demo = DemoData.generate(DateTime.now());
    await _repo.replaceAll(
        expenses: demo.expenses,
        budgets: demo.budgets,
        goals: demo.goals,
        wallets: demo.wallets,
        categories: const [],
        deposits: demo.deposits);
    await load();
  }

  Future<void> resetAll() async {
    await _repo.replaceAll(
        expenses: const [],
        budgets: const {},
        goals: const [],
        wallets: [_wallets.first],
        categories: const [],
        deposits: const []);
    await load();
  }
}

/// How an entry of [debt] reads, e.g. "Prêt à Karim" or "Remboursement de
/// Karim".
String debtEntryLabel(Debt debt, DebtEntry e) {
  final name = debt.person;
  return switch ((debt.direction, e.kind)) {
    (DebtDirection.lent, DebtEntryKind.start) => tr('Prêt à {0}', [name]),
    (DebtDirection.lent, DebtEntryKind.more) => tr('Nouveau prêt à {0}', [name]),
    (DebtDirection.lent, DebtEntryKind.repayment) => tr('Remboursement de {0}', [name]),
    (DebtDirection.borrowed, DebtEntryKind.start) => tr('Emprunt à {0}', [name]),
    (DebtDirection.borrowed, DebtEntryKind.more) => tr('Nouvel emprunt à {0}', [name]),
    (DebtDirection.borrowed, DebtEntryKind.repayment) => tr('Remboursé à {0}', [name]),
  };
}
