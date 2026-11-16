import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/plan.dart';
import '../models/wallet.dart';
import '../services/subscription_service.dart';

/// The signed-in person's plan (Starter, Pro or Premium) and what it allows.
class PlanState extends ChangeNotifier {
  PlanState(this._service, {this.accountId});

  final SubscriptionService _service;

  /// Cloud account id. Local accounts are not tied to RevenueCat, since
  /// their ids are only unique on one phone.
  final String? accountId;

  PlanStatus _status = PlanStatus.free;
  Plan? _testPlan;
  List<PlanOffer>? _offers;
  Timer? _endTimer;

  Plan get plan => _testPlan ?? _status.plan;

  /// Set when a cancelled paid plan is about to end (not in test mode).
  DateTime? get endsAt => _testPlan == null && _status.endsSoon ? _status.expiresAt : null;
  bool get storeAvailable => _service.available;
  bool get isTestPlan => _testPlan != null;

  /// Null while loading.
  List<PlanOffer>? get offers => _offers;

  List<PlanOffer> offersFor(Plan p) => [...?_offers?.where((o) => o.plan == p)];

  /// Test builds without real payments can switch plans to try the paid
  /// features (kept in memory only). See [AppConfig.testMode].
  bool get canTestPlans => (kDebugMode || AppConfig.testMode) && !_service.available;

  Future<void> load() async {
    try {
      if (accountId != null) await _service.logIn(accountId!);
      _status = await _service.currentStatus();
    } catch (e) {
      debugPrint('Plan: $e');
    }
    _watchEnd();
    notifyListeners();
  }

  /// A cancelled plan ends while the app may be open: check again then,
  /// so the extra wallets freeze on time.
  void _watchEnd() {
    _endTimer?.cancel();
    final end = _status.endsSoon ? _status.expiresAt : null;
    if (end == null) return;
    final wait = end.difference(DateTime.now()) + const Duration(seconds: 5);
    if (wait > const Duration(days: 40)) return;
    _endTimer = Timer(wait.isNegative ? Duration.zero : wait, load);
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    super.dispose();
  }

  Future<void> loadOffers() async {
    try {
      _offers = await _service.offers();
    } catch (e) {
      debugPrint('Offers: $e');
      _offers = const [];
    }
    notifyListeners();
  }

  /// Returns the plan afterwards, or null if the person cancelled.
  Future<Plan?> purchase(PlanOffer offer) async {
    final result = await _service.purchase(offer);
    if (result != null) _status = result;
    _watchEnd();
    notifyListeners();
    return result?.plan;
  }

  Future<Plan> restore() async {
    _status = await _service.restore();
    _watchEnd();
    notifyListeners();
    return _status.plan;
  }

  /// Test mode only: null goes back to the real plan.
  void setTestPlan(Plan? p) {
    if (!canTestPlans) return;
    _testPlan = p;
    notifyListeners();
  }

  Future<void> signOut() => _service.logOut();

  // --------------------------------------------------------------- limits --

  bool canAddWallet(int currentCount) => plan.walletLimit == null || currentCount < plan.walletLimit!;

  bool canUseWalletType(WalletType type) => plan.allowsWalletType(type);

  bool get canCustomizeCategories => plan.customCategories;

  bool get canUseForeignCurrency => plan.foreignCurrencyWallets;

  bool get canUseDebts => plan.debts;

  bool canAddGoal(int currentCount) => plan.goalLimit == null || currentCount < plan.goalLimit!;

  bool canAddCategoryBudget(int currentCount) =>
      plan.categoryBudgetLimit == null || currentCount < plan.categoryBudgetLimit!;
}
