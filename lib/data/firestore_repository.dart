import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/category.dart';
import '../models/debt.dart';
import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';
import 'repository.dart';

/// Cloud storage for a signed-in Firebase user.
///
/// Layout (matches firestore.rules at the project root):
///   users/{uid}                       profile: name, email, currency
///   users/{uid}/expenses/{id}         amount, category_id, date, note
///   users/{uid}/budgets/{categoryId}  amount
///   users/{uid}/goals/{id}            name, target, saved, deadline, created_at
///   users/{uid}/wallets/{id}          name, type, created_at
///   users/{uid}/categories/{id}       label, icon, color (custom categories)
///   users/{uid}/deposits/{id}         wallet_id, amount, date, kind, note, source_*
///   users/{uid}/debts/{id}            person, direction, due_date, note, created_at, entries (JSON)
///
/// Firestore keeps a copy on the phone, so the app works offline and syncs
/// later. Writes are not awaited: offline, a write only completes once the
/// server confirms it, but it is applied to the local copy immediately.
class FirestoreRepository implements BudgetRepository {
  FirestoreRepository(FirebaseFirestore firestore, String uid) : _user = firestore.collection('users').doc(uid);

  final DocumentReference<Map<String, dynamic>> _user;

  CollectionReference<Map<String, dynamic>> get _expenses => _user.collection('expenses');
  CollectionReference<Map<String, dynamic>> get _budgets => _user.collection('budgets');
  CollectionReference<Map<String, dynamic>> get _goals => _user.collection('goals');
  CollectionReference<Map<String, dynamic>> get _wallets => _user.collection('wallets');
  CollectionReference<Map<String, dynamic>> get _categories => _user.collection('categories');
  CollectionReference<Map<String, dynamic>> get _deposits => _user.collection('deposits');
  CollectionReference<Map<String, dynamic>> get _debts => _user.collection('debts');
  List<CollectionReference<Map<String, dynamic>>> get _all =>
      [_expenses, _budgets, _goals, _wallets, _categories, _deposits, _debts];

  static void _write(Future<void> f) => unawaited(f.catchError((Object e) => debugPrint('Firestore: $e')));

  static Map<String, Object?> _fields(Map<String, Object?> map) => Map.of(map)..remove('id');

  @override
  Future<List<Expense>> expenses() async {
    final snap = await _expenses.orderBy('date', descending: true).get();
    return [for (final d in snap.docs) Expense.fromMap({...d.data(), 'id': d.id})];
  }

  @override
  Future<String> insertExpense(Expense e) async {
    final doc = _expenses.doc();
    _write(doc.set(_fields(e.toMap())));
    return doc.id;
  }

  @override
  Future<void> updateExpense(Expense e) async => _write(_expenses.doc(e.id).set(_fields(e.toMap())));

  @override
  Future<void> deleteExpense(String id) async => _write(_expenses.doc(id).delete());

  @override
  Future<Map<String, double>> budgets() async {
    final snap = await _budgets.get();
    return {for (final d in snap.docs) d.id: (d.data()['amount'] as num).toDouble()};
  }

  @override
  Future<void> setBudget(String key, double amount) async =>
      _write(amount <= 0 ? _budgets.doc(key).delete() : _budgets.doc(key).set({'amount': amount}));

  @override
  Future<List<SavingsGoal>> goals() async {
    final snap = await _goals.orderBy('created_at').get();
    return [for (final d in snap.docs) SavingsGoal.fromMap({...d.data(), 'id': d.id})];
  }

  @override
  Future<String> insertGoal(SavingsGoal g) async {
    final doc = _goals.doc();
    _write(doc.set(_fields(g.toMap())));
    return doc.id;
  }

  @override
  Future<void> updateGoal(SavingsGoal g) async => _write(_goals.doc(g.id).set(_fields(g.toMap())));

  @override
  Future<void> deleteGoal(String id) async => _write(_goals.doc(id).delete());

  @override
  Future<List<Wallet>> wallets() async {
    final snap = await _wallets.orderBy('created_at').get();
    return [for (final d in snap.docs) Wallet.fromMap({...d.data(), 'id': d.id})];
  }

