import '../../data/repository.dart';
import '../../models/app_user.dart';
import '../../l10n/l10n.dart';

class AuthException implements Exception {
  const AuthException(this.message) : cancelled = false;

  /// The person closed the Google or Apple window: show nothing.
  const AuthException.cancelled()
      : message = '',
        cancelled = true;

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Accounts and where their data lives.
///
/// [LocalAuthBackend]: accounts and data on the phone (SQLite), used while
/// Firebase is not configured. [FirebaseAuthBackend]: Google, Apple and
/// e-mail accounts with data in Firestore.
abstract class AuthBackend {
  /// True when data is stored online.
  bool get isCloud;

  bool get supportsGoogle;
  bool get supportsApple;
  bool get supportsPasswordReset;

  /// The person still signed in from last time, if any.
  Future<AppUser?> restore();

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String currencyCode,
  });

  /// [currencyCode] is used only when this creates the account.
  Future<AppUser> signInWithGoogle({required String currencyCode});

  /// [currencyCode] is used only when this creates the account.
  Future<AppUser> signInWithApple({required String currencyCode});

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Saves name and currency.
  Future<void> update(AppUser user);

  /// Deletes the account and all its data. Required by both app stores.
  Future<void> deleteAccount(AppUser user);

  BudgetRepository repositoryFor(AppUser user);
}

class AuthValidators {
  static String? name(String? v) => (v == null || v.trim().isEmpty) ? tr('Entrez votre prénom.') : null;

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return tr('Entrez votre e-mail.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Cet e-mail n\'est pas valide.';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return tr('Entrez un mot de passe.');
    if (v.length < 6) return tr('Au moins 6 caractères.');
    return null;
  }
}
