import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'data/database.dart';
import 'firebase_options.dart';
import 'l10n/l10n.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth/auth_backend.dart';
import 'services/auth/firebase_auth_backend.dart';
import 'services/auth/local_auth_backend.dart';
import 'services/subscription_service.dart';
import 'state/app_state.dart';
import 'state/plan_state.dart';
import 'state/session_state.dart';
import 'theme/app_theme.dart';
import 'widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting();

  final db = await AppDatabase.open();
  final AuthBackend auth = await _firebaseReady()
      ? FirebaseAuthBackend(FirebaseAuth.instance, FirebaseFirestore.instance)
      : LocalAuthBackend(db);
  final session = SessionState(auth, db);
  final subscriptions = await SubscriptionService.create();
  await session.restore();

  runApp(MultiProvider(
    providers: [
      Provider.value(value: subscriptions),
      ChangeNotifierProvider.value(value: session),
    ],
    child: const TawfirApp(),
  ));
}

/// Online mode once `flutterfire configure` has generated the real
/// firebase_options.dart; local mode (phone only) until then.
Future<bool> _firebaseReady() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    return true;
  } catch (e) {
    debugPrint('Mode local, Firebase non configuré : $e');
    return false;
  }
}

class TawfirApp extends StatelessWidget {
  const TawfirApp({super.key});

  /// First launch: the three-step introduction. Then the sign-in screen
  /// until someone is signed in, then their data.
  ///
  /// The user's [AppState] and [PlanState] are provided above [MaterialApp]
  /// so that every route (expense form, profile, sheets) can read them.
  /// Signing in or out swaps the whole app, which also resets navigation.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final user = session.user;
    final language = session.language;
    setAppLanguage(language);
    final app = MaterialApp(
      // Texts are looked up when built: a new language rebuilds everything.
      key: ValueKey('lang-${language.name}'),
      title: 'Tawfir',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: session.themeMode,
      locale: language.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => _WideLayout(child: child!),
      home: user != null
          ? const HomeShell()
          : session.introSeen
              ? const AuthScreen()
              : const OnboardingScreen(),
    );
    if (user == null) return app;
    return MultiProvider(
      key: ValueKey('user-${user.id}'),
      providers: [
        ChangeNotifierProvider(
          create: (c) => PlanState(c.read<SubscriptionService>(), accountId: session.isCloud ? user.id : null)..load(),
        ),
        // AppState follows the plan so it can freeze what the plan no longer includes.
        ChangeNotifierProxyProvider<PlanState, AppState>(
          create: (_) => AppState(session.repository())..load(),
          update: (_, plan, app) => app!..setPlan(plan.plan),
        ),
      ],
      child: app,
    );
  }
}

/// On wide screens (tablets in landscape, desktop windows), the app keeps a
/// phone-like column in the middle of the backdrop instead of stretching
/// cards and text across the whole width. Layouts measuring the screen see
/// the column's width.
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.child});

  final Widget child;

  static const _maxWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= _maxWidth + 80) return child;
    return GlowBackdrop(
      child: Center(
        child: SizedBox(
          width: _maxWidth,
          child: MediaQuery(
            data: media.copyWith(size: Size(_maxWidth, media.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
