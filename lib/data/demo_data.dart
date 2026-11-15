import 'dart:math';

import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';
import '../services/insights_service.dart';
import '../utils/dates.dart';
import '../l10n/l10n.dart';

/// Realistic sample data (4 past months + current month) so the charts and the
/// insights engine have something to show during a demo. The current month
/// contains a deliberately unusual purchase and a spike in leisure spending.
class DemoData {
  final List<Expense> expenses;
  final Map<String, double> budgets;
  final List<SavingsGoal> goals;

  /// Cash for day-to-day spending, a bank account for fixed costs and bigger buys.
  final List<Wallet> wallets;

  /// Salary into the bank account, weekly cash withdrawals, opening balances.
  final List<Deposit> deposits;

  DemoData._(this.expenses, this.budgets, this.goals, this.wallets, this.deposits);

  factory DemoData.generate(DateTime now) {
    final rnd = Random(42);
    final expenses = <Expense>[];
    double between(int min, int max) => (min + rnd.nextInt(max - min + 1)).toDouble();

    final cash = Wallet(id: 'demo-cash', name: tr('Espèces'), type: WalletType.cash, createdAt: addMonths(now, -5));
    final bank = Wallet(id: 'demo-bank', name: tr('Compte bancaire'), type: WalletType.bank, createdAt: addMonths(now, -5));
    const paidByBank = {'housing', 'bills', 'education', 'shopping', 'health'};

    void add(DateTime date, String cat, double amount, [String note = '']) {
      if (date.isAfter(now)) return;
      final wallet = paidByBank.contains(cat) ? bank : cash;
      expenses.add(Expense(amount: amount, categoryId: cat, date: date, note: note, walletId: wallet.id));
    }

    final deposits = <Deposit>[];
    void deposit(DateTime date, Wallet to, double amount, DepositKind kind, String note, [Wallet? from]) {
      if (date.isAfter(now)) return;
      deposits.add(Deposit(
        id: 'demo-d${deposits.length}',
        walletId: to.id,
        amount: amount,
        date: date,
        kind: kind,
        note: note,
        sourceWalletId: from?.id,
      ));
    }

    final current = monthStart(now);
    final first = addMonths(current, -4);
    deposit(first, bank, 3000, DepositKind.adjustment, tr('Solde de départ'));
    deposit(first, cash, 500, DepositKind.adjustment, tr('Solde de départ'));

    for (var m = -4; m <= 0; m++) {
      final month = addMonths(current, m);
      final lastDay = m == 0 ? now.day : daysInMonth(month);
      DateTime day(int d) => DateTime(month.year, month.month, d, 12);

      deposit(DateTime(month.year, month.month, 1, 8), bank, 9500, DepositKind.income, tr('Salaire'));
      for (var d = 1; d <= lastDay; d++) {
        if (DateTime(month.year, month.month, d).weekday == DateTime.monday) {
          deposit(DateTime(month.year, month.month, d, 9), cash, 900, DepositKind.transfer, tr('Retrait'), bank);
        }
      }

      add(day(1), 'housing', 2500, tr('Loyer'));
      add(day(5), 'bills', between(320, 420), tr('Électricité & eau'));
      add(day(8), 'bills', 199, tr('Internet'));
      add(day(10), 'education', 250, tr('Cours d\'anglais'));

      for (var d = 1; d <= lastDay; d++) {
        final weekday = day(d).weekday;
        if (weekday == DateTime.monday || weekday == DateTime.thursday || weekday == DateTime.saturday) {
          add(day(d), 'food', between(90, 230), tr('Courses'));
        }
        if (weekday == DateTime.friday) add(day(d), 'restaurant', between(70, 160), tr('Restaurant'));
        if (weekday == DateTime.wednesday) add(day(d), 'transport', between(60, 110), tr('Carburant'));
        if (weekday == DateTime.sunday && m != 0) add(day(d), 'leisure', between(60, 140), tr('Sortie'));
      }
      if (lastDay >= 12) add(day(12), 'shopping', between(150, 320), tr('Vêtements'));
      if (lastDay >= 24) add(day(24), 'shopping', between(120, 280), tr('Maison'));
      if (m == -2) add(day(17), 'health', 180, tr('Pharmacie'));
    }

    // Current month: unusual purchase + leisure spike (detected by the insights).
    DateTime cur(int d) => DateTime(now.year, now.month, min(d, now.day), 12);
    add(cur(3), 'shopping', 2400, tr('Nouveau téléphone'));
    add(cur(2), 'leisure', 350, tr('Concert'));
    add(cur(4), 'leisure', 280, tr('Parc d\'attractions'));
    add(cur(6), 'leisure', 190, tr('Cinéma & dîner'));

    final budgets = <String, double>{
      InsightsService.totalBudgetKey: 8500,
      'food': 2200,
      'restaurant': 500,
      'leisure': 500,
      'shopping': 600,
    };

    DateTime monthsFromNow(int n) => DateTime(now.year, now.month + n, now.day);
    final goals = [
      SavingsGoal(name: tr('Voyage à Marrakech'), target: 5000, saved: 1900, deadline: monthsFromNow(5), createdAt: monthsFromNow(-3)),
      SavingsGoal(name: tr('Fonds d\'urgence'), target: 10000, saved: 2500, deadline: monthsFromNow(10), createdAt: monthsFromNow(-2)),
      SavingsGoal(name: tr('Nouvel ordinateur'), target: 8000, saved: 1200, deadline: monthsFromNow(2), createdAt: monthsFromNow(-4)),
    ];

    return DemoData._(expenses, budgets, goals, [cash, bank], deposits);
  }
}
