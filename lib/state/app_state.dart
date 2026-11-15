import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/demo_data.dart';
import '../data/repository.dart';
import '../models/category.dart';
import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/insight.dart';
import '../models/plan.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';
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
    _loaded = true;
    _changed();
  }

  void _changed() {
    _insights = null;
    _envelopeMonths.clear();
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
    final list = [for (final t in totals.entries) MapEntry(ExpenseCategory.byId(t.key), t.value)]
      ..sort((a, b) => b.value.compareTo(a.value));
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
    _budgets = next;
    _changed();
  }

  // ------------------------------------------------------------ envelope --
  //
  // The global budget is an envelope: money reserved in wallets for the
  // month's spending. Balances stay what is really in the wallets; the part
  // still reserved is shown apart from what is free. Each expense uses up the
  // share of the wallet that paid it; beyond it, the expense is outside the
  // budget. At the end of a month, what is left goes back to the wallets or
  // into a savings goal.

  static const fundPrefix = 'fund:';
  static const closedPrefix = 'closed:';
  static const sinceKey = 'envelope:since';

  final Map<DateTime, EnvelopeMonth> _envelopeMonths = {};

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
  /// wallet's currency. Zero when the envelope is shared or not funded by it.
  double reservedIn(Wallet w) {
    final left = envelopeIn(DateTime.now()).leftByWallet[w.id] ?? 0;
    return w.isForeign(activeCurrency.code) ? left / w.rate! : left;
  }

  /// Balance minus what is reserved for the budget; null if not tracked.
  double? freeIn(Wallet w) {
    final b = balanceOf(w);
    return b == null ? null : b - reservedIn(w);
  }

  bool isOutsideBudget(Expense e) => e.id != null && envelopeIn(e.date).outsideExpenseIds.contains(e.id);

  /// Sets the envelope from each wallet's share (main currency). The global
  /// budget becomes their sum; empty removes the budget.
  Future<void> setEnvelope(Map<String, double> funds) async {
    final next = Map<String, double>.from(_budgets);
    for (final key in _budgets.keys.where((k) => k.startsWith(fundPrefix))) {
      final id = key.substring(fundPrefix.length);
      if ((funds[id] ?? 0) <= 0) {
        await _repo.setBudget(key, 0);
        next.remove(key);
      }
    }
    var total = 0.0;
    for (final f in funds.entries) {
      if (f.value <= 0) continue;
      total += f.value;
      await _repo.setBudget('$fundPrefix${f.key}', f.value);
      next['$fundPrefix${f.key}'] = f.value;
    }
    await _repo.setBudget(InsightsService.totalBudgetKey, total);
    if (total > 0) {
      next[InsightsService.totalBudgetKey] = total;
    } else {
      next.remove(InsightsService.totalBudgetKey);
    }
    // Months before the envelope existed are never asked about.
    if (total > 0 && !next.containsKey(sinceKey)) {
      final since = _monthNumber(DateTime.now()).toDouble();
      await _repo.setBudget(sinceKey, since);
      next[sinceKey] = since;
    }
    _budgets = next;
    _changed();
  }

  static int _monthNumber(DateTime d) => d.year * 100 + d.month;
  static String _monthKey(DateTime d) => '$closedPrefix${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Last month's envelope, if money was left in it and nobody has said
  /// yet where it goes.
  ({DateTime month, double left, Map<String, double> byWallet})? get monthToClose {
    final env = envelope;
    final since = _budgets[sinceKey];
    if (env.isEmpty || env.shared || since == null) return null;
    final last = addMonths(monthStart(DateTime.now()), -1);
    if (_monthNumber(last) < since || _budgets.containsKey(_monthKey(last))) return null;
    final m = envelopeIn(last);
    if (m.left < 1) return null;
    return (month: last, left: m.left, byWallet: m.leftByWallet);
  }

  /// Closes a month's envelope. Without [goal], what was left simply stops
  /// being reserved and is free in the wallets again. With [goal], it leaves
  /// the wallets (as a withdrawal) and is added to the goal.
  Future<void> closeMonth(DateTime month, {SavingsGoal? goal}) async {
    final m = envelopeIn(month);
    if (goal != null && m.left > 0) {
      for (final share in m.leftByWallet.entries) {
        if (share.value < 0.005 || !_wallets.any((w) => w.id == share.key)) continue;
        final w = walletById(share.key);
        if (balanceOf(w) == null) continue;
        await saveDeposit(Deposit(
          id: newId('d'),
          walletId: w.id,
          amount: w.isForeign(activeCurrency.code) ? share.value / w.rate! : share.value,
          date: DateTime.now(),
          kind: DepositKind.withdrawal,
          note: tr('Vers l\'objectif « {0} »', [goal.name]),
        ));
      }
      await updateGoal(goal.copyWith(saved: goal.saved + m.left));
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
      await setEnvelope(funds);
    }
    _wallets = _wallets.where((x) => x.id != w.id).toList();
    _expenses = [for (final e in _expenses) e.walletId == w.id ? e.copyWith(walletId: moveTo.id) : e];
    _changed();
  }

  // ------------------------------------------------------------ deposits --

  /// Creates or updates money added to a wallet.
  Future<void> saveDeposit(Deposit d) async {
    await _repo.saveDeposit(d);
    _deposits = [d, ..._deposits.where((x) => x.id != d.id)]..sort((a, b) => b.date.compareTo(a.date));
    _changed();
  }

  Future<void> deleteDeposit(Deposit d) async {
    await _repo.deleteDeposit(d.id);
    _deposits = _deposits.where((x) => x.id != d.id).toList();
    _changed();
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
