import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/currency.dart';
import '../services/auth/auth_backend.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/currency_picker.dart';
import 'categories_screen.dart';
import 'home_shell.dart';
import 'paywall_screen.dart';
import '../l10n/l10n.dart';
import '../widgets/language_picker.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _changeCurrency(BuildContext context) async {
    final session = context.read<SessionState>();
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final current = Currency.byCode(session.user!.currencyCode);
    final picked = await showCurrencyPicker(context, selected: current);
    if (picked == null || picked.code == current.code) return;
    final hadForeignWallets = app.hasForeignWallets;
    await session.setCurrency(picked);
    app.refresh();
    messenger.showSnackBar(SnackBar(
      content: Text(tr('Devise changée en {0}. Les montants enregistrés ne sont pas convertis.{1}', [picked.name, hadForeignWallets ? tr(' Vérifiez les taux de vos portefeuilles en devises.') : ''])),
    ));
  }

  Future<void> _changeName(BuildContext context) async {
    final session = context.read<SessionState>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: session.user!.name),
    );
    if (name != null && name.trim().isNotEmpty) await session.setName(name);
  }

  Future<void> _loadDemo(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await confirm(context,
        title: tr('Charger les données de démo ?'),
        message: tr('Vos dépenses, budgets et objectifs actuels seront remplacés par cinq mois d\'exemples.'),
        confirmLabel: tr('Remplacer'));
    if (ok) await app.loadDemoData();
    if (ok && context.mounted) Navigator.pop(context);
  }

  Future<void> _reset(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await confirm(context,
        title: tr('Effacer vos données ?'),
        message: tr('Toutes vos dépenses, budgets et objectifs seront supprimés. Votre compte reste actif.'),
        confirmLabel: tr('Effacer'),
        destructive: true);
    if (ok) await app.resetAll();
  }

  Future<void> _logout(BuildContext context) async {
    final session = context.read<SessionState>();
    final plan = context.read<PlanState>();
    final navigator = Navigator.of(context);
    final ok = await confirm(context,
        title: tr('Se déconnecter ?'),
        message: session.isCloud
            ? tr('Vos données restent liées à votre compte. Reconnectez-vous pour les retrouver.')
            : tr('Vos données restent sur ce téléphone. Reconnectez-vous avec votre e-mail et votre mot de passe.'),
        confirmLabel: tr('Se déconnecter'));
    if (!ok) return;
    navigator.popUntil((r) => r.isFirst);
    await plan.signOut();
    await session.logout();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final session = context.read<SessionState>();
    final plan = context.read<PlanState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: tr('Supprimer votre compte ?'),
        message: tr('Votre compte, vos dépenses, budgets et objectifs seront supprimés définitivement. Un abonnement Premium en cours doit être résilié séparément dans la boutique.'),
        confirmLabel: tr('Supprimer'),
        destructive: true);
    if (!ok) return;
    try {
      await session.deleteAccount();
      await plan.signOut();
      navigator.popUntil((r) => r.isFirst);
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final plan = context.watch<PlanState>();
    final app = context.watch<AppState>();
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final eco = context.eco;
    final currency = Currency.byCode(user.currencyCode);

    Widget row({
      required IconData icon,
      required String title,
      String? value,
      Color? color,
      required VoidCallback onTap,
      bool chevron = true,
    }) =>
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color ?? eco.muted),
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: context.type.titleSmall?.copyWith(color: color))),
                if (value != null)
                  Flexible(
                    child: Text(value,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.bodyMedium?.copyWith(color: eco.muted)),
                  ),
                if (chevron) Icon(Icons.chevron_right_rounded, color: eco.muted),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Profil'))),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          Center(child: InitialAvatar(initial: user.initial, size: 84)),
          const SizedBox(height: 14),
          Text(user.name, textAlign: TextAlign.center, style: context.type.headlineSmall),
          const SizedBox(height: 2),
          Text(user.email, textAlign: TextAlign.center, style: context.type.bodyMedium?.copyWith(color: eco.muted)),
          SectionHeader(tr('Abonnement')),
          Grouped(
            children: [
              row(
                icon: plan.plan.isFree ? Icons.workspace_premium_outlined : Icons.workspace_premium_rounded,
                title: tr('Formule'),
                value: plan.plan.isFree
                    ? tr('Starter, gratuite')
                    : plan.endsAt != null
                        ? tr('{0} jusqu\'au {1}', [plan.plan.label, fullDate(plan.endsAt!)])
                        : plan.plan.label,
                onTap: () => showPlans(context),
              ),
            ],
          ),
          SectionHeader(tr('Organisation')),
          Grouped(
            dividerIndent: 54,
            children: [
              row(
                icon: Icons.account_balance_wallet_outlined,
                title: tr('Portefeuilles'),
                value: '${app.wallets.length}',
                onTap: () => HomeShell.showWallet(context, null),
              ),
              row(
                icon: Icons.category_outlined,
                title: tr('Catégories'),
                value: app.customCategories.isEmpty
                    ? '${ExpenseCategory.defaults.length}'
                    : '${ExpenseCategory.defaults.length} + ${app.customCategories.length}',
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen())),
              ),
            ],
          ),
          SectionHeader(tr('Préférences')),
          Grouped(
            dividerIndent: 54,
            children: [
              row(
                icon: Icons.currency_exchange_rounded,
                title: tr('Devise'),
                value: currency.name,
                onTap: () => _changeCurrency(context),
              ),
              row(icon: Icons.badge_outlined, title: tr('Prénom'), value: user.name, onTap: () => _changeName(context)),
              row(
                icon: Icons.translate_rounded,
                title: tr('Langue'),
                value: session.languageChoice?.nativeName ?? '${tr('Automatique')}, ${session.language.nativeName}',
                onTap: () => showLanguagePicker(context),
              ),
              row(
                icon: Icons.tour_outlined,
                title: tr('Revoir la visite guidée'),
                onTap: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  HomeShell.tourRequests.value++;
                },
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.contrast_rounded, size: 22, color: eco.muted),
                        const SizedBox(width: 16),
                        Text(tr('Apparence'), style: context.type.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto')), icon: Icon(Icons.phone_android_rounded)),
                        ButtonSegment(value: ThemeMode.light, label: Text(tr('Clair')), icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(value: ThemeMode.dark, label: Text(tr('Sombre')), icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: {session.themeMode},
                      onSelectionChanged: (s) => session.setThemeMode(s.first),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SectionHeader(tr('Données')),
          Grouped(
            dividerIndent: 54,
            children: [
              row(
                icon: Icons.auto_awesome_outlined,
                title: tr('Charger les données de démo'),
                onTap: () => _loadDemo(context),
              ),
              row(
                icon: Icons.delete_outline_rounded,
                title: tr('Effacer mes données'),
                color: eco.coral,
                chevron: false,
                onTap: () => _reset(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Grouped(
            children: [
              row(
                icon: Icons.logout_rounded,
                title: tr('Se déconnecter'),
                color: eco.coral,
                chevron: false,
                onTap: () => _logout(context),
              ),
              row(
                icon: Icons.person_remove_outlined,
                title: tr('Supprimer mon compte'),
                color: eco.coral,
                chevron: false,
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            session.isCloud
                ? tr('Vos données sont liées à votre compte et protégées : vous seul pouvez y accéder.')
                : tr('Votre compte et vos données sont enregistrés uniquement sur ce téléphone.'),
            textAlign: TextAlign.center,
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = AuthValidators.name(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Votre prénom')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          child: Text(tr('Enregistrer')),
        ),
      ],
    );
  }
}
