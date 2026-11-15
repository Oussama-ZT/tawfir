import 'wallet.dart';

/// The three plans and what each allows. Change the limits here: the plans
/// screen, the checks and the tests all read them from this file.
///
/// After a downgrade (subscription expired), what goes beyond the new plan is
/// frozen, never deleted: it stays visible but cannot be used or changed
/// until the person subscribes again (see AppState, section "freeze").
enum Plan {
  starter(
    label: 'Starter',
    walletLimit: 1,
    walletTypes: {WalletType.cash, WalletType.bank},
    customCategories: false,
    foreignCurrencyWallets: false,
    goalLimit: 2,
    categoryBudgetLimit: 3,
  ),
  pro(
    label: 'Pro',
    walletLimit: 2,
    walletTypes: {WalletType.cash, WalletType.bank},
    customCategories: true,
    foreignCurrencyWallets: false,
    goalLimit: null,
    categoryBudgetLimit: null,
  ),
  premium(
    label: 'Premium',
    walletLimit: null,
    walletTypes: null,
    customCategories: true,
    foreignCurrencyWallets: true,
    goalLimit: null,
    categoryBudgetLimit: null,
  );

  const Plan({
    required this.label,
    required this.walletLimit,
    required this.walletTypes,
    required this.customCategories,
    required this.foreignCurrencyWallets,
    required this.goalLimit,
    required this.categoryBudgetLimit,
  });

  final String label;

  /// Null means unlimited.
  final int? walletLimit;

  /// Wallet kinds allowed; null means all kinds plus a custom name.
  final Set<WalletType>? walletTypes;

  /// Can create, rename and delete categories beyond the defaults.
  final bool customCategories;

  /// Wallets in another currency than the account's (e.g. Paysera in euros).
  final bool foreignCurrencyWallets;

  /// Null means unlimited.
  final int? goalLimit;

  /// Null means unlimited.
  final int? categoryBudgetLimit;

  bool get isFree => this == starter;

  bool allowsWalletType(WalletType type) => walletTypes?.contains(type) ?? true;

  bool get customWalletNames => walletTypes == null;

  /// Lowest plan that allows a given wallet count.
  static Plan forWalletCount(int count) => values.firstWhere((p) => p.walletLimit == null || count <= p.walletLimit!);
}
