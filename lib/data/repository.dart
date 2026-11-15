import '../models/category.dart';
import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';
import 'database.dart';

/// Where one user's expenses, budgets and goals are stored.
///
/// Two implementations: [LocalRepository] (SQLite on the phone) and
/// FirestoreRepository (the cloud, see firestore_repository.dart).
/// [AppState] only talks to this interface.
abstract class BudgetRepository {
  Future<List<Expense>> expenses();

  /// Returns the new id.
  Future<String> insertExpense(Expense e);
  Future<void> updateExpense(Expense e);
  Future<void> deleteExpense(String id);

  /// Budget per category id, plus the overall budget under 'total'.
  Future<Map<String, double>> budgets();

  /// An amount of 0 or less removes the budget.
  Future<void> setBudget(String key, double amount);

  Future<List<SavingsGoal>> goals();

  /// Returns the new id.
  Future<String> insertGoal(SavingsGoal g);
  Future<void> updateGoal(SavingsGoal g);
  Future<void> deleteGoal(String id);

  Future<List<Wallet>> wallets();

  /// Creates or updates (the id is set by the caller).
  Future<void> saveWallet(Wallet w);

  /// Deletes a wallet; its expenses move to [moveTo].
  Future<void> deleteWallet(String id, {required String moveTo});

  /// Custom categories only (defaults live in code).
  Future<List<ExpenseCategory>> categories();

  /// Creates or updates (the id is set by the caller).
  Future<void> saveCategory(ExpenseCategory c);

  /// Its expenses move to "Autre" and its budget is removed.
  Future<void> deleteCategory(String id);

  /// Money added to wallets, newest first.
  Future<List<Deposit>> deposits();

  /// Creates or updates (the id is set by the caller).
  Future<void> saveDeposit(Deposit d);
  Future<void> deleteDeposit(String id);

  /// Replaces all of the user's data (demo data, reset).
  Future<void> replaceAll({
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required List<Wallet> wallets,
    required List<ExpenseCategory> categories,
    required List<Deposit> deposits,
  });
}

/// SQLite storage for a local account.
class LocalRepository implements BudgetRepository {
  LocalRepository(this._db, String userId) : _userId = int.parse(userId);

  final AppDatabase _db;
  final int _userId;

  @override
  Future<List<Expense>> expenses() => _db.expenses(_userId);

  @override
  Future<String> insertExpense(Expense e) async => '${await _db.insertExpense(_userId, e)}';

  @override
  Future<void> updateExpense(Expense e) => _db.updateExpense(_userId, e);

  @override
  Future<void> deleteExpense(String id) => _db.deleteExpense(_userId, int.parse(id));

  @override
  Future<Map<String, double>> budgets() => _db.budgets(_userId);

  @override
  Future<void> setBudget(String key, double amount) => _db.setBudget(_userId, key, amount);

  @override
  Future<List<SavingsGoal>> goals() => _db.goals(_userId);

  @override
  Future<String> insertGoal(SavingsGoal g) async => '${await _db.insertGoal(_userId, g)}';

  @override
  Future<void> updateGoal(SavingsGoal g) => _db.updateGoal(_userId, g);

  @override
  Future<void> deleteGoal(String id) => _db.deleteGoal(_userId, int.parse(id));

  @override
  Future<List<Wallet>> wallets() => _db.wallets(_userId);

  @override
  Future<void> saveWallet(Wallet w) => _db.saveWallet(_userId, w);

  @override
  Future<void> deleteWallet(String id, {required String moveTo}) => _db.deleteWallet(_userId, id, moveTo: moveTo);

  @override
  Future<List<ExpenseCategory>> categories() => _db.categories(_userId);

  @override
  Future<void> saveCategory(ExpenseCategory c) => _db.saveCategory(_userId, c);

  @override
  Future<void> deleteCategory(String id) => _db.deleteCategory(_userId, id);

  @override
  Future<List<Deposit>> deposits() => _db.deposits(_userId);

  @override
  Future<void> saveDeposit(Deposit d) => _db.saveDeposit(_userId, d);

  @override
  Future<void> deleteDeposit(String id) => _db.deleteDeposit(_userId, id);

  @override
  Future<void> replaceAll({
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required List<Wallet> wallets,
    required List<ExpenseCategory> categories,
    required List<Deposit> deposits,
  }) =>
      _db.replaceAll(_userId,
          expenses: expenses,
          budgets: budgets,
          goals: goals,
          wallets: wallets,
          categories: categories,
          deposits: deposits);
}
