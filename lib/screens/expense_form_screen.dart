import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../models/wallet.dart';
import '../services/budget_math.dart';
import '../services/insights_service.dart';
import '../services/qr_receipt.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'categories_screen.dart';
import 'qr_scan_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

/// Add a new expense, or edit / delete an existing one.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense});

  final Expense? expense;

  static Future<void> open(BuildContext context, [Expense? expense]) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: expense), fullscreenDialog: true));

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _categoryId;
  late String _walletId;
  late DateTime _date;
  String? _amountError;
  bool _saving = false;

  /// A refund is stored as a negative expense: it lowers the month's
  /// spending and its category, and puts the money back in the wallet.
  late bool _refund;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _refund = e?.isRefund ?? false;
    final shown = (e?.originalAmount ?? e?.amount)?.abs();
    _amount = TextEditingController(text: shown == null ? '' : shown.toStringAsFixed(shown.truncateToDouble() == shown ? 0 : 2));
    _note = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId ?? ExpenseCategory.visible.first.id;
    final app = context.read<AppState>();
    _walletId = e?.walletId != null ? app.walletById(e!.walletId).id : app.defaultWallet.id;
    _date = e?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  Future<void> _save() async {
    final value = parseAmount(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _amountError = tr('Entrez un montant supérieur à 0.'));
      return;
    }
    if (value > 100000000) {
      setState(() => _amountError = tr('Ce montant semble trop élevé.'));
      return;
    }
    final state = context.read<AppState>();
    if (state.isWalletFrozen(state.walletById(_walletId))) {
      setState(() => _amountError = tr('Ce portefeuille est gelé : choisissez-en un autre dans « Payé avec ».'));
      return;
    }
    setState(() => _saving = true);
    final wallet = state.walletById(_walletId);
    final rate = _rateFor(wallet);
    final sign = _refund ? -1 : 1;
    final expense = Expense(
      id: widget.expense?.id,
      amount: sign * (rate == null ? value : value * rate),
      categoryId: _categoryId,
      date: _date,
      note: _note.text.trim(),
      walletId: _walletId,
      originalAmount: rate == null ? null : sign * value,
      originalCurrency: rate == null ? null : wallet.currencyCode,
    );

    // Real-time detection: compare with the user's history before saving.
    final unusual = _refund ? null : InsightsService.checkUnusual(expense, state.expenses);

    if (_isEdit) {
      await state.updateExpense(expense);
    } else {
      await state.addExpense(expense);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    if (unusual != null) {
      final cat = ExpenseCategory.byId(expense.categoryId);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            tr('Dépense inhabituelle en {0} : environ {1}× votre montant habituel ({2}).', [
              cat.label,
              decimal1(unusual.ratio),
              moneyApprox(unusual.usual),
            ]),
          ),
        ),
      );
    }
  }

  /// Conversion rate for a wallet in another currency, null otherwise.
  /// Editing keeps the rate the expense was recorded with.
  double? _rateFor(Wallet w) {
    if (!w.isForeign(activeCurrency.code)) return null;
    final e = widget.expense;
    if (e != null && e.originalCurrency == w.currencyCode && e.rate != null) return e.rate;
    return w.rate;
  }

  Future<void> _pickWallet() async {
    final app = context.read<AppState>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(_refund ? tr('Rendu sur') : tr('Payé avec'), style: ctx.type.headlineSmall),
            ),
            for (final w in app.activeWallets)
              ListTile(
                leading: WalletAvatar(type: w.type, size: 38),
                title: Text(w.name, style: ctx.type.titleSmall),
                trailing: w.id == _walletId ? Icon(Icons.check_rounded, color: ctx.eco.blueInk) : null,
                onTap: () => Navigator.pop(ctx, w.id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _walletId = picked);
  }

  /// Where a new expense will be taken from: the wallet's share of the
  /// budget, or outside it.
  Widget? _budgetHint(BuildContext context) {
    final app = context.watch<AppState>();
    if (_isEdit || !sameMonth(_date, DateTime.now())) return null;
    final st = app.budgetStatus(_date);
    if (!st.hasBudget) return null;
    // What this expense will count in the main currency.
    final typed = parseAmount(_amount.text) ?? 0;
    final rate = _rateFor(app.walletById(_walletId));
    final value = (rate == null ? typed : typed * rate) * (_refund ? -1 : 1);
    final after = st.budget - st.spent - value;
    final eco = context.eco;
    // `after` is what the month will have left once this amount is saved
    // (a refund gives money back).
    final (text, color) = after < -0.005
        ? (st.level == BudgetLevel.exceeded && value >= 0
              ? (tr('Le budget du mois est déjà dépassé de {0}.', [money(st.overspent)]), eco.coral)
              : value < 0
              ? (tr('Même avec ce remboursement, le budget reste dépassé de {0}.', [money(-after)]), eco.coral)
              : (tr('Cette dépense dépassera le budget du mois de {0}.', [money(-after)]), eco.coral))
        : value < 0
        ? (tr('Après ce remboursement : {0} restants, soit {1} par jour.', [money(after), moneyApprox(after / st.daysLeft)]), eco.muted)
        : value > 0
        ? (tr('Après cette dépense : {0} restants, soit {1} par jour.', [money(after), moneyApprox(after / st.daysLeft)]), eco.muted)
        : (tr('Reste ce mois : {0}, soit {1} par jour.', [money(st.remaining), moneyApprox(st.dailyAllowance)]), eco.muted);
    return Padding(
      // Lined up under "Payé avec" when that row is shown.
      padding: EdgeInsetsDirectional.fromSTEB(app.activeWallets.length > 1 ? 54 : 16, 12, 16, 12),
      child: Text(text, style: context.type.bodySmall?.copyWith(color: color)),
    );
  }

  /// Scans a receipt or payment QR code and fills what it states: amount,
  /// merchant (as the note), date, and the wallet in that currency.
  Future<void> _scan() async {
    final raw = await QrScanScreen.open(context);
    if (raw == null || !mounted) return;
    final r = QrReceipt.parse(raw);
    final app = context.read<AppState>();
    final messages = <String>[];

    setState(() {
      final amount = r.amount;
      if (amount != null) {
        _amount.text = amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
        _amountError = null;
      }
      final merchant = r.merchant;
      if (merchant != null && _note.text.trim().isEmpty) {
        _note.text = merchant.length > 80 ? merchant.substring(0, 80) : merchant;
      }
      if (r.date != null) _date = r.date!;

      // Amount in another currency: pay with the wallet in that currency.
      final code = r.currency;
      if (amount != null && code != null && code != _walletCurrency.code) {
        final match = app.activeWallets.where((w) => !app.isWalletFrozen(w) && w.currencyOr(activeCurrency).code == code).firstOrNull;
        if (match != null) {
          _walletId = match.id;
          messages.add(tr('Payé avec « {0} », votre portefeuille en {1}.', [match.name, code]));
        } else {
          messages.add(
            tr('Ce montant est en {0} et « {1} » est en {2} : vérifiez-le avant d\'ajouter.', [
              code,
              app.walletById(_walletId).name,
              _walletCurrency.code,
            ]),
          );
        }
      }
    });

    if (r.amount != null) {
      messages.insert(0, tr('Montant lu : {0}.', ['${_amount.text} ${r.currency ?? _walletCurrency.symbol}']));
    } else if (r.merchant != null) {
      messages.add(tr('Ce QR code ne contient pas de montant : « {0} » est noté, saisissez le montant.', [r.merchant!]));
    } else {
      messages.add(tr('Ce QR code ne contient pas de montant. Saisissez-le à la main.'));
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text(messages.join(' '))));
  }

  Future<void> _newCategory() async {
    final created = await showCategoryForm(context);
    if (created != null && mounted) setState(() => _categoryId = created.id);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: _refund ? tr('Supprimer ce remboursement ?') : tr('Supprimer cette dépense ?'),
      message: _refund
          ? tr('Il sera retiré de vos budgets et de vos graphiques, et l\'argent sortira de nouveau du portefeuille.')
          : tr('Elle sera retirée de vos budgets et de vos graphiques.'),
      confirmLabel: tr('Supprimer'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteExpense(widget.expense!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final amountStyle = context.type.displayLarge?.copyWith(fontSize: 56, fontFeatures: tabular);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _refund
              ? (_isEdit ? tr('Modifier le remboursement') : tr('Nouveau remboursement'))
              : (_isEdit ? tr('Modifier la dépense') : tr('Nouvelle dépense')),
          style: context.type.titleLarge,
        ),
        actions: [
          if (!_isEdit) TextButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: Text(tr('Scanner'))),
          if (_isEdit) IconButton(tooltip: tr('Supprimer'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(tr('Dépense'))),
              ButtonSegment(value: true, label: Text(tr('Remboursement'))),
            ],
            selected: {_refund},
            onSelectionChanged: (v) => setState(() => _refund = v.first),
          ),
          if (_refund)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 10, 4, 0),
              child: Text(
                tr('Argent rendu pour un achat : il est déduit des dépenses du mois et de sa catégorie, et revient dans le portefeuille.'),
                style: context.type.bodySmall,
              ),
            ),
          // Amount: the one thing this screen is for, set large and centred.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                IntrinsicWidth(
                  child: TextField(
                    controller: _amount,
                    autofocus: !_isEdit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: amountStyle,
                    onChanged: (_) => setState(() => _amountError = null),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: amountStyle?.copyWith(color: eco.hairline),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_walletCurrency.symbol, style: context.type.headlineSmall?.copyWith(color: eco.muted)),
              ],
            ),
          ),
          if (_conversion != null && _amountError == null)
            Text(
              _conversion!,
              textAlign: TextAlign.center,
              style: context.type.bodyMedium?.copyWith(color: eco.muted),
            ),
          if (_amountError != null)
            Text(
              _amountError!,
              textAlign: TextAlign.center,
              style: context.type.bodyMedium?.copyWith(color: eco.coral),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 12),
            child: Text(tr('Catégorie'), style: context.type.titleSmall),
          ),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
            children: [for (final cat in _categories) _categoryTile(cat), _newCategoryTile()],
          ),
          const SizedBox(height: 20),
          Grouped(
            dividerIndent: 54,
            children: [
              if (context.watch<AppState>().activeWallets.length > 1 ||
                  context.read<AppState>().isWalletFrozen(context.read<AppState>().walletById(_walletId)))
                InkWell(
                  onTap: _pickWallet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: Row(
                      children: [
                        Icon(context.read<AppState>().walletById(_walletId).type.icon, size: 22, color: eco.muted),
                        const SizedBox(width: 16),
                        Expanded(child: Text(_refund ? tr('Rendu sur') : tr('Payé avec'), style: context.type.titleSmall)),
                        Text(
                          context.read<AppState>().walletById(_walletId).name,
                          style: context.type.bodyMedium?.copyWith(color: eco.muted),
                        ),
                        Icon(Icons.chevron_right_rounded, color: eco.muted),
                      ],
                    ),
                  ),
                ),
              ?_budgetHint(context),
              InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 22, color: eco.muted),
                      const SizedBox(width: 16),
                      Expanded(child: Text(tr('Date'), style: context.type.titleSmall)),
                      Text(longDate(_date), style: context.type.bodyMedium?.copyWith(color: eco.muted)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 22, color: eco.muted),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _note,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: tr('Note (facultatif)'),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          // Lifted above the keyboard so the button stays reachable while typing.
          padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _isEdit ? tr('Enregistrer les modifications') : (_refund ? tr('Ajouter le remboursement') : tr('Ajouter la dépense')),
            ),
          ),
        ),
      ),
    );
  }

  /// Pickable categories, plus the expense's own one if it is a frozen
  /// custom category (so editing does not silently change it).
  List<ExpenseCategory> get _categories {
    final list = ExpenseCategory.visible;
    if (list.any((c) => c.id == _categoryId)) return list;
    final current = ExpenseCategory.byId(_categoryId);
    if (current.id != _categoryId) return list;
    return [...list.take(list.length - 1), current, list.last];
  }

  Currency get _walletCurrency => context.read<AppState>().walletById(_walletId).currencyOr(activeCurrency);

  /// "≈ 5 000 DA (1 € = 250 DA)" under the amount for a foreign wallet.
  String? get _conversion {
    final wallet = context.read<AppState>().walletById(_walletId);
    final rate = _rateFor(wallet);
    if (rate == null) return null;
    final value = parseAmount(_amount.text) ?? 0;
    final label = rateLabel(Currency.byCode(wallet.currencyCode), rate);
    return value > 0 ? '≈ ${money(value * rate)} ($label)' : label;
  }

  Widget _newCategoryTile() {
    final eco = context.eco;
    return Semantics(
      button: true,
      label: tr('Nouvelle catégorie'),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _newCategory,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: eco.hairline, width: 1.5),
              ),
              child: Icon(Icons.add_rounded, color: eco.muted, size: 26),
            ),
            const SizedBox(height: 6),
            Text(tr('Nouvelle'), style: context.type.labelSmall?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(ExpenseCategory cat) {
    final eco = context.eco;
    final selected = _categoryId == cat.id;
    return Semantics(
      selected: selected,
      button: true,
      label: cat.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _categoryId = cat.id),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? cat.color : cat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(cat.icon, color: selected ? Colors.white : cat.color, size: 26),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                cat.label,
                maxLines: 1,
                style: context.type.labelSmall?.copyWith(
                  color: selected ? eco.ink : eco.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
