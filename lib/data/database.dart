import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/category.dart';
import '../models/deposit.dart';
import '../models/expense.dart';
import '../models/savings_goal.dart';
import '../models/wallet.dart';

/// Local SQLite storage. All data stays on the device, scoped per account.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final path = join(await getDatabasesPath(), 'ecobudget.db');
    final db = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL DEFAULT 0,
            amount REAL NOT NULL,
            category_id TEXT NOT NULL,
            date INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
          CREATE TABLE budgets (
            user_id INTEGER NOT NULL DEFAULT 0,
            category_id TEXT NOT NULL,
            amount REAL NOT NULL,
            PRIMARY KEY (user_id, category_id)
          )''');
        await db.execute('''
          CREATE TABLE goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL DEFAULT 0,
            name TEXT NOT NULL,
            target REAL NOT NULL,
            saved REAL NOT NULL DEFAULT 0,
            deadline INTEGER,
            created_at INTEGER NOT NULL
          )''');
        await _createV2Tables(db);
        await _upgradeToV3(db);
        await _upgradeToV4(db);
        await _upgradeToV5(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE expenses ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE goals ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
          await db.execute('DROP INDEX IF EXISTS idx_expenses_date');
          await db.execute('''
            CREATE TABLE budgets_v2 (
              user_id INTEGER NOT NULL DEFAULT 0,
              category_id TEXT NOT NULL,
              amount REAL NOT NULL,
              PRIMARY KEY (user_id, category_id)
            )''');
          await db.execute('INSERT INTO budgets_v2 (user_id, category_id, amount) SELECT 0, category_id, amount FROM budgets');
          await db.execute('DROP TABLE budgets');
          await db.execute('ALTER TABLE budgets_v2 RENAME TO budgets');
          await _createV2Tables(db);
        }
        if (oldVersion < 3) await _upgradeToV3(db);
        if (oldVersion < 4) await _upgradeToV4(db);
        if (oldVersion < 5) await _upgradeToV5(db);
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('CREATE INDEX idx_expenses_user_date ON expenses(user_id, date)');
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        currency TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  /// Version 3: wallets and custom categories.
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute('ALTER TABLE expenses ADD COLUMN wallet_id TEXT');
    await db.execute('''
      CREATE TABLE wallets (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        label TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL
      )''');
  }

  /// Version 4: wallets in other currencies.
  static Future<void> _upgradeToV4(Database db) async {
    await db.execute('ALTER TABLE wallets ADD COLUMN currency TEXT');
    await db.execute('ALTER TABLE wallets ADD COLUMN rate REAL');
    await db.execute('ALTER TABLE expenses ADD COLUMN original_amount REAL');
    await db.execute('ALTER TABLE expenses ADD COLUMN original_currency TEXT');
  }

  /// Version 5: money added to wallets.
  static Future<void> _upgradeToV5(Database db) async {
    await db.execute('''
      CREATE TABLE deposits (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        wallet_id TEXT NOT NULL,
        amount REAL NOT NULL,
        date INTEGER NOT NULL,
        kind TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        source_wallet_id TEXT,
        source_amount REAL
      )''');
  }

  static const _userTables = ['expenses', 'budgets', 'goals', 'wallets', 'categories', 'deposits'];

  // ---------------------------------------------------------------- users --

  Future<int> userCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;

  Future<int> insertUser({
    required String name,
    required String email,
    required String passwordHash,
    required String salt,
    required String currency,
  }) =>
      _db.insert('users', {
        'name': name,
        'email': email,
        'password_hash': passwordHash,
        'salt': salt,
        'currency': currency,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// Returns the user row including password_hash and salt.
  Future<Map<String, Object?>?> userRowByEmail(String email) async {
    final rows = await _db.query('users', where: 'email = ?', whereArgs: [email], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<AppUser?> userById(int id) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<void> updateUser(AppUser user) => _db.update(
        'users',
        {'name': user.name, 'currency': user.currencyCode},
        where: 'id = ?',
        whereArgs: [int.parse(user.id)],
      );

  /// Removes an account and everything it owns.
  Future<void> deleteUser(int userId) => _db.transaction((txn) async {
        for (final table in _userTables) {
          await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
        }
        await txn.delete('users', where: 'id = ?', whereArgs: [userId]);
      });

  /// Gives data created before accounts existed to the first account.
  Future<void> claimUnownedData(int userId) async {
    for (final table in ['expenses', 'budgets', 'goals']) {
      await _db.update(table, {'user_id': userId}, where: 'user_id = 0');
    }
  }

  // ------------------------------------------------------------- settings --

  Future<String?> setting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ------------------------------------------------------------- expenses --

  Future<List<Expense>> expenses(int userId) async {
    final rows = await _db.query('expenses',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC, id DESC');
    return rows.map(Expense.fromMap).toList();
  }

  Future<int> insertExpense(int userId, Expense e) =>
      _db.insert('expenses', {...e.toMap()..remove('id'), 'user_id': userId});

  Future<void> updateExpense(int userId, Expense e) => _db.update('expenses', e.toMap(),
      where: 'id = ? AND user_id = ?', whereArgs: [e.id, userId]);

  Future<void> deleteExpense(int userId, int id) =>
      _db.delete('expenses', where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);

  // -------------------------------------------------------------- budgets --

  Future<Map<String, double>> budgets(int userId) async {
    final rows = await _db.query('budgets', where: 'user_id = ?', whereArgs: [userId]);
    return {for (final r in rows) r['category_id'] as String: (r['amount'] as num).toDouble()};
  }

  Future<void> setBudget(int userId, String key, double amount) async {
    if (amount <= 0) {
      await _db.delete('budgets', where: 'user_id = ? AND category_id = ?', whereArgs: [userId, key]);
    } else {
      await _db.insert('budgets', {'user_id': userId, 'category_id': key, 'amount': amount},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ---------------------------------------------------------------- goals --

  Future<List<SavingsGoal>> goals(int userId) async {
    final rows = await _db.query('goals', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at ASC');
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<int> insertGoal(int userId, SavingsGoal g) =>
      _db.insert('goals', {...g.toMap()..remove('id'), 'user_id': userId});

  Future<void> updateGoal(int userId, SavingsGoal g) =>
      _db.update('goals', g.toMap(), where: 'id = ? AND user_id = ?', whereArgs: [g.id, userId]);

  Future<void> deleteGoal(int userId, int id) =>
      _db.delete('goals', where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);

  // -------------------------------------------------------------- wallets --

  Future<List<Wallet>> wallets(int userId) async {
    final rows = await _db.query('wallets', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at ASC');
    return rows.map(Wallet.fromMap).toList();
  }

  Future<void> saveWallet(int userId, Wallet w) =>
      _db.insert('wallets', {...w.toMap(), 'user_id': userId}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Deletes a wallet and moves its expenses to [moveTo].
  Future<void> deleteWallet(int userId, String id, {required String moveTo}) => _db.transaction((txn) async {
        await txn.update('expenses', {'wallet_id': moveTo},
            where: 'user_id = ? AND wallet_id = ?', whereArgs: [userId, id]);
        await txn.delete('wallets', where: 'user_id = ? AND id = ?', whereArgs: [userId, id]);
      });

  // ------------------------------------------------------------- deposits --

  Future<List<Deposit>> deposits(int userId) async {
    final rows = await _db.query('deposits', where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
    return rows.map(Deposit.fromMap).toList();
  }

  Future<void> saveDeposit(int userId, Deposit d) =>
      _db.insert('deposits', {...d.toMap(), 'user_id': userId}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteDeposit(int userId, String id) =>
      _db.delete('deposits', where: 'user_id = ? AND id = ?', whereArgs: [userId, id]);

  // ----------------------------------------------------------- categories --

  Future<List<ExpenseCategory>> categories(int userId) async {
    final rows = await _db.query('categories', where: 'user_id = ?', whereArgs: [userId], orderBy: 'label ASC');
    return rows.map(ExpenseCategory.fromMap).toList();
  }

  Future<void> saveCategory(int userId, ExpenseCategory c) =>
      _db.insert('categories', {...c.toMap(), 'user_id': userId}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Deletes a custom category: its expenses go to "Autre", its budget is removed.
  Future<void> deleteCategory(int userId, String id) => _db.transaction((txn) async {
        await txn.update('expenses', {'category_id': ExpenseCategory.otherId},
            where: 'user_id = ? AND category_id = ?', whereArgs: [userId, id]);
        await txn.delete('budgets', where: 'user_id = ? AND category_id = ?', whereArgs: [userId, id]);
        await txn.delete('categories', where: 'user_id = ? AND id = ?', whereArgs: [userId, id]);
      });

  /// Replaces all of one user's data in a single transaction (demo data, reset).
  Future<void> replaceAll(
    int userId, {
    required List<Expense> expenses,
    required Map<String, double> budgets,
    required List<SavingsGoal> goals,
    required List<Wallet> wallets,
    required List<ExpenseCategory> categories,
    required List<Deposit> deposits,
  }) async {
    await _db.transaction((txn) async {
      for (final table in _userTables) {
        await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
      final batch = txn.batch();
      for (final e in expenses) {
        batch.insert('expenses', {...e.toMap()..remove('id'), 'user_id': userId});
      }
      budgets.forEach((k, v) => batch.insert('budgets', {'user_id': userId, 'category_id': k, 'amount': v}));
      for (final g in goals) {
        batch.insert('goals', {...g.toMap()..remove('id'), 'user_id': userId});
      }
      for (final w in wallets) {
        batch.insert('wallets', {...w.toMap(), 'user_id': userId});
      }
      for (final c in categories) {
        batch.insert('categories', {...c.toMap(), 'user_id': userId});
      }
      for (final d in deposits) {
        batch.insert('deposits', {...d.toMap(), 'user_id': userId});
      }
      await batch.commit(noResult: true);
    });
  }
}
