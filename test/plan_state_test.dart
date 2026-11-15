import 'package:eco_budget/models/category.dart';
import 'package:eco_budget/models/plan.dart';
import 'package:eco_budget/models/wallet.dart';
import 'package:eco_budget/services/subscription_service.dart';
import 'package:eco_budget/state/plan_state.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plans', () {
    test('without RevenueCat keys everyone is on Starter', () async {
      final service = await SubscriptionService.create();
      expect(service.available, isFalse);
      final plan = PlanState(service);
      await plan.load();
      expect(plan.plan, Plan.starter);
      await plan.loadOffers();
      expect(plan.offers, isEmpty);
    });

    test('Starter: one cash or bank wallet, default categories only', () async {
      final plan = PlanState(await SubscriptionService.create());
      expect(plan.canAddWallet(0), isTrue);
      expect(plan.canAddWallet(1), isFalse);
      expect(plan.canUseWalletType(WalletType.cash), isTrue);
      expect(plan.canUseWalletType(WalletType.bank), isTrue);
      expect(plan.canUseWalletType(WalletType.card), isFalse);
      expect(plan.canCustomizeCategories, isFalse);
      expect(plan.canAddGoal(Plan.starter.goalLimit!), isFalse);
      expect(plan.canAddCategoryBudget(Plan.starter.categoryBudgetLimit!), isFalse);
    });

    test('Pro: two cash/bank wallets and custom categories', () async {
      final plan = PlanState(await SubscriptionService.create())..setTestPlan(Plan.pro);
      expect(plan.canAddWallet(1), isTrue);
      expect(plan.canAddWallet(2), isFalse);
      expect(plan.canUseWalletType(WalletType.savings), isFalse);
      expect(plan.canCustomizeCategories, isTrue);
      expect(plan.canAddGoal(50), isTrue);
    });

    test('Premium: unlimited wallets of every kind', () async {
      final plan = PlanState(await SubscriptionService.create())..setTestPlan(Plan.premium);
      expect(plan.canAddWallet(20), isTrue);
      for (final t in WalletType.values) {
        expect(plan.canUseWalletType(t), isTrue);
      }
      expect(Plan.premium.customWalletNames, isTrue);
    });

    test('lowest plan for a wallet count', () {
      expect(Plan.forWalletCount(1), Plan.starter);
      expect(Plan.forWalletCount(2), Plan.pro);
      expect(Plan.forWalletCount(3), Plan.premium);
    });
  });

  group('custom categories', () {
    tearDown(() => ExpenseCategory.customList = const []);

    test('appear before "Autre", which stays last', () {
      final pets = ExpenseCategory.custom(id: 'c1', label: 'Animaux', iconKey: 'pets', color: const Color(0xFF2E7D32));
      ExpenseCategory.customList = [pets];
      final visible = ExpenseCategory.visible;
      expect(visible.last.id, ExpenseCategory.otherId);
      expect(visible[visible.length - 2].id, 'c1');
      expect(ExpenseCategory.byId('c1').label, 'Animaux');
    });

    test('unknown or deleted ids show as "Autre"', () {
      expect(ExpenseCategory.byId('gone').id, ExpenseCategory.otherId);
    });

    test('round-trip through storage', () {
      final c = ExpenseCategory.custom(id: 'c2', label: 'Sport', iconKey: 'sport', color: const Color(0xFFC62828));
      final back = ExpenseCategory.fromMap(c.toMap());
      expect(back.label, 'Sport');
      expect(back.iconKey, 'sport');
      expect(back.color, c.color);
      expect(back.isCustom, isTrue);
    });
  });
}
