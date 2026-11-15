import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../data/database.dart';
import '../l10n/l10n.dart';
import '../data/repository.dart';
import '../models/app_user.dart';
import '../models/currency.dart';
import '../services/auth/auth_backend.dart';
import '../utils/format.dart';

/// Who is signed in. The rest of the app only exists while [user] is set.
class SessionState extends ChangeNotifier {
  SessionState(this._auth, this._device);

  final AuthBackend _auth;

  /// Phone-level settings (intro already seen), whatever the account type.
  final AppDatabase _device;
  static const _introKey = 'intro_seen';
  static const _themeKey = 'theme_mode';
  static const _tourKey = 'tour_seen';
  static const _languageKey = 'language';

  AppUser? _user;
  bool _introSeen = true;
  ThemeMode _themeMode = ThemeMode.system;

  /// Light, dark, or following the phone. Kept on the phone.
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _device.setSetting(_themeKey, mode == ThemeMode.system ? null : mode.name);
  }

  AppUser? get user => _user;

  /// True when accounts and data are online (Firebase configured).
  bool get isCloud => _auth.isCloud;
  bool get supportsGoogle => _auth.supportsGoogle;
  bool get supportsApple => _auth.supportsApple;
  bool get supportsPasswordReset => _auth.supportsPasswordReset;

  /// False only on the very first launch, until the introduction is closed.
  bool get introSeen => _introSeen;

  bool _tourSeen = true;

  AppLanguage? _languageChoice;

  /// The language chosen in the app; null follows the phone.
  AppLanguage? get languageChoice => _languageChoice;

  /// The language the app is shown in.
  AppLanguage get language => _languageChoice ?? AppLanguage.system;

  Future<void> setLanguage(AppLanguage? l) async {
    if (l == _languageChoice) return;
    _languageChoice = l;
    notifyListeners();
    await _device.setSetting(_languageKey, l?.name);
  }

  /// False until the guided tour of the home screen has been shown once.
  bool get tourSeen => _tourSeen;

  Future<void> finishTour() async {
    _tourSeen = true;
    await _device.setSetting(_tourKey, '1');
  }

  BudgetRepository repository() => _auth.repositoryFor(_user!);

  Future<void> restore() async {
    // Phones that already have a local account skip the introduction.
    _introSeen = await _device.setting(_introKey) == '1' || await _device.userCount() > 0;
    _tourSeen = await _device.setting(_tourKey) == '1';
    _languageChoice = AppLanguage.byCode(await _device.setting(_languageKey));
    final theme = await _device.setting(_themeKey);
    _themeMode = ThemeMode.values.firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system);
    try {
      _setUser(await _auth.restore());
    } catch (e) {
      debugPrint('Session restore: $e');
      _setUser(null);
    }
  }

  Future<void> finishIntro() async {
    _introSeen = true;
    notifyListeners();
    await _device.setSetting(_introKey, '1');
  }

  Future<void> login(String email, String password) async =>
      _setUser(await _auth.signIn(email: email, password: password));

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required Currency currency,
  }) async =>
      _setUser(await _auth.register(name: name, email: email, password: password, currencyCode: currency.code));

  Future<void> signInWithGoogle(Currency defaultCurrency) async =>
      _setUser(await _auth.signInWithGoogle(currencyCode: defaultCurrency.code));

  Future<void> signInWithApple(Currency defaultCurrency) async =>
      _setUser(await _auth.signInWithApple(currencyCode: defaultCurrency.code));

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  Future<void> logout() async {
    await _auth.signOut();
    _setUser(null);
  }

  Future<void> deleteAccount() async {
    await _auth.deleteAccount(_user!);
    _setUser(null);
  }

  Future<void> setCurrency(Currency c) => _save(_user!.copyWith(currencyCode: c.code));

  Future<void> setName(String name) => _save(_user!.copyWith(name: name.trim()));

  Future<void> _save(AppUser updated) async {
    await _auth.update(updated);
    _setUser(updated);
  }

  void _setUser(AppUser? u) {
    _user = u;
    if (u != null) activeCurrency = Currency.byCode(u.currencyCode);
    notifyListeners();
  }
}
