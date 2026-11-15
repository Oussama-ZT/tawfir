import '../models/expense.dart';

/// The month's budget as an envelope: money reserved in wallets for the
/// month's spending. Amounts are in the main currency.
///
/// The money stays in the wallets (their balance is what is really there);
/// the envelope only reserves part of it. Each expense uses up the share of
/// the wallet that paid it; beyond that share, or from a wallet that does not
/// fund the envelope, the expense is outside the budget.
class Envelope {
  const Envelope({required this.total, this.funds = const {}});

  /// The whole envelope (the global budget).
  final double total;

  /// Share reserved in each wallet, by wallet id. Empty means one shared
  /// envelope: every expense counts, whatever the wallet (accounts that set
  /// their budget before envelopes existed).
  final Map<String, double> funds;

  bool get isEmpty => total <= 0;
  bool get shared => funds.isEmpty;
}

/// Where a month's spending stands against the envelope.
class EnvelopeMonth {
  const EnvelopeMonth({
    required this.total,
    required this.used,
    required this.outside,
    required this.leftByWallet,
    required this.outsideExpenseIds,
  });

  static const none = EnvelopeMonth(total: 0, used: 0, outside: 0, leftByWallet: {}, outsideExpenseIds: {});

  final double total;

  /// Spending paid from the envelope.
  final double used;

  /// Spending outside the budget.
  final double outside;

  /// What is still reserved in each funding wallet (empty when shared).
  final Map<String, double> leftByWallet;

  /// Expenses that went (at least partly) beyond their wallet's share.
  final Set<String> outsideExpenseIds;

  double get left => (total - used).clamp(0, double.infinity).toDouble();
  double get ratio => total <= 0 ? 0 : used / total;

  /// The envelope is empty and spending carried on outside it.
  bool get exceeded => total > 0 && left <= 0.005 && outside > 0.005;
}

class EnvelopeMath {
  /// [expenses] are the month's expenses, in any order.
  static EnvelopeMonth compute(Envelope env, List<Expense> expenses) {
    if (env.isEmpty) {
      final spent = expenses.fold(0.0, (s, e) => s + e.amount);
      return EnvelopeMonth(
        total: 0,
        used: 0,
        outside: spent,
        leftByWallet: const {},
        outsideExpenseIds: {for (final e in expenses) ?e.id},
      );
    }
    // Oldest first: the envelope is used up in the order money was spent.
    final ordered = [...expenses]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        final ai = int.tryParse(a.id ?? ''), bi = int.tryParse(b.id ?? '');
        return ai != null && bi != null ? ai.compareTo(bi) : 0;
      });

    final spentBy = <String, double>{};
    var used = 0.0, outside = 0.0;
    final outsideIds = <String>{};
    for (final e in ordered) {
      // A shared envelope is one pot for every wallet.
      final pot = env.shared ? '' : (e.walletId ?? '');
      final cap = env.shared ? env.total : (env.funds[pot] ?? 0);
      final before = spentBy[pot] ?? 0;
      final after = before + e.amount;
      spentBy[pot] = after;
      final inside = (cap - before).clamp(0.0, e.amount).toDouble();
      used += inside;
      if (e.amount - inside > 0.005) {
        outside += e.amount - inside;
        if (e.id != null) outsideIds.add(e.id!);
      }
    }
    return EnvelopeMonth(
      total: env.total,
      used: used,
      outside: outside,
      leftByWallet: env.shared
          ? const {}
          : {
              for (final f in env.funds.entries)
                f.key: (f.value - (spentBy[f.key] ?? 0)).clamp(0, double.infinity).toDouble(),
            },
      outsideExpenseIds: outsideIds,
    );
  }
}
