import 'package:material_ui/material_ui.dart';
import '../l10n/l10n.dart';

/// Expense category: one of the [defaults] every account has, or a custom
/// one created by the person (Pro and Premium). The id is stored with each
/// expense.
class ExpenseCategory {
  final String id;
  /// The label as written: French for the built-in categories.
  final String rawLabel;
  final IconData icon;
  final Color color;

  /// Key in [icons] for custom categories (icons must be constants so the
  /// release build can strip unused icon glyphs).
  final String? iconKey;

  const ExpenseCategory({
    required this.id,
    required String label,
    required this.icon,
    required this.color,
    this.iconKey,
  }) : rawLabel = label;

  /// Shown label: built-in categories in the current language.
  String get label => isCustom ? rawLabel : tr(rawLabel);

  bool get isCustom => iconKey != null;

  static const otherId = 'other';

  static const List<ExpenseCategory> defaults = [
    ExpenseCategory(id: 'food', label: 'Alimentation', icon: Icons.shopping_basket_outlined, color: Color(0xFF2E7D32)),
    ExpenseCategory(id: 'restaurant', label: 'Restaurants', icon: Icons.restaurant_outlined, color: Color(0xFFEF6C00)),
    ExpenseCategory(id: 'transport', label: 'Transport', icon: Icons.directions_bus_outlined, color: Color(0xFF1565C0)),
    ExpenseCategory(id: 'housing', label: 'Logement', icon: Icons.home_outlined, color: Color(0xFF6A1B9A)),
    ExpenseCategory(id: 'bills', label: 'Factures', icon: Icons.receipt_long_outlined, color: Color(0xFF00838F)),
    ExpenseCategory(id: 'health', label: 'Santé', icon: Icons.local_hospital_outlined, color: Color(0xFFC62828)),
    ExpenseCategory(id: 'leisure', label: 'Loisirs', icon: Icons.sports_esports_outlined, color: Color(0xFFAD1457)),
    ExpenseCategory(id: 'shopping', label: 'Shopping', icon: Icons.shopping_bag_outlined, color: Color(0xFF4E342E)),
    ExpenseCategory(id: 'education', label: 'Éducation', icon: Icons.school_outlined, color: Color(0xFF283593)),
    ExpenseCategory(id: otherId, label: 'Autre', icon: Icons.more_horiz, color: Color(0xFF546E7A)),
  ];

  /// Icons offered when creating a category.
  static const Map<String, IconData> icons = {
    'pets': Icons.pets_outlined,
    'baby': Icons.child_friendly_outlined,
    'gift': Icons.card_giftcard_outlined,
    'sport': Icons.fitness_center_outlined,
    'travel': Icons.flight_outlined,
    'car': Icons.directions_car_outlined,
    'phone': Icons.smartphone_outlined,
    'beauty': Icons.spa_outlined,
    'coffee': Icons.local_cafe_outlined,
    'music': Icons.music_note_outlined,
    'book': Icons.menu_book_outlined,
    'work': Icons.work_outline_rounded,
    'charity': Icons.volunteer_activism_outlined,
    'tools': Icons.build_outlined,
    'game': Icons.videogame_asset_outlined,
    'star': Icons.star_outline_rounded,
  };

  /// Colours offered when creating a category.
  static const List<Color> palette = [
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFC62828),
    Color(0xFFAD1457),
    Color(0xFF5D4037),
  ];

  factory ExpenseCategory.custom({required String id, required String label, required String iconKey, required Color color}) =>
      ExpenseCategory(id: id, label: label, icon: icons[iconKey] ?? Icons.star_outline_rounded, color: color, iconKey: iconKey);

  ExpenseCategory copyWith({String? label, String? iconKey, Color? color}) =>
      ExpenseCategory.custom(id: id, label: label ?? rawLabel, iconKey: iconKey ?? this.iconKey!, color: color ?? this.color);

  Map<String, Object?> toMap() => {'id': id, 'label': rawLabel, 'icon': iconKey, 'color': color.toARGB32()};

  factory ExpenseCategory.fromMap(Map<String, Object?> map) => ExpenseCategory.custom(
        id: map['id'].toString(),
        label: map['label'] as String,
        iconKey: map['icon'] as String? ?? 'star',
        color: Color(map['color'] as int),
      );

  // The signed-in person's custom categories, set by AppState when it loads.
  static List<ExpenseCategory> _custom = const [];

  /// False when the plan no longer includes custom categories: they are
  /// frozen, not offered for new expenses, but past expenses keep them.
  static bool customEnabled = true;

  static List<ExpenseCategory> get customList => _custom;

  static set customList(List<ExpenseCategory> list) => _custom = List.unmodifiable(list);

  /// Categories that can be picked: defaults, plus custom ones unless
  /// frozen, with "Autre" kept last.
  static List<ExpenseCategory> get visible => [
        ...defaults.where((c) => c.id != otherId),
        if (customEnabled) ..._custom,
        defaults.last,
      ];

  /// Unknown ids (e.g. a deleted custom category) show as "Autre".
  static ExpenseCategory byId(String id) =>
      defaults.firstWhere((c) => c.id == id, orElse: () => _custom.firstWhere((c) => c.id == id, orElse: () => defaults.last));
}
