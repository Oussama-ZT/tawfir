import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../widgets/eco_nav_bar.dart';
import '../widgets/tour.dart';
import 'dashboard_screen.dart';
import 'expense_form_screen.dart';
import 'expenses_screen.dart';
import 'planning_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Tab indexes, used by screens that link to another tab.
  static const home = 0, wallets = 1, expenses = 2, budgets = 3;

  /// Current tab. Any screen, including pushed ones, can switch it.
  static final tab = ValueNotifier<int>(home);

  /// Wallet the Wallets tab should bring to the front.
  static final focusWallet = ValueNotifier<String?>(null);

  /// Bumped by the profile to show the guided tour again.
  static final tourRequests = ValueNotifier<int>(0);

  /// Back to the tabs, on the Wallets tab, with [walletId] in front.
  static void showWallet(BuildContext context, String? walletId) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tab.value = wallets;
    focusWallet.value = walletId;
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    HomeShell.tab.value = HomeShell.home;
    HomeShell.tab.addListener(_changed);
    HomeShell.tourRequests.addListener(_replayTour);
  }

  bool _touring = false;

  /// Runs once the home screen is laid out and its budget card has settled.
  void _startTour() {
    if (_touring) return;
    _touring = true;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final session = context.read<SessionState>();
      showTour(
        context,
        homeTour,
        onDone: () {
          _touring = false;
          session.finishTour();
        },
      );
    });
  }

  void _replayTour() {
    HomeShell.tab.value = HomeShell.home;
    context.read<SessionState>().replayOthersTour();
    _startTour();
  }

  @override
  void dispose() {
    HomeShell.tab.removeListener(_changed);
    HomeShell.tourRequests.removeListener(_replayTour);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _go(int i) => HomeShell.tab.value = i;

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AppState>().loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!context.read<SessionState>().tourSeen && !_touring) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(Theme.of(context).brightness),
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: HomeShell.tab.value,
          children: [
            DashboardScreen(onNavigate: _go),
            const WalletsScreen(),
            const ExpensesScreen(),
            const PlanningScreen(),
          ],
        ),
        bottomNavigationBar: EcoNavBar(
          selected: HomeShell.tab.value,
          onSelected: _go,
          onAdd: () => ExpenseFormScreen.open(context),
          addAnchor: TourKeys.addButton,
          items: [
            EcoNavItem(Icons.home_outlined, Icons.home_rounded, tr('Accueil')),
            EcoNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('Portefeuilles')),
            EcoNavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('Dépenses'), anchor: TourKeys.expensesTab),
            EcoNavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, tr('Autres'), anchor: TourKeys.budgetsTab),
          ],
        ),
      ),
    );
  }
}
