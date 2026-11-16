import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/debt.dart';
import '../models/plan.dart';
import '../models/wallet.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/ids.dart';
import '../widgets/common.dart';
import '../l10n/l10n.dart';
import 'paywall_screen.dart';

/// Lets a debt change through on Pro and Premium; on Starter, opens the
/// plans screen instead. Debts made before a downgrade stay visible but
/// frozen (only deleting them stays possible, like a frozen wallet).
Future<bool> requireDebts(BuildContext context) {
  if (context.read<PlanState>().canUseDebts) return Future.value(true);
  final frozen = context.read<AppState>().debts.isNotEmpty;
  return requirePlan(
    context,
    allowed: false,
    needed: Plan.pro,
    reason: frozen
        ? tr(
            'Vos dettes sont gelées : votre formule actuelle ne les inclut plus. Elles restent consultables, et Pro permet de les modifier de nouveau.',
          )
        : tr('Avec Pro, notez l\'argent que vous prêtez ou empruntez et suivez ce qui reste à rendre.'),
  );
}

/// Money lent and borrowed: what people owe me, what I owe them.
class DebtsView extends StatelessWidget {
  const DebtsView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final allowed = context.watch<PlanState>().canUseDebts;
    final now = DateTime.now();
    final open = app.debts.where((d) => !d.isSettled).toList()
      // Late ones first, then by due date, then the most recent.
      ..sort((a, b) {
        final late = (b.isOverdue(now) ? 1 : 0) - (a.isOverdue(now) ? 1 : 0);
        if (late != 0) return late;
        if (a.dueDate != null || b.dueDate != null) {
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        }
        return b.date.compareTo(a.date);
      });
    final settled = app.debts.where((d) => d.isSettled).toList()..sort((a, b) => b.date.compareTo(a.date));

