import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/expense.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import 'expense_form_screen.dart';
import '../l10n/l10n.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = monthStart(DateTime.now());
  String? _categoryId;
  String? _walletId;

  Future<void> _delete(Expense e) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.deleteExpense(e);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(e.isRefund
            ? tr('Remboursement de {0} supprimé', [money(e.amount.abs())])
            : tr('Dépense de {0} supprimée', [money(e.amount)])),
        action: SnackBarAction(label: tr('Annuler'), onPressed: () => state.addExpense(e)),
      ));
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    if (sameDay(day, now)) return tr('Aujourd\'hui');
    if (sameDay(day, now.subtract(const Duration(days: 1)))) return tr('Hier');
    final s = longDate(day);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final eco = context.eco;
    if (_walletId != null && !state.wallets.any((w) => w.id == _walletId)) _walletId = null;
    final items = state.expensesIn(_month, categoryId: _categoryId, walletId: _walletId);
    final total = items.fold(0.0, (s, e) => s + e.amount);

    final groups = <DateTime, List<Expense>>{};
    for (final e in items) {
      groups.putIfAbsent(DateTime(e.date.year, e.date.month, e.date.day), () => []).add(e);
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenTitle(tr('Dépenses')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      MonthSelector(month: _month, onChanged: (m) => setState(() => _month = m)),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(isSingular(items.length) ? tr('{0} dépense', [items.length]) : tr('{0} dépenses', [items.length]), style: context.type.bodySmall),
                          Text(money(total), style: context.type.titleMedium?.copyWith(fontFeatures: tabular)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (state.hasSeveralWallets) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _filter(context,
                            label: tr('Tous les portefeuilles'),
                            selected: _walletId == null,
                            onTap: () => setState(() => _walletId = null)),
                        for (final w in state.wallets)
                          _filter(
                            context,
                            label: w.name,
                            icon: w.type.icon,
                            iconColor: eco.blueInk,
                            selected: _walletId == w.id,
                            onTap: () => setState(() => _walletId = _walletId == w.id ? null : w.id),
                          ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: state.hasSeveralWallets ? 8 : 14),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _filter(context, label: tr('Toutes'), selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
                      for (final cat in ExpenseCategory.visible)
                        _filter(
                          context,
                          label: cat.label,
                          icon: cat.icon,
                          iconColor: cat.color,
                          selected: _categoryId == cat.id,
                          onTap: () => setState(() => _categoryId = _categoryId == cat.id ? null : cat.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: _categoryId == null && _walletId == null
                    ? tr('Aucune dépense ce mois-ci')
                    : tr('Aucune dépense pour ce filtre'),
                message: tr('Touchez + en bas de l\'écran pour noter une dépense.'),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.list(
                children: [
                  for (final g in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(_dayLabel(g.key), style: context.type.labelMedium?.copyWith(color: eco.muted))),
                          Text(money(g.value.fold(0.0, (s, e) => s + e.amount)),
                              style: context.type.labelMedium?.copyWith(color: eco.muted, fontFeatures: tabular)),
                        ],
                      ),
                    ),
                    Grouped(
                      dividerIndent: 72,
                      children: [
                        for (final e in g.value)
                          Dismissible(
                            key: ValueKey('expense-${e.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: eco.coral,
                              alignment: AlignmentDirectional.centerEnd,
                              padding: const EdgeInsetsDirectional.only(end: 24),
                              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            ),
                            onDismissed: (_) => _delete(e),
                            child: ExpenseTile(expense: e, onTap: () => ExpenseFormScreen.open(context, e)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filter(BuildContext context,
      {required String label, IconData? icon, Color? iconColor, required bool selected, required VoidCallback onTap}) {
    final eco = context.eco;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: icon == null ? null : Icon(icon, size: 17, color: selected ? eco.onBlue : iconColor),
        label: Text(label),
        labelStyle: context.type.labelMedium?.copyWith(color: selected ? eco.onBlue : eco.ink),
        side: BorderSide(color: selected ? eco.blue : eco.hairline),
      ),
    );
  }
}
