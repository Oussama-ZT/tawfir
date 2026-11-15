enum InsightKind {
  /// Something already went wrong (budget exceeded, deadline missed).
  danger,

  /// Unusual spending detected.
  anomaly,

  /// Will go wrong at the current pace.
  warning,

  /// Actionable suggestion.
  tip,

  /// Positive feedback.
  success,
}

class Insight {
  final InsightKind kind;
  final String title;
  final String message;
  final String? categoryId;

  const Insight({required this.kind, required this.title, required this.message, this.categoryId});

  /// Lower comes first when sorting.
  int get priority => kind.index;
}
