import 'package:material_ui/material_ui.dart';

import 'currency.dart';
import '../l10n/l10n.dart';

/// Kind of wallet. Starter and Pro can use [cash] and [bank]; Premium can
/// use every kind and give wallets their own name (see Plan).
enum WalletType {
  cash('Espèces', Icons.payments_outlined),
  bank('Compte bancaire', Icons.account_balance_outlined),
  card('Carte', Icons.credit_card_outlined),
  savings('Épargne', Icons.savings_outlined),
  mobile('Paiement mobile', Icons.phone_iphone_outlined),
  other('Autre', Icons.wallet_outlined);

  const WalletType(this._label, this.icon);

  final String _label;
  String get label => tr(_label);
  final IconData icon;

  static WalletType fromName(String? name) => values.firstWhere((t) => t.name == name, orElse: () => other);
}

/// Where money is spent from: cash, a bank account, a card, Paysera...
/// Every expense belongs to one wallet.
///
/// A wallet can hold another currency than the account's main one (Premium):
/// expenses are then entered in that currency and converted with [rate],
/// the rate the person actually gets when changing money.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.currencyCode,
    this.rate,
  });

  /// Created on the phone (see newId), so expenses can point to it right away.
  final String id;
  final String name;
  final WalletType type;
  final DateTime createdAt;

  /// Null means the account's main currency.
  final String? currencyCode;

  /// Value of 1 unit of [currencyCode] in the main currency, e.g. 1 € = 250 DA.
  final double? rate;

  /// The wallet a new account starts with.
  factory Wallet.starter(String id) =>
      Wallet(id: id, name: WalletType.cash.label, type: WalletType.cash, createdAt: DateTime.now());

  /// True when amounts in this wallet must be converted to [mainCode].
  bool isForeign(String mainCode) => currencyCode != null && currencyCode != mainCode && (rate ?? 0) > 0;

  Currency currencyOr(Currency main) => isForeign(main.code) ? Currency.byCode(currencyCode) : main;

  Wallet copyWith({String? name, WalletType? type, String? currencyCode, double? rate, bool mainCurrency = false}) =>
      Wallet(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        createdAt: createdAt,
        currencyCode: mainCurrency ? null : (currencyCode ?? this.currencyCode),
        rate: mainCurrency ? null : (rate ?? this.rate),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'currency': currencyCode,
        'rate': rate,
      };

  factory Wallet.fromMap(Map<String, Object?> map) => Wallet(
        id: map['id'].toString(),
        name: map['name'] as String,
        type: WalletType.fromName(map['type'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        currencyCode: map['currency'] as String?,
        rate: (map['rate'] as num?)?.toDouble(),
      );
}
