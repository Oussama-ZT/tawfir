class Expense {
  final String? id;

  /// In the account's main currency. Totals, budgets, charts and advice all
  /// use this value.
  final double amount;
  final String categoryId;
  final DateTime date;
  final String note;

  /// Wallet it was paid from. Null only for expenses recorded before wallets
  /// existed; AppState.load assigns those to the first wallet.
  final String? walletId;

  /// Amount as paid, when the wallet uses another currency (e.g. 20 € from
  /// a Paysera wallet). [amount] holds the converted value at the rate of
  /// that day, so later rate changes do not rewrite past expenses.
  final double? originalAmount;
  final String? originalCurrency;

  const Expense({
    this.id,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.walletId,
    this.originalAmount,
    this.originalCurrency,
  });

  bool get isConverted => originalAmount != null && originalCurrency != null;

  /// Money given back for a purchase, stored as a negative expense: totals
  /// drop by it and the wallet gets it back.
  bool get isRefund => amount < 0;

  /// Rate used when it was recorded (main currency per unit of the original).
  /// A refund has both amounts negative, so the rate stays positive.
  double? get rate => isConverted && originalAmount! != 0 ? amount / originalAmount! : null;

  Expense copyWith({String? id, double? amount, String? categoryId, DateTime? date, String? note, String? walletId}) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      walletId: walletId ?? this.walletId,
      originalAmount: originalAmount,
      originalCurrency: originalCurrency,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'amount': amount,
    'category_id': categoryId,
    'date': date.millisecondsSinceEpoch,
    'note': note,
    'wallet_id': walletId,
    'original_amount': originalAmount,
    'original_currency': originalCurrency,
  };

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map['id']?.toString(),
    amount: (map['amount'] as num).toDouble(),
    categoryId: map['category_id'] as String,
    date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
    note: (map['note'] as String?) ?? '',
    walletId: map['wallet_id'] as String?,
    originalAmount: (map['original_amount'] as num?)?.toDouble(),
    originalCurrency: map['original_currency'] as String?,
  );
}
