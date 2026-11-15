/// A money movement on a wallet that is not an expense.
enum DepositKind {
  /// From outside the app's wallets: salary, cash withdrawal, gift...
  income,

  /// From another wallet (e.g. bank account to cash). Neutral for totals.
  transfer,

  /// Money leaving the wallet without being an expense: set aside, lent,
  /// moved to an account the app does not follow. [Deposit.amount] is
  /// positive and is subtracted from the balance.
  withdrawal,

  /// Correction so the balance matches what the person really has. Can be
  /// negative. The first one sets the starting balance.
  adjustment;

  static DepositKind fromName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => income);
}

/// Money added to, taken out of, or moved between wallets. Expenses are
/// recorded separately. A wallet's balance is tracked from its first
/// movement (see WalletMath).
class Deposit {
  const Deposit({
    required this.id,
    required this.walletId,
    required this.amount,
    required this.date,
    required this.kind,
    this.note = '',
    this.sourceWalletId,
    this.sourceAmount,
  });

  final String id;

  /// Wallet receiving the money (or losing it, for a withdrawal).
  final String walletId;

  /// In the receiving wallet's currency.
  final double amount;
  final DateTime date;
  final DepositKind kind;
  final String note;

  /// For a transfer: the wallet the money came from.
  final String? sourceWalletId;

  /// For a transfer between currencies: what left the source wallet, in its
  /// currency (100 € sent, 25 000 DA received). Null means same as [amount].
  final double? sourceAmount;

  double get sentAmount => sourceAmount ?? amount;

  Deposit copyWith({String? walletId, String? sourceWalletId, bool clearSource = false}) => Deposit(
        id: id,
        walletId: walletId ?? this.walletId,
        amount: amount,
        date: date,
        kind: clearSource ? DepositKind.income : kind,
        note: note,
        sourceWalletId: clearSource ? null : (sourceWalletId ?? this.sourceWalletId),
        sourceAmount: clearSource ? null : sourceAmount,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'wallet_id': walletId,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'kind': kind.name,
        'note': note,
        'source_wallet_id': sourceWalletId,
        'source_amount': sourceAmount,
      };

  factory Deposit.fromMap(Map<String, Object?> map) => Deposit(
        id: map['id'].toString(),
        walletId: map['wallet_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
        kind: DepositKind.fromName(map['kind'] as String?),
        note: (map['note'] as String?) ?? '',
        sourceWalletId: map['source_wallet_id'] as String?,
        sourceAmount: (map['source_amount'] as num?)?.toDouble(),
      );
}
