import '../models/expense.dart';

/// How the monthly budget is decided.
enum BudgetMode { automatic, manual }

/// The person's budget preferences. Amounts are in the main currency.
///
/// Automatic: budget = monthly income − savings (an amount, or a share of
/// the income). Manual: the budget is typed in. Nothing is ever guessed: an
/// automatic budget without an income has no amount.
class BudgetConfig {
  const BudgetConfig({
    this.mode = BudgetMode.automatic,
    this.income,
    this.savingsPercent,
    this.savingsAmount,
    this.manualBudget,
    this.incomeFromRecords = false,
  });

  final BudgetMode mode;

  /// True when the income is the average actually recorded over the last
  /// complete months rather than an amount typed in.
  final bool incomeFromRecords;

  /// Monthly income: typed in, or recorded (see [incomeFromRecords]); null
  /// until there is one.
  final double? income;

  /// Savings as a share of income (0–100), or as a fixed amount. At most one
  /// of the two is used; the amount wins when both are set.
  final double? savingsPercent;
  final double? savingsAmount;

  final double? manualBudget;

  /// What to put aside each month, or null without an income.
  double? get savings {
    final i = income;
    if (i == null || i <= 0) return null;
    if (savingsAmount != null) return savingsAmount!.clamp(0, i).toDouble();
    return (i * (savingsPercent ?? 0) / 100).clamp(0, i).toDouble();
  }

  /// The monthly budget this configuration gives, or null when it cannot be
  /// worked out (automatic without income, manual without amount).
  double? get budget => switch (mode) {
    BudgetMode.automatic => income == null || income! <= 0 ? null : income! - savings!,
    BudgetMode.manual => manualBudget == null || manualBudget! <= 0 ? null : manualBudget,
  };
}

/// Where a month stands against its budget.
enum BudgetLevel { none, within, approaching, exceeded }

/// A month's spending against its budget, as shown everywhere in the app.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.spent,
    required this.daysInMonth,
    required this.daysLeft,
    required this.spentToday,
  });

  /// 0 when no budget applies to the month.
  final double budget;
  final double spent;
  final int daysInMonth;

  /// Days left in the month, today included; 0 for a month that is over.
  final int daysLeft;
  final double spentToday;

  /// Share of the budget at which the month is "approaching" the limit.
  static const warningRatio = 0.8;

  bool get hasBudget => budget > 0;

  /// What is left; never negative (see [overspent]).
  double get remaining => (budget - spent).clamp(0, double.infinity).toDouble();

  /// Spending beyond the budget, shown apart from what is left.
  double get overspent => (spent - budget).clamp(0, double.infinity).toDouble();

  double get ratio => hasBudget ? spent / budget : 0;

  BudgetLevel get level {
    if (!hasBudget) return BudgetLevel.none;
    if (spent > budget + 0.005) return BudgetLevel.exceeded;
    if (ratio >= warningRatio) return BudgetLevel.approaching;
    return BudgetLevel.within;
  }

  /// What can be spent per day for the rest of the month: what is left
  /// divided by the days left, today included. Spending less than this
  /// raises it for the following days, spending more lowers it. Zero once
  /// the budget is used up or the month is over.
  double get dailyAllowance => !hasBudget || daysLeft <= 0 ? 0 : remaining / daysLeft;
}

