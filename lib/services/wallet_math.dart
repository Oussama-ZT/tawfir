import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/wallet.dart';

/// Balance arithmetic for wallets, kept pure so it can be tested on its own.
/// All amounts returned are in the wallet's own currency.
class WalletMath {
  /// An expense expressed in the wallet's currency (20 € for a Paysera
  /// wallet, even though totals count it as 5 000 DA).
  static double expenseIn(Wallet w, Expense e, String mainCode) {
    if (!w.isForeign(mainCode)) return e.amount;
    return e.originalCurrency == w.currencyCode && e.originalAmount != null ? e.originalAmount! : e.amount / w.rate!;
  }

  /// When balance tracking starts: the first deposit into or out of the
  /// wallet. Null means the balance is unknown (no money added yet).
  static DateTime? trackingStart(Wallet w, List<Deposit> deposits) {
    DateTime? start;
    for (final d in deposits) {
      if (d.walletId != w.id && d.sourceWalletId != w.id) continue;
      if (start == null || d.date.isBefore(start)) start = d.date;
    }
    return start;
  }

  /// Money in minus money out since tracking started; null if not tracked.
  static double? balance(Wallet w, List<Expense> expenses, List<Deposit> deposits, String mainCode) {
    final start = trackingStart(w, deposits);
    if (start == null) return null;
    var total = 0.0;
    for (final d in deposits) {
      if (d.walletId == w.id) total += d.kind == DepositKind.withdrawal ? -d.amount : d.amount;
      if (d.sourceWalletId == w.id) total -= d.sentAmount;
    }
    for (final e in expenses) {
      if (e.walletId == w.id && !e.date.isBefore(start)) total -= expenseIn(w, e, mainCode);
    }
    return total;
  }

  /// Income received, money spent and money withdrawn from [since], in the
  /// wallet's currency (transfers and corrections excluded).
  static ({double received, double spent, double withdrawn}) flowsSince(
      Wallet w, List<Expense> expenses, List<Deposit> deposits, DateTime since, String mainCode) {
    var received = 0.0, spent = 0.0, withdrawn = 0.0;
    for (final d in deposits) {
      if (d.walletId != w.id || d.date.isBefore(since)) continue;
      if (d.kind == DepositKind.income) received += d.amount;
      if (d.kind == DepositKind.withdrawal) withdrawn += d.amount;
    }
    for (final e in expenses) {
      if (e.walletId == w.id && !e.date.isBefore(since)) spent += expenseIn(w, e, mainCode);
    }
    return (received: received, spent: spent, withdrawn: withdrawn);
  }

  /// Money that came in from outside (salary, withdrawals, gifts) during a
  /// month; transfers and corrections excluded.
  static double incomeIn(Wallet w, List<Deposit> deposits, DateTime month) => deposits
      .where((d) =>
          d.walletId == w.id &&
          d.kind == DepositKind.income &&
          d.date.year == month.year &&
          d.date.month == month.month)
      .fold(0.0, (s, d) => s + d.amount);
}
