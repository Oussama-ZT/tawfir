import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/firestore_repository.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
import 'auth_backend.dart';
import '../../l10n/l10n.dart';

/// Online accounts with Firebase Authentication (Google, Apple, e-mail).
/// The profile (name, currency) lives in Firestore at users/{uid}.
class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend(this._auth, this._firestore) {
    unawaited(_auth.setLanguageCode('fr'));
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool _googleReady = false;

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) => _firestore.collection('users').doc(uid);

  @override
  bool get isCloud => true;

  @override
  bool get supportsGoogle => true;

  /// Sign in with Apple is offered on Apple devices, where the App Store
  /// requires it next to Google.
  @override
  bool get supportsApple => Platform.isIOS || Platform.isMacOS;

  @override
  bool get supportsPasswordReset => true;

  @override
  Future<AppUser?> restore() async {
    final user = await _auth.authStateChanges().first;
    return user == null ? null : _loadProfile(user);
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) => _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
        return _loadProfile(cred.user!);
      });

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String currencyCode,
  }) =>
      _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        await cred.user!.updateDisplayName(name.trim());
        return _loadProfile(cred.user!, name: name.trim(), currencyCode: currencyCode);
      });

  @override
  Future<AppUser> signInWithGoogle({required String currencyCode}) => _guard(() async {
        final google = GoogleSignIn.instance;
        if (!_googleReady) {
          await google.initialize();
          _googleReady = true;
        }
        final GoogleSignInAccount account;
        try {
          account = await google.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) throw const AuthException.cancelled();
          debugPrint('Google sign-in: ${e.code} ${e.description}');
          throw AuthException(tr('La connexion avec Google a échoué. Réessayez.'));
        }
        final idToken = account.authentication.idToken;
        final cred = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
        return _loadProfile(cred.user!, currencyCode: currencyCode);
      });

  @override
  Future<AppUser> signInWithApple({required String currencyCode}) => _guard(() async {
        final provider = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        final cred = await _auth.signInWithProvider(provider);
        return _loadProfile(cred.user!, currencyCode: currencyCode);
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  @override
  Future<void> update(AppUser user) =>
      _profileDoc(user.id).set({'name': user.name, 'currency': user.currencyCode}, SetOptions(merge: true));

  @override
  Future<void> deleteAccount(AppUser user) => _guard(() async {
        final current = _auth.currentUser;
        if (current == null) return;
        await FirestoreRepository(_firestore, user.id).deleteUserData();
        await current.delete();
        await signOut();
      });

  @override
  BudgetRepository repositoryFor(AppUser user) => FirestoreRepository(_firestore, user.id);

  // ------------------------------------------------------------- helpers --

  /// Reads the profile, creating it on first sign-in. Falls back to what
  /// Firebase Auth knows when offline and never synced.
  Future<AppUser> _loadProfile(User user, {String? name, String? currencyCode}) async {
    final fallbackName = name ?? _nameFrom(user);
    final created = user.metadata.creationTime ?? DateTime.now();
    final doc = _profileDoc(user.uid);
    Map<String, dynamic>? data;
    try {
      data = (await doc.get()).data();
    } on FirebaseException catch (e) {
      debugPrint('Profile read: ${e.code}');
      try {
        data = (await doc.get(const GetOptions(source: Source.cache))).data();
      } on FirebaseException catch (_) {}
    }
    if (data == null) {
      data = {
        'name': fallbackName,
        'email': user.email ?? '',
        'currency': currencyCode ?? 'USD',
        'created_at': created.millisecondsSinceEpoch,
      };
      unawaited(doc.set(data).catchError((Object e) => debugPrint('Firestore: $e')));
    }
    return AppUser(
      id: user.uid,
      name: (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : fallbackName,
      email: user.email ?? (data['email'] as String? ?? ''),
      currencyCode: data['currency'] as String? ?? currencyCode ?? 'USD',
      createdAt: created,
    );
  }

  static String _nameFrom(User user) {
    final display = user.displayName?.trim() ?? '';
    if (display.isNotEmpty) return display.split(RegExp(r'\s+')).first;
    final email = user.email ?? '';
    if (email.contains('@')) {
      final local = email.split('@').first;
      return local.isEmpty ? tr('Vous') : local[0].toUpperCase() + local.substring(1);
    }
    return tr('Vous');
  }

  /// Turns Firebase errors into French messages people can act on.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuth: ${e.code} ${e.message}');
      if (const {'canceled', 'web-context-canceled', 'popup-closed-by-user'}.contains(e.code)) {
        throw const AuthException.cancelled();
      }
      throw AuthException(switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => tr('E-mail ou mot de passe incorrect.'),
        'email-already-in-use' => tr('Un compte existe déjà avec cet e-mail. Connectez-vous.'),
        'invalid-email' => tr('Cet e-mail n\'est pas valide.'),
        'weak-password' => tr('Mot de passe trop faible : au moins 6 caractères.'),
        'network-request-failed' => tr('Pas de connexion internet. Réessayez.'),
        'too-many-requests' => tr('Trop de tentatives. Réessayez dans quelques minutes.'),
        'user-disabled' => tr('Ce compte a été désactivé.'),
        'account-exists-with-different-credential' =>
          tr('Un compte existe déjà avec cet e-mail, avec une autre méthode de connexion.'),
        'requires-recent-login' => tr('Pour des raisons de sécurité, reconnectez-vous puis réessayez.'),
        'operation-not-allowed' => tr('Ce mode de connexion n\'est pas encore activé.'),
        _ => tr('La connexion a échoué. Réessayez.'),
      });
    }
  }
}
