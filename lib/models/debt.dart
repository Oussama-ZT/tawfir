import 'dart:convert';

/// Which way the money went.
enum DebtDirection {
  /// I gave money: the person owes me.
  lent,

  /// I took money: I owe the person.
  borrowed;

  static DebtDirection fromName(String? n) => n == borrowed.name ? borrowed : lent;
}

enum DebtEntryKind {
  /// The amount lent or borrowed at the start.
  start,

  /// Lent or borrowed again from the same person.
  more,

  /// Money given back.
  repayment;

  static DebtEntryKind fromName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => repayment);
}

/// One movement of a debt. When [walletId] is set, the wallet has a matching
/// Deposit of kind `debt` with the same [id], so its balance follows.
class DebtEntry {
  const DebtEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    this.walletId,
    this.note = '',
  });

  final String id;
  final DebtEntryKind kind;

  /// Always positive, in the main currency.
  final double amount;
  final DateTime date;

  /// Null: no wallet changed (a debt from before the app, or money handed
  /// over outside the wallets the app follows).
  final String? walletId;
  final String note;

  /// True when it adds to what is owed.
  bool get raises => kind != DebtEntryKind.repayment;

  DebtEntry copyWith({double? amount, DateTime? date, String? walletId, bool clearWallet = false, String? note}) => DebtEntry(
        id: id,
        kind: kind,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        walletId: clearWallet ? null : (walletId ?? this.walletId),
        note: note ?? this.note,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'wallet': walletId,
        'note': note,
      };

  factory DebtEntry.fromMap(Map<String, Object?> m) => DebtEntry(
        id: m['id'].toString(),
        kind: DebtEntryKind.fromName(m['kind'] as String?),
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        walletId: m['wallet'] as String?,
        note: (m['note'] as String?) ?? '',
      );
}

/// Money lent to or borrowed from someone, with everything given back since.
///
/// The debt keeps its own history, so what is owed never depends on the
/// wallets (deleting a wallet keeps the debt right). Lending and repaying
/// move money in and out of wallets, but they are neither expenses nor
/// income: budgets and reports ignore them.
class Debt {
  Debt({
    required this.id,
    required this.person,
    required this.direction,
    required List<DebtEntry> entries,
    this.dueDate,
    this.note = '',
    required this.createdAt,
  }) : entries = [...entries]..sort((a, b) => a.date.compareTo(b.date));

  final String id;
  final String person;
  final DebtDirection direction;

  /// Oldest first; the first one is normally the [DebtEntryKind.start].
  final List<DebtEntry> entries;
  final DateTime? dueDate;
  final String note;
  final DateTime createdAt;

  bool get isLent => direction == DebtDirection.lent;

  /// Everything lent or borrowed.
  double get total => entries.where((e) => e.raises).fold(0.0, (s, e) => s + e.amount);

  /// Everything given back.
  double get repaid => entries.where((e) => !e.raises).fold(0.0, (s, e) => s + e.amount);

  /// Still owed; never negative.
  double get remaining => total - repaid > 0.005 ? total - repaid : 0;

  bool get isSettled => remaining == 0;

  double get progress => total <= 0 ? 0 : (repaid / total).clamp(0.0, 1.0);

  DebtEntry? get start => entries.where((e) => e.kind == DebtEntryKind.start).firstOrNull;

  /// When it began: the first movement.
  DateTime get date => entries.isEmpty ? createdAt : entries.first.date;

  /// Past its due date and not fully given back.
  bool isOverdue(DateTime now) =>
      !isSettled && dueDate != null && dueDate!.isBefore(DateTime(now.year, now.month, now.day));

  /// What an entry does to its wallet: positive arrives, negative leaves.
  /// Lending takes money out, its repayments bring it back; borrowing is
  /// the other way round.
  double walletEffect(DebtEntry e) => (isLent == e.raises) ? -e.amount : e.amount;

  Debt copyWith({
    String? person,
    DebtDirection? direction,
    List<DebtEntry>? entries,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? note,
  }) =>
      Debt(
        id: id,
        person: person ?? this.person,
        direction: direction ?? this.direction,
        entries: entries ?? this.entries,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'person': person,
        'direction': direction.name,
        'due_date': dueDate?.millisecondsSinceEpoch,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'entries': jsonEncode([for (final e in entries) e.toMap()]),
      };

  factory Debt.fromMap(Map<String, Object?> m) {
    final raw = m['entries'];
    final list = raw is String ? jsonDecode(raw) as List : (raw as List? ?? const []);
    return Debt(
      id: m['id'].toString(),
      person: (m['person'] as String?) ?? '',
      direction: DebtDirection.fromName(m['direction'] as String?),
      dueDate: m['due_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
      note: (m['note'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      entries: [for (final e in list) DebtEntry.fromMap(Map<String, Object?>.from(e as Map))],
    );
  }
}
