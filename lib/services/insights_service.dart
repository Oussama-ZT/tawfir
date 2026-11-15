import 'dart:math' as math;

import '../models/category.dart';
import '../models/expense.dart';
import '../models/insight.dart';
import '../models/savings_goal.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../l10n/l10n.dart';

/// EcoBudget's "smart" layer: turns raw expenses, budgets and goals into short,
/// plain-language insights. Everything runs on the device, no network needed.
///
/// Detection rules:
/// 1. Unusual expense: a recent expense far above what the user usually spends
///    in that category (median + 3 robust deviations, and at least 2x the median).
/// 2. Budget pace: projects month-end spending from the current daily pace and
///    warns before the budget is exceeded, with a "max per day" to stay on track.
/// 3. Category trend: this month's spending in a category already exceeds the
///    average of previous months by 30 %+ (or is clearly lower: positive feedback).
/// 4. Goal advice: monthly amount needed to reach each savings goal on time.
/// 5. Concentration: one variable category takes a large share of spending.
class InsightsService {
  static const String totalBudgetKey = 'total';

  /// Categories considered fixed costs: not flagged for concentration tips.
  static const Set<String> fixedCategories = {'housing', 'bills'};

  static List<Insight> generate({
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required DateTime now,
  }) {
    final past = expenses.where((e) => !e.date.isAfter(now)).toList();
    final insights = <Insight>[
      ..._budgetPace(past, budgets, now),
      ..._unusualExpenses(past, now),
      ..._categoryTrends(past, now),
      ..._goalAdvice(goals, now),
      ..._concentration(past, now),
      ..._budgetSuggestion(past, budgets, now),
    ];
    // Stable sort by priority, keeping rule order for ties.
    final indexed = insights.asMap().entries.toList()
      ..sort((a, b) {
        final p = a.value.priority.compareTo(b.value.priority);
        return p != 0 ? p : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  // ---------------------------------------------------------------- rule 1 --

  static List<Insight> _unusualExpenses(List<Expense> expenses, DateTime now) {
    final recentLimit = now.subtract(const Duration(days: 30));
    final found = <({Expense expense, double ratio, double usual})>[];

    for (final e in expenses) {
      if (e.date.isBefore(recentLimit)) continue;
      final result = checkUnusual(e, expenses);
      if (result != null) found.add((expense: e, ratio: result.ratio, usual: result.usual));
    }

    found.sort((a, b) => b.ratio.compareTo(a.ratio));
    return [
      for (final f in found.take(3))
        Insight(
          kind: InsightKind.anomaly,
          categoryId: f.expense.categoryId,
          title: tr('Dépense inhabituelle : {0}', [ExpenseCategory.byId(f.expense.categoryId).label]),
          message: tr('{0} le {1}{2}, soit environ {3}× votre dépense habituelle ({4}).', [money(f.expense.amount), shortDate(f.expense.date), f.expense.note.isEmpty ? '' : ' (${f.expense.note})', decimal1(f.ratio), moneyApprox(f.usual)]),
        ),
    ];
  }

  // ---------------------------------------------------------------- rule 2 --

  static List<Insight> _budgetPace(List<Expense> expenses, Map<String, double> budgets, DateTime now) {
    final out = <Insight>[];
    final month = expenses.where((e) => sameMonth(e.date, now)).toList();
    final day = now.day;
    final dim = daysInMonth(now);
    final daysLeft = dim - day + 1; // today included

    final total = budgets[totalBudgetKey] ?? 0;
    if (total > 0) {
      final spent = _sum(month);
      // Fixed costs (rent, bills) are paid once a month, so only variable
      // spending is extrapolated from the daily pace.
      final fixed = _sum(month.where((e) => fixedCategories.contains(e.categoryId)));
      final projected = fixed + (spent - fixed) / day * dim;
      if (spent > total) {
        out.add(Insight(
          kind: InsightKind.danger,
          title: tr('Budget mensuel dépassé'),
          message: tr('Vous avez dépensé {0} pour un budget de {1} (+{2}).', [money(spent), money(total), money(spent - total)]),
        ));
      } else if (day >= 5 && daysLeft > 0 && projected > total * 1.05) {
        out.add(Insight(
          kind: InsightKind.warning,
          title: tr('Risque de dépassement du budget'),
          message: tr('À ce rythme, vous finirez le mois vers {0} (budget : {1}). Limitez-vous à {2} par jour pendant les {3} jours restants.', [moneyApprox(projected), money(total), moneyApprox((total - spent) / daysLeft), daysLeft]),
        ));
      } else if (day >= 20 && projected <= total * 0.9) {
        out.add(Insight(
          kind: InsightKind.success,
          title: tr('Vous êtes sur la bonne voie'),
          message: tr('Au rythme actuel, vous devriez économiser environ {0} ce mois-ci.', [moneyApprox(total - projected)]),
        ));
      }
    }

    for (final cat in ExpenseCategory.visible) {
      final budget = budgets[cat.id] ?? 0;
      if (budget <= 0) continue;
      final spent = _sum(month.where((e) => e.categoryId == cat.id));
      if (spent > budget) {
        out.add(Insight(
          kind: InsightKind.danger,
          categoryId: cat.id,
          title: tr('Budget {0} dépassé', [cat.label]),
          message: tr('{0} dépensés pour un budget de {1} (+{2}).', [money(spent), money(budget), money(spent - budget)]),
        ));
      } else if (spent >= budget * 0.8) {
        out.add(Insight(
          kind: InsightKind.warning,
          categoryId: cat.id,
          title: tr('Budget {0} presque atteint', [cat.label]),
          message: tr('Vous avez utilisé {0} du budget. Il reste {1} pour {2} jours.', [percent(spent / budget), money(budget - spent), daysLeft]),
        ));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- rule 3 --

  static List<Insight> _categoryTrends(List<Expense> expenses, DateTime now) {
    final out = <Insight>[];
    final start = monthStart(now);
    final previousMonths = [for (var i = 1; i <= 3; i++) addMonths(start, -i)]
        .where((m) => expenses.any((e) => sameMonth(e.date, m)))
        .toList();
    if (previousMonths.length < 2) return out;

    final current = expenses.where((e) => sameMonth(e.date, now)).toList();
    for (final cat in ExpenseCategory.visible) {
      final totals = [
        for (final m in previousMonths)
          _sum(expenses.where((e) => e.categoryId == cat.id && sameMonth(e.date, m))),
      ];
      final avg = totals.reduce((a, b) => a + b) / totals.length;
      if (avg <= 0) continue;
      final spent = _sum(current.where((e) => e.categoryId == cat.id));

      if (spent > avg * 1.3 && spent - avg >= 50) {
        out.add(Insight(
          kind: InsightKind.anomaly,
          categoryId: cat.id,
          title: tr('Hausse inhabituelle : {0}', [cat.label]),
          message: tr('Déjà {0} ce mois-ci, soit +{1} par rapport à votre moyenne mensuelle ({2}).', [money(spent), percent(spent / avg - 1), moneyApprox(avg)]),
        ));
      } else if (now.day >= 25 && spent < avg * 0.8 && avg - spent >= 50) {
        out.add(Insight(
          kind: InsightKind.success,
          categoryId: cat.id,
          title: tr('Bravo : {0} en baisse', [cat.label]),
          message: tr('{0} ce mois-ci contre {1} en moyenne (−{2}).', [money(spent), moneyApprox(avg), percent(1 - spent / avg)]),
        ));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- rule 4 --

  static List<Insight> _goalAdvice(List<SavingsGoal> goals, DateTime now) {
    final out = <Insight>[];
    for (final g in goals) {
      if (g.isReached) {
        out.add(Insight(
          kind: InsightKind.success,
          title: tr('Objectif « {0} » atteint', [g.name]),
          message: tr('Félicitations, vous avez épargné {0} !', [money(g.saved)]),
        ));
        continue;
      }
      final deadline = g.deadline;
      if (deadline == null) continue;

      if (deadline.isBefore(now)) {
        out.add(Insight(
          kind: InsightKind.danger,
          title: tr('Objectif « {0} » en retard', [g.name]),
          message: tr('L\'échéance est passée et il manque encore {0}. Pensez à fixer une nouvelle date.', [money(g.remaining)]),
        ));
        continue;
      }

      final monthsLeft = math.max(1, (deadline.difference(now).inDays / 30.44).ceil());
      final perMonth = g.remaining / monthsLeft;
      final totalDays = deadline.difference(g.createdAt).inDays;
      final elapsed = now.difference(g.createdAt).inDays;
      final expected = totalDays <= 0 ? 1.0 : (elapsed / totalDays).clamp(0.0, 1.0);
      final behind = g.progress < expected - 0.15;

      out.add(Insight(
        kind: behind ? InsightKind.warning : InsightKind.tip,
        title: behind ? tr('En retard sur « {0} »', [g.name]) : tr('Objectif « {0} »', [g.name]),
        message: tr('Épargnez {0} par mois pour atteindre {1} d\'ici {2}.', [moneyApprox(perMonth), money(g.target), monthYear(deadline).toLowerCase()]),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------- rule 5 --

  static List<Insight> _concentration(List<Expense> expenses, DateTime now) {
    final month = expenses.where((e) => sameMonth(e.date, now)).toList();
    if (month.length < 5) return const [];
    final total = _sum(month);
    if (total <= 0) return const [];

    ExpenseCategory? top;
    var topSpent = 0.0;
    for (final cat in ExpenseCategory.visible) {
      if (fixedCategories.contains(cat.id)) continue;
      final s = _sum(month.where((e) => e.categoryId == cat.id));
      if (s > topSpent) {
        topSpent = s;
        top = cat;
      }
    }
    if (top == null || topSpent / total < 0.35) return const [];
    return [
      Insight(
        kind: InsightKind.tip,
        categoryId: top.id,
        title: tr('{0} : {1} de vos dépenses', [top.label, percent(topSpent / total)]),
        message: tr('C\'est votre premier poste variable ce mois-ci. Le réduire de 10 % vous ferait économiser environ {0} par mois.', [moneyApprox(topSpent * 0.1)]),
      ),
    ];
  }

  // ---------------------------------------------------------------- rule 6 --

  static List<Insight> _budgetSuggestion(List<Expense> expenses, Map<String, double> budgets, DateTime now) {
    if ((budgets[totalBudgetKey] ?? 0) > 0) return const [];
    final start = monthStart(now);
    final totals = [
      for (var i = 1; i <= 3; i++) _sum(expenses.where((e) => sameMonth(e.date, addMonths(start, -i)))),
    ].where((t) => t > 0).toList();
    if (totals.isEmpty) {
      return [
        Insight(
          kind: InsightKind.tip,
          title: tr('Définissez un budget mensuel'),
          message: tr('Fixer un budget permet à EcoBudget de vous alerter avant un dépassement.'),
        ),
      ];
    }
    final avg = totals.reduce((a, b) => a + b) / totals.length;
    final suggested = (avg * 0.95 / 100).round() * 100.0;
    return [
      Insight(
        kind: InsightKind.tip,
        title: tr('Définissez un budget mensuel'),
        message: tr('D\'après vos derniers mois ({0} en moyenne), un budget d\'environ {1} serait réaliste et vous ferait épargner un peu.', [moneyApprox(avg), money(suggested)]),
      ),
    ];
  }

  /// Up to [count] insights for a compact view: the most important insight of
  /// each kind first (so an anomaly is not hidden behind several alerts),
  /// then the rest in priority order.
  static List<Insight> highlights(List<Insight> sorted, {int count = 3}) {
    final picked = <Insight>[];
    final seen = <InsightKind>{};
    for (final i in sorted) {
      if (picked.length == count) break;
      if (seen.add(i.kind)) picked.add(i);
    }
    for (final i in sorted) {
      if (picked.length == count) break;
      if (!picked.contains(i)) picked.add(i);
    }
    return picked..sort((a, b) => a.priority.compareTo(b.priority));
  }

  // --------------------------------------------------------------- helpers --

  /// Returns how unusual [e] is compared with earlier expenses of the same
  /// category, or null if it looks normal (or there is not enough history).
  ///
  /// Uses the median and the median absolute deviation (MAD), which are not
  /// distorted by a few past outliers the way a mean / standard deviation are.
  static ({double ratio, double usual})? checkUnusual(Expense e, List<Expense> all) {
    final history = all
        .where((h) => h.categoryId == e.categoryId && h.date.isBefore(e.date))
        .map((h) => h.amount)
        .toList();
    if (history.length < 5) return null;

    final med = median(history);
    if (med <= 0) return null;
    final mad = median(history.map((x) => (x - med).abs()).toList());
    // 1.4826 * MAD approximates the standard deviation; floor it so a very
    // regular history (MAD = 0) does not flag tiny variations.
    final spread = math.max(1.4826 * mad, 0.15 * med);
    if (e.amount > med + 3 * spread && e.amount >= 2 * med) {
      return (ratio: e.amount / med, usual: med);
    }
    return null;
  }

  static double _sum(Iterable<Expense> list) => list.fold(0.0, (s, e) => s + e.amount);

  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    final s = [...values]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }
}