    if (app.debts.isEmpty && !allowed) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: tr('Prêts et emprunts'),
        message: tr('Avec Pro, notez l\'argent que vous prêtez ou empruntez et suivez ce qui reste à rendre.'),
        action: FilledButton(onPressed: () => requireDebts(context), child: Text(tr('Voir les formules'))),
      );
    }

    if (app.debts.isEmpty) {
      return EmptyState(
        icon: Icons.handshake_outlined,
        title: tr('Prêts et emprunts'),
        message: tr(
          'Notez l\'argent que vous prêtez ou empruntez : Tawfir suit ce qui reste à rendre et met à jour le portefeuille utilisé.',
        ),
        action: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () => showDebtForm(context, direction: DebtDirection.lent),
              child: Text(tr('J\'ai prêté')),
            ),
            FilledButton.tonal(
              onPressed: () => showDebtForm(context, direction: DebtDirection.borrowed),
              child: Text(tr('J\'ai emprunté')),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (!allowed) ...[const _FrozenNote(), const SizedBox(height: 12)],
        Row(
          children: [
            Expanded(
              child: _Total(label: tr('On vous doit'), amount: app.owedToMe, color: context.eco.leaf),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Total(label: tr('Vous devez'), amount: app.owedByMe, color: context.eco.coral),
            ),
          ],
        ),
        if (open.isNotEmpty) ...[
          _Heading(tr('En cours')),
          Grouped(dividerIndent: 74, children: [for (final d in open) _DebtTile(debt: d)]),
        ],
        if (settled.isNotEmpty) ...[
          _Heading(tr('Réglées')),
          Grouped(dividerIndent: 74, children: [for (final d in settled) _DebtTile(debt: d)]),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 0),
          child: Text(
            tr('Un prêt ou un emprunt n\'est ni une dépense ni un revenu : il ne compte pas dans votre budget.'),
            style: context.type.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Shown on Starter for debts made with Pro or Premium.
class _FrozenNote extends StatelessWidget {
  const _FrozenNote();

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 8),
      decoration: eco.glass(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: eco.muted, size: 20),
              const SizedBox(width: 10),
              Text(tr('Dettes gelées'), style: context.type.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text(
              tr('Votre formule ne les inclut plus. Elles restent consultables, mais plus de remboursements ni de modifications.'),
              style: context.type.bodyMedium?.copyWith(color: eco.muted),
            ),
          ),
          TextButton(
            onPressed: () => showPlans(context, suggested: Plan.pro),
            child: Text(tr('Les réactiver avec {0}', [Plan.pro.label])),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 22, 4, 10),
    child: Text(text, style: context.type.titleMedium),
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.amount, required this.color});

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
      decoration: eco.glass(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.bodyMedium?.copyWith(color: eco.muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              money(amount),
              style: context.type.titleLarge?.copyWith(fontFeatures: tabular, color: amount > 0 ? color : eco.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Initial of the person, tinted by who owes whom.
class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.debt, this.size = 44});

  final Debt debt;
  final double size;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final color = debt.isSettled ? eco.muted : (debt.isLent ? eco.leaf : eco.coral);
    final name = debt.person.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: context.type.titleMedium?.copyWith(color: color, fontSize: size * 0.42),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final now = DateTime.now();
    final color = debt.isLent ? eco.leaf : eco.coral;
    final late = debt.isOverdue(now);
    final due = debt.dueDate;
    final subtitle = debt.isSettled
        ? tr('Réglée')
        : [
            debt.isLent ? tr('Vous doit') : tr('Vous lui devez'),
            if (due != null) late ? tr('échéance dépassée le {0}', [shortDate(due)]) : tr('avant le {0}', [shortDate(due)]),
          ].join(', ');

    return InkWell(
      onTap: () => showDebtSheet(context, debt),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
        child: Row(
          children: [
            _PersonAvatar(debt: debt),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(debt.person, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.type.bodySmall?.copyWith(color: late ? eco.coral : null)),
                  if (!debt.isSettled && debt.repaid > 0) ...[const SizedBox(height: 8), _RepaidBar(debt: debt, height: 4)],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(debt.isSettled ? debt.total : debt.remaining),
                  style: context.type.titleSmall?.copyWith(
                    fontFeatures: tabular,
                    color: debt.isSettled ? eco.muted : color,
                    decoration: debt.isSettled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (!debt.isSettled && debt.repaid > 0) Text(tr('sur {0}', [money(debt.total)]), style: context.type.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RepaidBar extends StatelessWidget {
  const _RepaidBar({required this.debt, this.height = 6});

  final Debt debt;
  final double height;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: debt.progress,
        minHeight: height,
        backgroundColor: eco.surfaceSunken,
        color: debt.isSettled ? eco.muted : (debt.isLent ? eco.leaf : eco.coral),
      ),
    );
  }
}

// ------------------------------------------------------------ detail sheet --

/// Everything about one debt: what is left, its history, and the actions.
Future<void> showDebtSheet(BuildContext context, Debt debt) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _DebtSheet(debtId: debt.id),
);

class _DebtSheet extends StatelessWidget {
  const _DebtSheet({required this.debtId});

  final String debtId;

  Future<void> _onMenu(BuildContext context, Debt debt, String action) async {
    final app = context.read<AppState>();
    if (action == 'edit') {
      await showDebtForm(context, debt: debt);
    } else if (action == 'delete') {
      final ok = await confirm(
        context,
        title: tr('Supprimer la dette avec {0} ?', [debt.person]),
        message: tr(
          'Son historique et les mouvements de portefeuille qu\'elle a créés seront supprimés : les soldes redeviennent comme avant.',
        ),
        confirmLabel: tr('Supprimer'),
        destructive: true,
      );
      if (ok) await app.deleteDebt(debt);
    }
  }

  Future<void> _removeEntry(BuildContext context, Debt debt, DebtEntry e) async {
    final app = context.read<AppState>();
    if (!await requireDebts(context) || !context.mounted) return;
    final ok = await confirm(
      context,
      title: tr('Supprimer ce mouvement ?'),
      message: tr('Ce qui reste à rendre et le portefeuille concerné seront recalculés sans lui.'),
      confirmLabel: tr('Supprimer'),
      destructive: true,
    );
    if (ok) await app.removeDebtEntry(debt, e);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final allowed = context.watch<PlanState>().canUseDebts;
    final debt = app.debts.where((d) => d.id == debtId).firstOrNull;
    if (debt == null) {
      // Deleted from this sheet: close it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox(height: 120);
    }
    final eco = context.eco;
    final color = debt.isLent ? eco.leaf : eco.coral;
    final due = debt.dueDate;
    final late = debt.isOverdue(DateTime.now());

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 8, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              _PersonAvatar(debt: debt, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt.person, style: context.type.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(debt.isLent ? tr('Vous lui avez prêté') : tr('Vous lui avez emprunté'), style: context.type.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Options'),
                icon: Icon(Icons.more_vert_rounded, color: eco.muted),
                onSelected: (a) => _onMenu(context, debt, a),
                itemBuilder: (_) => [
                  if (allowed) PopupMenuItem(value: 'edit', child: Text(tr('Modifier'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Supprimer'))),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 22),
                Text(
                  debt.isSettled
                      ? tr('Dette réglée')
                      : debt.isLent
                      ? tr('{0} vous doit', [debt.person])
                      : tr('Vous devez à {0}', [debt.person]),
                  style: context.type.bodyMedium?.copyWith(color: eco.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  money(debt.isSettled ? debt.total : debt.remaining),
                  style: context.type.displaySmall?.copyWith(fontFeatures: tabular, color: debt.isSettled ? eco.muted : color),
                ),
                const SizedBox(height: 14),
                _RepaidBar(debt: debt),
                const SizedBox(height: 8),
                Text(tr('Rendu : {0} sur {1}', [money(debt.repaid), money(debt.total)]), style: context.type.bodySmall),
                if (due != null && !debt.isSettled) ...[
                  const SizedBox(height: 4),
                  Text(
                    late ? tr('Échéance dépassée : {0}', [longDate(due)]) : tr('Échéance : {0}', [longDate(due)]),
                    style: context.type.bodySmall?.copyWith(color: late ? eco.coral : null),
                  ),
                ],
                if (debt.note.isNotEmpty) ...[const SizedBox(height: 10), Text(debt.note, style: context.type.bodyMedium)],
                const SizedBox(height: 20),
                if (!allowed) const _FrozenNote(),
                if (allowed && !debt.isSettled)
                  FilledButton.icon(
                    onPressed: () => showDebtEntryForm(context, debt, DebtEntryKind.repayment),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(debt.isLent ? tr('Remboursement reçu') : tr('Rembourser')),
                  ),
                if (allowed)
                  TextButton.icon(
                    onPressed: () => showDebtEntryForm(context, debt, DebtEntryKind.more),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(debt.isLent ? tr('Prêter encore') : tr('Emprunter encore')),
                  ),
                const SizedBox(height: 12),
                Text(tr('Historique'), style: context.type.titleMedium),
                const SizedBox(height: 8),
                for (final e in debt.entries.reversed)
                  _EntryRow(debt: debt, entry: e, onRemove: allowed ? () => _removeEntry(context, debt, e) : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.debt, required this.entry, required this.onRemove});

  final Debt debt;
  final DebtEntry entry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final app = context.read<AppState>();
    final title = switch (entry.kind) {
      DebtEntryKind.start => debt.isLent ? tr('Prêt') : tr('Emprunt'),
      DebtEntryKind.more => debt.isLent ? tr('Prêt supplémentaire') : tr('Emprunt supplémentaire'),
      DebtEntryKind.repayment => tr('Remboursement'),
    };
    final wallet = app.wallets.where((w) => w.id == entry.walletId).firstOrNull;
    final effect = debt.walletEffect(entry);
    final details = [shortDate(entry.date), wallet?.name ?? tr('hors portefeuille'), if (entry.note.isNotEmpty) entry.note].join(', ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // The first amount is changed from "Modifier"; the others can be removed.
      onTap: entry.kind == DebtEntryKind.start ? null : onRemove,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              entry.raises ? Icons.north_east_rounded : Icons.south_west_rounded,
              size: 20,
              color: entry.raises ? eco.muted : (debt.isLent ? eco.leaf : eco.coral),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.type.titleSmall),
                  Text(details, style: context.type.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(
              // Shown as it moved the wallet: money in is "+".
              '${effect < 0 ? '−' : '+'}${money(entry.amount)}',
              style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: effect > 0 ? eco.leaf : null),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ forms --

/// Which wallet the money comes from or goes to, or none.
class _WalletChoice extends StatelessWidget {
  const _WalletChoice({required this.out, required this.walletId, required this.onChanged});

  /// True when the money leaves the wallet.
  final bool out;
  final String? walletId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wallets = <Wallet>[
      ...app.debtWallets,
      // Keep an older choice visible even if that wallet is no longer offered.
      ...app.wallets.where((w) => w.id == walletId && !app.debtWallets.contains(w)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(out ? tr('Pris dans') : tr('Reçu dans'), style: context.type.titleSmall),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in wallets)
              ChoiceChip(
                label: Text(w.name),
                avatar: Icon(w.type.icon, size: 18),
                selected: walletId == w.id,
                onSelected: (_) => onChanged(w.id),
              ),
            ChoiceChip(label: Text(tr('Aucun portefeuille')), selected: walletId == null, onSelected: (_) => onChanged(null)),
          ],
        ),
        if (walletId == null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 0),
            child: Text(
              tr('Aucun solde ne change : pour une dette d\'avant l\'app, ou de l\'argent hors de vos portefeuilles.'),
              style: context.type.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.date, required this.onTap, this.onClear, this.icon = Icons.calendar_today_outlined});

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Material(
      color: eco.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: eco.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(icon, color: eco.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.type.bodySmall),
                    Text(date == null ? tr('Aucune date') : longDate(date!), style: context.type.titleSmall),
                  ],
                ),
              ),
              if (onClear != null && date != null)
                IconButton(tooltip: tr('Retirer'), onPressed: onClear, icon: const Icon(Icons.close_rounded))
              else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

Future<DateTime?> _pickPast(BuildContext context, DateTime initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: DateTime(now.year - 10),
    lastDate: now,
  );
}

String _amountText(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

/// Creates a debt ([direction] preselected) or edits [debt].
/// Pro and Premium only (see [requireDebts]).
Future<void> showDebtForm(BuildContext context, {Debt? debt, DebtDirection? direction}) async {
  if (!await requireDebts(context) || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DebtForm(debt: debt, direction: direction ?? debt?.direction ?? DebtDirection.lent),
  );
}

class _DebtForm extends StatefulWidget {
  const _DebtForm({this.debt, required this.direction});

  final Debt? debt;
  final DebtDirection direction;

  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late DebtDirection _direction;
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  DateTime? _due;
  String? _walletId;
  bool _saving = false;

  bool get _isEdit => widget.debt != null;

  @override
  void initState() {
    super.initState();
    final d = widget.debt;
    final start = d?.start;
    final app = context.read<AppState>();
    _direction = widget.direction;
    _person = TextEditingController(text: d?.person ?? '');
    _amount = TextEditingController(text: start == null ? '' : _amountText(start.amount));
    _note = TextEditingController(text: d?.note ?? '');
    _date = start?.date ?? DateTime.now();
    _due = d?.dueDate;
    final preferred = app.debtWallets.where((w) => w.id == app.defaultWallet.id).firstOrNull ?? app.debtWallets.firstOrNull;
    _walletId = d == null ? preferred?.id : start?.walletId;
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime(now.year, now.month + 1, now.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      helpText: tr('Date à laquelle l\'argent doit être rendu'),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final amount = parseAmount(_amount.text)!;
    final existing = widget.debt;
    final start = existing?.start;
    final startEntry = DebtEntry(id: start?.id ?? newId('d'), kind: DebtEntryKind.start, amount: amount, date: _date, walletId: _walletId);
    final debt = existing == null
        ? Debt(
            id: newId('debt'),
            person: _person.text.trim(),
            direction: _direction,
            entries: [startEntry],
            dueDate: _due,
            note: _note.text.trim(),
            createdAt: DateTime.now(),
          )
        : existing.copyWith(
            person: _person.text.trim(),
            direction: _direction,
            entries: [startEntry, ...existing.entries.where((e) => e.id != startEntry.id)],
            dueDate: _due,
            clearDueDate: _due == null,
            note: _note.text.trim(),
          );
    await app.saveDebt(debt);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final people = _isEdit ? const <String>[] : app.debtPeople.take(6).toList();
    final existing = widget.debt;
    // Added later and repaid: the start amount cannot go below what that needs.
    final others = existing == null ? 0.0 : existing.entries.where((e) => e.kind == DebtEntryKind.more).fold(0.0, (s, e) => s + e.amount);
    final minimum = existing == null ? 0.0 : existing.repaid - others;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 16),
                child: Text(_isEdit ? tr('Modifier la dette') : tr('Nouvelle dette'), style: context.type.headlineSmall),
              ),
              SegmentedButton<DebtDirection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: DebtDirection.lent, label: Text(tr('J\'ai prêté'))),
                  ButtonSegment(value: DebtDirection.borrowed, label: Text(tr('J\'ai emprunté'))),
                ],
                selected: {_direction},
                onSelectionChanged: (v) => setState(() => _direction = v.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _person,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _direction == DebtDirection.lent ? tr('Prêté à') : tr('Emprunté à'),
                  hintText: tr('Nom de la personne'),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('Indiquez la personne.') : null,
              ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [for (final p in people) ActionChip(label: Text(p), onPressed: () => setState(() => _person.text = p))],
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Montant'), suffixText: currencySymbol),
                validator: (v) {
                  final value = parseAmount(v ?? '');
                  if (value == null || value <= 0) return tr('Entrez un montant supérieur à 0.');
                  if (value < minimum - 0.005) return tr('{0} déjà rendus : le montant ne peut pas être inférieur.', [money(minimum)]);
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _WalletChoice(out: _direction == DebtDirection.lent, walletId: _walletId, onChanged: (id) => setState(() => _walletId = id)),
              const SizedBox(height: 16),
              _DateRow(
                label: tr('Date'),
                date: _date,
                onTap: () async {
                  final picked = await _pickPast(context, _date);
                  if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
                },
              ),
              const SizedBox(height: 12),
              _DateRow(
                label: tr('À rendre avant (facultatif)'),
                date: _due,
                icon: Icons.event_outlined,
                onTap: _pickDue,
                onClear: () => setState(() => _due = null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Note (facultatif)'), counterText: ''),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Enregistrer'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Records a repayment, or more money lent or borrowed, for [debt].
/// Pro and Premium only (see [requireDebts]).
Future<void> showDebtEntryForm(BuildContext context, Debt debt, DebtEntryKind kind) async {
  if (!await requireDebts(context) || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EntryForm(debt: debt, kind: kind),
  );
}

class _EntryForm extends StatefulWidget {
  const _EntryForm({required this.debt, required this.kind});

  final Debt debt;
  final DebtEntryKind kind;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _walletId;
  bool _saving = false;

  bool get _repayment => widget.kind == DebtEntryKind.repayment;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    // The wallet used last for this debt, else the usual one.
    final last = widget.debt.entries.reversed.map((e) => e.walletId).whereType<String>().firstOrNull;
    final offered = app.debtWallets;
    _walletId =
        offered.where((w) => w.id == last).firstOrNull?.id ??
        offered.where((w) => w.id == app.defaultWallet.id).firstOrNull?.id ??
        offered.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final debt = widget.debt;
    await app.addDebtEntry(
      debt,
      DebtEntry(
        id: newId('d'),
        kind: widget.kind,
        amount: parseAmount(_amount.text)!,
        date: _date,
        walletId: _walletId,
        note: _note.text.trim(),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
    final now = app.debts.where((d) => d.id == debt.id).firstOrNull;
    if (_repayment && now != null && now.isSettled) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Dette avec {0} réglée.', [debt.person]))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    final remaining = debt.remaining;
    final title = _repayment
        ? (debt.isLent ? tr('{0} vous rend de l\'argent', [debt.person]) : tr('Vous rendez de l\'argent à {0}', [debt.person]))
        : (debt.isLent ? tr('Prêter encore à {0}', [debt.person]) : tr('Emprunter encore à {0}', [debt.person]));
    // Money leaves the wallet when lending, or when paying back a loan.
    final out = debt.isLent != _repayment;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 16),
                child: Text(title, style: context.type.headlineSmall),
              ),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Montant'),
                  suffixText: currencySymbol,
                  helperText: _repayment ? tr('Reste à rendre : {0}', [money(remaining)]) : null,
                ),
                validator: (v) {
                  final value = parseAmount(v ?? '');
                  if (value == null || value <= 0) return tr('Entrez un montant supérieur à 0.');
                  if (_repayment && value > remaining + 0.005) {
                    return tr('Au plus {0} : c\'est ce qui reste à rendre.', [money(remaining)]);
                  }
                  return null;
                },
              ),
              if (_repayment) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionChip(
                    label: Text(tr('Tout : {0}', [money(remaining)])),
                    onPressed: () => setState(() => _amount.text = _amountText(remaining)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _WalletChoice(out: out, walletId: _walletId, onChanged: (id) => setState(() => _walletId = id)),
              const SizedBox(height: 16),
              _DateRow(
                label: tr('Date'),
                date: _date,
                onTap: () async {
                  final picked = await _pickPast(context, _date);
                  if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Note (facultatif)'), counterText: ''),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Enregistrer'))),
            ],
          ),
        ),
      ),
    );
  }
}
