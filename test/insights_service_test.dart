import 'package:eco_budget/data/demo_data.dart';
import 'package:eco_budget/models/expense.dart';
import 'package:eco_budget/models/insight.dart';
import 'package:eco_budget/models/savings_goal.dart';
import 'package:eco_budget/services/insights_service.dart';
import 'package:eco_budget/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  final now = DateTime(2026, 11, 15, 18);
  Expense exp(double amount, String cat, DateTime date, [String note = '']) =>
      Expense(amount: amount, categoryId: cat, date: date, note: note);

  List<Insight> run({
    List<Expense> expenses = const [],
    Map<String, double> budgets = const {InsightsService.totalBudgetKey: 100000},
    List<SavingsGoal> goals = const [],
  }) =>
      InsightsService.generate(expenses: expenses, budgets: budgets, goals: goals, now: now);

  group('median', () {
    test('odd and even lengths', () {
      expect(InsightsService.median([3, 1, 2]), 2);
      expect(InsightsService.median([4, 1, 3, 2]), 2.5);
      expect(InsightsService.median([]), 0);
    });
  });

  group('checkUnusual', () {
    final history = [
      for (var i = 0; i < 8; i++) exp(180.0 + i * 15, 'shopping', DateTime(2026, 9, 1 + i * 3)),
    ];

    test('flags an expense far above the usual amount', () {
      final big = exp(2400, 'shopping', DateTime(2026, 11, 3));
      final result = InsightsService.checkUnusual(big, [...history, big]);
      expect(result, isNotNull);
      expect(result!.ratio, greaterThan(9));
    });

    test('ignores a normal expense', () {
      final normal = exp(260, 'shopping', DateTime(2026, 11, 3));
      expect(InsightsService.checkUnusual(normal, history), isNull);
    });

    test('ignores other categories and needs at least 5 past expenses', () {
      final food = exp(2400, 'food', DateTime(2026, 11, 3));
      expect(InsightsService.checkUnusual(food, history), isNull);
      final shortHistory = history.take(4).toList();
      final big = exp(2400, 'shopping', DateTime(2026, 11, 3));
      expect(InsightsService.checkUnusual(big, shortHistory), isNull);
    });

    test('a past outlier does not hide a new one (robust statistics)', () {
      final withOutlier = [...history, exp(5000, 'shopping', DateTime(2026, 10, 10))];
      final big = exp(1500, 'shopping', DateTime(2026, 11, 3));
      expect(InsightsService.checkUnusual(big, withOutlier), isNotNull);
    });
  });

  group('budget pace', () {
    test('warns when the projection exceeds the budget', () {
      final insights = run(
        expenses: [exp(2000, 'food', DateTime(2026, 11, 10))],
        budgets: {InsightsService.totalBudgetKey: 3000},
      );
      final warning = insights.firstWhere((i) => i.title == 'Risque de dépassement du budget');
      expect(warning.kind, InsightKind.warning);
      expect(warning.message, contains('par jour'));
    });

    test('alerts when the budget is already exceeded', () {
      final insights = run(
        expenses: [exp(3500, 'food', DateTime(2026, 11, 10))],
        budgets: {InsightsService.totalBudgetKey: 3000},
      );
      expect(insights.first.kind, InsightKind.danger);
      expect(insights.first.title, 'Budget mensuel dépassé');
    });

    test('rent paid on day 1 is not extrapolated to the whole month', () {
      final insights = run(
        expenses: [exp(2500, 'housing', DateTime(2026, 11, 1)), exp(500, 'food', DateTime(2026, 11, 10))],
        budgets: {InsightsService.totalBudgetKey: 4000},
      );
      // Naive projection: 3000 / 15 * 30 = 6000 (> budget). Fixed-aware: 2500 + 1000 = 3500.
      expect(insights.where((i) => i.title == 'Risque de dépassement du budget'), isEmpty);
    });

    test('category budget at 80 % or more', () {
      final insights = run(
        expenses: [exp(450, 'restaurant', DateTime(2026, 11, 10))],
        budgets: {InsightsService.totalBudgetKey: 100000, 'restaurant': 500},
      );
      expect(insights.any((i) => i.title == 'Budget Restaurants presque atteint'), isTrue);
    });

    test('ignores expenses of other months and future dates', () {
      final insights = run(
        expenses: [exp(5000, 'food', DateTime(2026, 10, 10)), exp(5000, 'food', DateTime(2026, 11, 20))],
        budgets: {InsightsService.totalBudgetKey: 3000},
      );
      expect(insights.where((i) => i.title.contains('Budget mensuel')), isEmpty);
    });
  });

  test('category spike compared with previous months', () {
    final insights = run(expenses: [
      exp(300, 'leisure', DateTime(2026, 9, 10)),
      exp(300, 'leisure', DateTime(2026, 10, 10)),
      exp(500, 'leisure', DateTime(2026, 11, 5)),
    ]);
    final spike = insights.firstWhere((i) => i.title == 'Hausse inhabituelle : Loisirs');
    expect(spike.kind, InsightKind.anomaly);
    expect(spike.message, contains('+67 %'));
  });

  group('goals', () {
    test('monthly amount needed to reach the goal on time', () {
      final insights = run(goals: [
        SavingsGoal(name: 'Voyage', target: 5000, saved: 2000, deadline: DateTime(2027, 4, 15), createdAt: DateTime(2026, 11, 1)),
      ]);
      final tip = insights.firstWhere((i) => i.title.contains('Voyage'));
      expect(tip.kind, InsightKind.tip);
      expect(tip.message, contains(money(600)));
    });

    test('behind schedule becomes a warning, missed deadline a danger', () {
      final insights = run(goals: [
        SavingsGoal(name: 'PC', target: 8000, saved: 500, deadline: DateTime(2027, 1, 15), createdAt: DateTime(2026, 5, 15)),
        SavingsGoal(name: 'Vélo', target: 3000, saved: 1000, deadline: DateTime(2026, 10, 1), createdAt: DateTime(2026, 1, 1)),
      ]);
      expect(insights.firstWhere((i) => i.title.contains('PC')).kind, InsightKind.warning);
      expect(insights.firstWhere((i) => i.title.contains('Vélo')).kind, InsightKind.danger);
    });
  });

  test('suggests a budget from past months when none is set', () {
    final insights = run(
      budgets: const {},
      expenses: [exp(4000, 'food', DateTime(2026, 9, 10)), exp(5000, 'food', DateTime(2026, 10, 10))],
    );
    final tip = insights.firstWhere((i) => i.title == 'Définissez un budget mensuel');
    expect(tip.message, contains(money(4300))); // 4500 * 0.95 rounded to 100
  });

  test('insights are sorted by severity', () {
    final insights = run(
      budgets: {InsightsService.totalBudgetKey: 1000},
      expenses: [exp(1500, 'food', DateTime(2026, 11, 10))],
      goals: [SavingsGoal(name: 'A', target: 100, saved: 100, createdAt: DateTime(2026, 1, 1))],
    );
    final priorities = insights.map((i) => i.priority).toList();
    expect(priorities, orderedEquals([...priorities]..sort()));
  });

  test('highlights keep one insight of each kind before repeating a kind', () {
    const danger = Insight(kind: InsightKind.danger, title: 'd', message: '');
    const anomaly = Insight(kind: InsightKind.anomaly, title: 'a', message: '');
    const tip = Insight(kind: InsightKind.tip, title: 't', message: '');
    final picked = InsightsService.highlights([danger, danger, danger, anomaly, tip]);
    expect(picked.map((i) => i.kind), [InsightKind.danger, InsightKind.anomaly, InsightKind.tip]);
  });

  test('demo data triggers the unusual purchase and leisure spike', () {
    final demo = DemoData.generate(now);
    expect(demo.expenses.every((e) => !e.date.isAfter(now)), isTrue);
    final insights = InsightsService.generate(
      expenses: demo.expenses,
      budgets: demo.budgets,
      goals: demo.goals,
      now: now,
    );
    expect(insights.any((i) => i.kind == InsightKind.anomaly && i.message.contains('Nouveau téléphone')), isTrue);
    expect(insights.any((i) => i.title == 'Hausse inhabituelle : Loisirs'), isTrue);
  });

  test('parseAmount accepts French and English formats', () {
    expect(parseAmount('1 200,50'), 1200.5);
    expect(parseAmount('1200.5'), 1200.5);
    expect(parseAmount('abc'), isNull);
  });
}
