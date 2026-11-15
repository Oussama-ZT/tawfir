import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../data/database.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
import 'auth_backend.dart';
import '../../l10n/l10n.dart';

/// Local accounts: credentials never leave the phone. Passwords are stored as
/// a salted, iterated SHA-256 hash, never in clear text. Used while Firebase
/// is not configured.
class LocalAuthBackend implements AuthBackend {
  LocalAuthBackend(this._db);

  final AppDatabase _db;
  static const _sessionKey = 'session_user_id';
  static const _iterations = 20000;

  @override
  bool get isCloud => false;

  @override
  bool get supportsGoogle => false;

  @override
  bool get supportsApple => false;

  @override
  bool get supportsPasswordReset => false;

  @override
  Future<AppUser> signInWithGoogle({required String currencyCode}) =>
      throw AuthException(tr('La connexion avec Google n\'est pas encore activée dans cette version.'));

  @override
  Future<AppUser> signInWithApple({required String currencyCode}) =>
      throw AuthException(tr('La connexion avec Apple n\'est pas encore activée dans cette version.'));

  @override
  Future<void> sendPasswordReset(String email) => throw AuthException(
      tr('Sur un compte enregistré sur ce téléphone, le mot de passe ne peut pas être réinitialisé.'));

  @override
  BudgetRepository repositoryFor(AppUser user) => LocalRepository(_db, user.id);

  @override
  Future<void> deleteAccount(AppUser user) async {
    await _db.deleteUser(int.parse(user.id));
    await signOut();
  }

  @override
  Future<AppUser?> restore() async {
    final id = int.tryParse(await _db.setting(_sessionKey) ?? '');
    return id == null ? null : _db.userById(id);
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String currencyCode,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (await _db.userRowByEmail(normalized) != null) {
      throw AuthException(tr('Un compte existe déjà avec cet e-mail. Connectez-vous.'));
    }
    final isFirst = await _db.userCount() == 0;
    final salt = newSalt();
    final id = await _db.insertUser(
      name: name.trim(),
      email: normalized,
      passwordHash: hashPassword(password, salt),
      salt: salt,
      currency: currencyCode,
    );
    if (isFirst) await _db.claimUnownedData(id);
    await _db.setSetting(_sessionKey, '$id');
    return (await _db.userById(id))!;
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final row = await _db.userRowByEmail(email.trim().toLowerCase());
    if (row == null) {
      throw AuthException(tr('Aucun compte avec cet e-mail sur ce téléphone. Créez un compte.'));
    }
    final expected = row['password_hash'] as String;
    if (!_constantTimeEquals(hashPassword(password, row['salt'] as String), expected)) {
      throw AuthException(tr('Mot de passe incorrect.'));
    }
    await _db.setSetting(_sessionKey, '${row['id']}');
    return AppUser.fromMap(row);
  }

  @override
  Future<void> signOut() => _db.setSetting(_sessionKey, null);

  @override
  Future<void> update(AppUser user) => _db.updateUser(user);

  // ------------------------------------------------------------- helpers --

  static String newSalt() {
    final rnd = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static String hashPassword(String password, String salt) {
    final saltBytes = utf8.encode(salt);
    var digest = sha256.convert([...saltBytes, ...utf8.encode(password)]).bytes;
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert([...digest, ...saltBytes]).bytes;
    }
    return base64.encode(digest);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