  @override
  Future<void> saveWallet(Wallet w) async => _write(_wallets.doc(w.id).set(_fields(w.toMap())));

  @override
  Future<void> deleteWallet(String id, {required String moveTo}) async {
    final batch = _user.firestore.batch();
    for (final d in (await _expenses.where('wallet_id', isEqualTo: id).get()).docs) {
      batch.update(d.reference, {'wallet_id': moveTo});
    }
    batch.delete(_wallets.doc(id));
    _write(batch.commit());
  }

  @override
  Future<List<ExpenseCategory>> categories() async {
    final snap = await _categories.orderBy('label').get();
    return [for (final d in snap.docs) ExpenseCategory.fromMap({...d.data(), 'id': d.id})];
  }

  @override
  Future<void> saveCategory(ExpenseCategory c) async => _write(_categories.doc(c.id).set(_fields(c.toMap())));

  @override
  Future<void> deleteCategory(String id) async {
    final batch = _user.firestore.batch();
    for (final d in (await _expenses.where('category_id', isEqualTo: id).get()).docs) {
      batch.update(d.reference, {'category_id': ExpenseCategory.otherId});
    }
    batch.delete(_budgets.doc(id));
    batch.delete(_categories.doc(id));
    _write(batch.commit());
  }

  @override
  Future<List<Deposit>> deposits() async {
    final snap = await _deposits.orderBy('date', descending: true).get();
    return [for (final d in snap.docs) Deposit.fromMap({...d.data(), 'id': d.id})];
  }

  @override
  Future<void> saveDeposit(Deposit d) async => _write(_deposits.doc(d.id).set(_fields(d.toMap())));

  @override
  Future<void> deleteDeposit(String id) async => _write(_deposits.doc(id).delete());

  @override
  Future<List<Debt>> debts() async {
    final snap = await _debts.get();
    return [for (final d in snap.docs) Debt.fromMap({...d.data(), 'id': d.id})]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> saveDebt(Debt d) async => _write(_debts.doc(d.id).set(_fields(d.toMap())));

  @override
  Future<void> deleteDebt(String id) async => _write(_debts.doc(id).delete());

  @override
  Future<void> replaceAll({
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required List<Wallet> wallets,
    required List<ExpenseCategory> categories,
    required List<Deposit> deposits,
    List<Debt> debts = const [],
  }) async {
    final ops = <void Function(WriteBatch)>[];
    for (final c in _all) {
      for (final d in (await c.get()).docs) {
        ops.add((b) => b.delete(d.reference));
      }
    }
    for (final e in expenses) {
      ops.add((b) => b.set(_expenses.doc(), _fields(e.toMap())));
    }
    budgets.forEach((k, v) => ops.add((b) => b.set(_budgets.doc(k), {'amount': v})));
    for (final g in goals) {
      ops.add((b) => b.set(_goals.doc(), _fields(g.toMap())));
    }
    for (final w in wallets) {
      ops.add((b) => b.set(_wallets.doc(w.id), _fields(w.toMap())));
    }
    for (final c in categories) {
      ops.add((b) => b.set(_categories.doc(c.id), _fields(c.toMap())));
    }
    for (final d in deposits) {
      ops.add((b) => b.set(_deposits.doc(d.id), _fields(d.toMap())));
    }
    for (final d in debts) {
      ops.add((b) => b.set(_debts.doc(d.id), _fields(d.toMap())));
    }
    // A batch holds at most 500 writes.
    for (var i = 0; i < ops.length; i += 450) {
      final batch = _user.firestore.batch();
      for (final op in ops.skip(i).take(450)) {
        op(batch);
      }
      _write(batch.commit());
    }
  }

  /// Erases everything, profile included, and waits for the server.
  /// Used when the account is deleted, so it needs a connection.
  Future<void> deleteUserData() async {
    final refs = [
      for (final c in _all) ...(await c.get()).docs.map((d) => d.reference),
      _user,
    ];
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _user.firestore.batch();
      for (final r in refs.skip(i).take(450)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }
}
