import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config.dart';
import '../models/plan.dart';
import '../l10n/l10n.dart';

/// One plan the person can buy, as shown on the Premium screen.
class PlanOffer {
  const PlanOffer({required this.plan, required this.id, required this.price, required this.period, required this.package});

  final Plan plan;
  final String id;

  /// Already formatted by the store in the buyer's currency, e.g. "2,99 €".
  final String price;

  /// "par mois", "par an", "une fois"...
  final String period;
  final Package package;
}

/// The plan the stores report, and when a paid plan ends.
class PlanStatus {
  const PlanStatus(this.plan, {this.expiresAt, this.willRenew = true});

  static const free = PlanStatus(Plan.starter);

  final Plan plan;

  /// End of the paid period. A cancelled subscription stays active until
  /// then (e.g. paid on 15/10, cancelled: active until 15/11).
  final DateTime? expiresAt;

  /// False once the person cancelled: the plan ends at [expiresAt].
  final bool willRenew;

  bool get endsSoon => !plan.isFree && !willRenew && expiresAt != null;
}

class SubscriptionException implements Exception {
  const SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Paid plans through RevenueCat, which handles Google Play and App Store
/// billing and tells the app which plan the person has.
class SubscriptionService {
  SubscriptionService._(this.available);

  /// False until RevenueCat keys are set in [AppConfig].
  final bool available;

  static Future<SubscriptionService> create() async {
    final key = Platform.isIOS || Platform.isMacOS ? AppConfig.revenueCatAppleKey : AppConfig.revenueCatGoogleKey;
    if (key.isEmpty) return SubscriptionService._(false);
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      return SubscriptionService._(true);
    } catch (e) {
      debugPrint('RevenueCat: $e');
      return SubscriptionService._(false);
    }
  }

  /// Ties purchases to the account, so Premium follows it to other phones.
  Future<void> logIn(String userId) async {
    if (available) await Purchases.logIn(userId);
  }

  Future<void> logOut() async {
    if (!available) return;
    try {
      await Purchases.logOut();
    } on PlatformException catch (_) {
      // Already anonymous.
    }
  }

  Future<PlanStatus> currentStatus() async {
    if (!available) return PlanStatus.free;
    return _status(await Purchases.getCustomerInfo());
  }

  /// Packages of the Pro and Premium offerings set up in RevenueCat.
  Future<List<PlanOffer>> offers() async {
    if (!available) return const [];
    final all = (await Purchases.getOfferings()).all;
    return [
      for (final (plan, offeringId) in [(Plan.pro, AppConfig.proOffering), (Plan.premium, AppConfig.premiumOffering)])
        for (final p in all[offeringId]?.availablePackages ?? const <Package>[])
          PlanOffer(
            plan: plan,
            id: p.identifier,
            price: p.storeProduct.priceString,
            period: _period(p.packageType),
            package: p,
          ),
    ];
  }

  /// Returns the status afterwards; null if the person cancelled.
  Future<PlanStatus?> purchase(PlanOffer offer) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(offer.package));
      return _status(result.customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return null;
      debugPrint('RevenueCat purchase: $code ${e.message}');
      throw SubscriptionException(switch (code) {
        PurchasesErrorCode.networkError => tr('Pas de connexion internet. Réessayez.'),
        PurchasesErrorCode.purchaseNotAllowedError => tr('Les achats ne sont pas autorisés sur ce téléphone.'),
        PurchasesErrorCode.productAlreadyPurchasedError => tr('Vous avez déjà cet abonnement. Touchez « Restaurer mes achats ».'),
        PurchasesErrorCode.paymentPendingError => tr('Le paiement est en attente de validation.'),
        _ => tr('L\'achat n\'a pas abouti. Réessayez.'),
      });
    }
  }

  Future<PlanStatus> restore() async {
    try {
      return _status(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      debugPrint('RevenueCat restore: ${e.message}');
      throw SubscriptionException(tr('Impossible de restaurer vos achats. Réessayez.'));
    }
  }

  static PlanStatus _status(CustomerInfo info) {
    final active = info.entitlements.active;
    for (final (plan, id) in [(Plan.premium, AppConfig.premiumEntitlement), (Plan.pro, AppConfig.proEntitlement)]) {
      final e = active[id];
      if (e == null) continue;
      final end = e.expirationDate == null ? null : DateTime.tryParse(e.expirationDate!)?.toLocal();
      return PlanStatus(plan, expiresAt: end, willRenew: e.willRenew);
    }
    return PlanStatus.free;
  }

  static String _period(PackageType type) => switch (type) {
        PackageType.weekly => 'par semaine',
        PackageType.monthly => 'par mois',
        PackageType.twoMonth => tr('tous les 2 mois'),
        PackageType.threeMonth => 'par trimestre',
        PackageType.sixMonth => tr('tous les 6 mois'),
        PackageType.annual => 'par an',
        PackageType.lifetime => tr('une seule fois'),
        _ => '',
      };
}
