class SavingsGoal {
  final String? id;
  final String name;
  final double target;
  final double saved;
  final DateTime? deadline;
  final DateTime createdAt;

  const SavingsGoal({
    this.id,
    required this.name,
    required this.target,
    this.saved = 0,
    this.deadline,
    required this.createdAt,
  });

  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);
  double get remaining => (target - saved).clamp(0.0, double.infinity);
  bool get isReached => saved >= target;

  SavingsGoal copyWith({String? id, String? name, double? target, double? saved, DateTime? deadline, bool clearDeadline = false}) {
    return SavingsGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      saved: saved ?? this.saved,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'target': target,
        'saved': saved,
        'deadline': deadline?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SavingsGoal.fromMap(Map<String, Object?> map) => SavingsGoal(
        id: map['id']?.toString(),
        name: map['name'] as String,
        target: (map['target'] as num).toDouble(),
        saved: (map['saved'] as num).toDouble(),
        deadline: map['deadline'] == null ? null : DateTime.fromMillisecondsSinceEpoch(map['deadline'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