/// Budget arithmetic, kept pure so it can be tested on its own.
class BudgetMath {
  /// Status of the month containing [month], on [today] (local date).
  /// [expenses] may hold any dates: only that month's count.
  static BudgetStatus status({required double budget, required List<Expense> expenses, required DateTime month, required DateTime today}) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    var spent = 0.0, spentToday = 0.0;
    for (final e in expenses) {
      if (e.date.year != first.year || e.date.month != first.month) continue;
      spent += e.amount;
      if (e.date.day == today.day && e.date.month == today.month && e.date.year == today.year) {
        spentToday += e.amount;
      }
    }
    final int daysLeft;
    if (today.year == first.year && today.month == first.month) {
      daysLeft = days - today.day + 1;
    } else if (today.isBefore(first)) {
      daysLeft = days;
    } else {
      daysLeft = 0;
    }
    return BudgetStatus(budget: budget, spent: spent, daysInMonth: days, daysLeft: daysLeft, spentToday: spentToday);
  }

  /// Ids of the month's expenses that pushed spending past [budget], in the
  /// order they were spent.
  static Set<String> overBudgetIds(double budget, List<Expense> monthExpenses) {
    if (budget <= 0) return const {};
    final ordered = [...monthExpenses]
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        final ai = int.tryParse(a.id ?? ''), bi = int.tryParse(b.id ?? '');
        return ai != null && bi != null ? ai.compareTo(bi) : 0;
      });
    var total = 0.0;
    final ids = <String>{};
    for (final e in ordered) {
      total += e.amount;
      // A refund lowers the total but is never itself over the budget.
      if (e.amount > 0 && total > budget + 0.005 && e.id != null) ids.add(e.id!);
    }
    return ids;
  }

  /// How much of [budget] is still free to give to [categoryId], given the
  /// other categories' budgets. Category budgets split the monthly budget;
  /// they never add to it.
  static double unallocated(double budget, Map<String, double> categoryBudgets, {String? except}) {
    var used = 0.0;
    for (final e in categoryBudgets.entries) {
      if (e.key != except) used += e.value;
    }
    return (budget - used).clamp(0, double.infinity).toDouble();
  }
}

/// A month's figures for the reports screen.
class MonthReport {
  const MonthReport({
    required this.month,
    required this.expenses,
    required this.income,
    required this.count,
    required this.daysCounted,
    required this.budget,
    this.topCategoryId,
    this.topCategoryAmount = 0,
    this.biggest,
  });

  final DateTime month;
  final double expenses;
  final double income;
  final int count;

  /// Days the daily average is taken over: the whole month once it is over,
  /// the days so far for the current month.
  final int daysCounted;

  /// The budget that applied that month (0 if none was set).
  final double budget;
  final String? topCategoryId;
  final double topCategoryAmount;
  final Expense? biggest;

  double get net => income - expenses;
  double get averagePerDay => daysCounted <= 0 ? 0 : expenses / daysCounted;
  double? get budgetUsage => budget > 0 ? expenses / budget : null;

  /// Change from [previous] as a ratio (0.12 = +12 %), or null when the
  /// previous value is zero.
  static double? change(double current, double previous) => previous.abs() < 0.005 ? null : current / previous - 1;

  static MonthReport build({
    required DateTime month,
    required List<Expense> expenses,
    required double income,
    required double budget,
    required DateTime today,
  }) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final items = expenses.where((e) => e.date.year == first.year && e.date.month == first.month).toList();
    var total = 0.0;
    final byCategory = <String, double>{};
    Expense? biggest;
    var count = 0;
    for (final e in items) {
      total += e.amount;
      byCategory[e.categoryId] = (byCategory[e.categoryId] ?? 0) + e.amount;
      // Refunds lower the totals but are not expenses of their own.
      if (e.amount <= 0) continue;
      count++;
      if (biggest == null || e.amount > biggest.amount) biggest = e;
    }
    String? top;
    var topAmount = 0.0;
    for (final c in byCategory.entries) {
      if (c.value > topAmount) {
        top = c.key;
        topAmount = c.value;
      }
    }
    final current = today.year == first.year && today.month == first.month;
    final future = today.isBefore(first);
    return MonthReport(
      month: first,
      expenses: total,
      income: income,
      count: count,
      daysCounted: future ? 0 : (current ? today.day : days),
      budget: budget,
      topCategoryId: top,
      topCategoryAmount: topAmount,
      biggest: biggest,
    );
  }
}
