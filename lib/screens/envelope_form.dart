import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/wallet.dart';
import '../services/budget_math.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'wallets_screen.dart';

/// Sets the monthly budget: worked out from income and savings, or typed
/// in; optionally reserved in wallets.
Future<void> showBudgetForm(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetForm(),
    );

enum _SavingsKind { percent, amount }

class _BudgetForm extends StatefulWidget {
  const _BudgetForm();

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  late BudgetMode _mode;
  late _SavingsKind _savingsKind;
  late bool _fromRecords;
  late final double? _recorded;
  final _income = TextEditingController();
  final _savings = TextEditingController();
  final _manual = TextEditingController();
  final _shares = <String, TextEditingController>{};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final c = app.budgetConfig;
    _mode = c.mode;
    _fromRecords = c.incomeFromRecords;
    _recorded = app.recordedIncomeAverage;
    _savingsKind = c.savingsAmount != null ? _SavingsKind.amount : _SavingsKind.percent;
    _income.text = c.incomeFromRecords ? '' : _plain(c.income);
    _savings.text = _plain(c.savingsAmount ?? c.savingsPercent);
    _manual.text = _plain(c.manualBudget);
    for (final w in app.activeWallets) {
      _shares[w.id] = TextEditingController(text: _plain(app.envelope.funds[w.id]));
    }
    for (final ctrl in [_income, _savings, _manual, ..._shares.values]) {
      ctrl.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [_income, _savings, _manual, ..._shares.values]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() => _error = null);

  static String _plain(double? v) =>
      v == null || v <= 0 ? '' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  static double? _read(TextEditingController c) => parseAmount(c.text.trim());

  BudgetConfig get _config => BudgetConfig(
        mode: _mode,
        incomeFromRecords: _fromRecords,
        income: _fromRecords ? _recorded : _read(_income),
        savingsPercent: _savingsKind == _SavingsKind.percent ? _read(_savings) : null,
        savingsAmount: _savingsKind == _SavingsKind.amount ? _read(_savings) : null,
        manualBudget: _read(_manual),
      );

  double get _reserved => _shares.values.fold(0.0, (s, c) => s + (_read(c) ?? 0));

  String? _validate() {
    final c = _config;
    if (_mode == BudgetMode.automatic) {
      if (_fromRecords && (_recorded ?? 0) <= 0) {
        return tr('Aucun revenu enregistré ces trois derniers mois : saisissez votre revenu, ou passez en mode manuel.');
      }
      if ((c.income ?? 0) <= 0) return tr('Entrez votre revenu mensuel, ou passez en mode manuel.');
      final s = _read(_savings) ?? 0;
      if (s < 0) return tr('Montant invalide.');
      if (_savingsKind == _SavingsKind.percent && s > 100) return tr('L\'épargne ne peut pas dépasser 100 %.');
      if (_savingsKind == _SavingsKind.amount && s >= c.income!) return tr('L\'épargne doit rester inférieure au revenu.');
    } else if ((c.manualBudget ?? 0) <= 0) {
      return tr('Entrez un montant supérieur à 0.');
    }
    if (_reserved > (c.budget ?? 0) + 0.005) {
      return tr('Les réservations ({0}) dépassent le budget ({1}).', [money(_reserved), money(c.budget ?? 0)]);
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    await context.read<AppState>().setBudgetConfig(
          _config,
          funds: {for (final e in _shares.entries) e.key: _read(e.value) ?? 0},
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final c = _config;
    // Preferences are kept; only the budget goes.
    await context.read<AppState>().setBudgetConfig(
          BudgetConfig(
            mode: BudgetMode.manual,
            income: c.income,
            savingsPercent: c.savingsPercent,
            savingsAmount: c.savingsAmount,
          ),
          funds: const {},
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final c = _config;
    final budget = c.budget;
    final recordedIncome = app.incomeInMonth(monthStart(DateTime.now()));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Budget du mois'), style: context.type.headlineSmall),
            const SizedBox(height: 14),
            SegmentedButton<BudgetMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: BudgetMode.automatic, label: Text(tr('Automatique'))),
                ButtonSegment(value: BudgetMode.manual, label: Text(tr('Manuel'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_mode == BudgetMode.automatic) ...[
              Text(
                tr('Le budget se calcule à partir de votre revenu, moins ce que vous voulez épargner.'),
                style: context.type.bodyMedium?.copyWith(color: eco.muted),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Revenu saisi'))),
                  ButtonSegment(value: true, label: Text(tr('Revenus enregistrés'))),
                ],
                selected: {_fromRecords},
                onSelectionChanged: (v) => setState(() {
                  _fromRecords = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_fromRecords)
                Text(
                  _recorded == null
                      ? tr('Aucun revenu enregistré ces trois derniers mois. Ajoutez vos revenus dans vos portefeuilles (« Ajouter », type revenu), ou saisissez votre revenu.')
                      : tr('Moyenne de vos revenus enregistrés sur les trois derniers mois : {0}. Le budget suivra vos revenus réels.', [money(_recorded)]),
                  style: context.type.bodyMedium,
                )
              else
                _AmountField(controller: _income, label: tr('Revenu mensuel')),
              if (!_fromRecords && recordedIncome > 0 && (c.income ?? 0) <= 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => _income.text = _plain(recordedIncome),
                    child: Text(tr('Utiliser les revenus enregistrés ce mois : {0}', [money(recordedIncome)])),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AmountField(
                      controller: _savings,
                      label: tr('Épargne'),
                      suffix: _savingsKind == _SavingsKind.percent ? '%' : activeCurrency.symbol,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SegmentedButton<_SavingsKind>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: _SavingsKind.percent, label: Text('%')),
                      ButtonSegment(value: _SavingsKind.amount, label: Text(activeCurrency.symbol)),
                    ],
                    selected: {_savingsKind},
                    onSelectionChanged: (s) => setState(() {
                      _savingsKind = s.first;
                      _savings.clear();
                    }),
                  ),
                ],
              ),
            ] else ...[
              Text(
                tr('Vous fixez vous-même ce que vous dépensez au plus chaque mois.'),
                style: context.type.bodyMedium?.copyWith(color: eco.muted),
              ),
              const SizedBox(height: 14),
              _AmountField(controller: _manual, label: tr('Budget mensuel')),
            ],
            const SizedBox(height: 14),
            _Result(mode: _mode, budget: budget, savings: c.savings),
            const SizedBox(height: 22),
            Text(tr('Réserver dans les portefeuilles (facultatif)'), style: context.type.titleMedium),
            const SizedBox(height: 4),
            Text(
              tr('L\'argent reste dans le portefeuille mais apparaît comme réservé au budget du mois.'),
              style: context.type.bodySmall,
            ),
            const SizedBox(height: 10),
            Grouped(
              dividerIndent: 70,
              children: [for (final w in app.activeWallets) _shareRow(context, app, w)],
            ),
            if (budget != null && _reserved > 0)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 0),
                child: Text(
                  tr('Non réservé : {0}', [money((budget - _reserved).clamp(0, double.infinity).toDouble())]),
                  style: context.type.bodySmall,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 4, 0),
                child: Text(_error!, style: context.type.bodyMedium?.copyWith(color: eco.coral)),
              ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Enregistrer le budget'))),
            if (app.totalBudget > 0)
              TextButton(onPressed: _saving ? null : _remove, child: Text(tr('Retirer le budget'))),
          ],
        ),
      ),
    );
  }

  Widget _shareRow(BuildContext context, AppState app, Wallet w) {
    final balance = app.balanceOf(w);
    final currency = w.currencyOr(activeCurrency);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
      child: Row(
        children: [
          WalletAvatar(type: w.type, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  balance == null ? tr('Solde pas encore suivi') : tr('Solde : {0}', [moneyIn(balance, currency)]),
                  style: context.type.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 128, child: _AmountField(controller: _shares[w.id]!, dense: true)),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, this.label, this.suffix, this.dense = false});

  final TextEditingController controller;
  final String? label;
  final String? suffix;
  final bool dense;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: dense ? TextAlign.end : TextAlign.start,
        style: (dense ? context.type.titleMedium : context.type.titleLarge)?.copyWith(fontFeatures: tabular),
        decoration: InputDecoration(
          labelText: label,
          hintText: '0',
          suffixText: suffix ?? activeCurrency.symbol,
          isDense: dense,
          contentPadding: dense ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12) : null,
        ),
      );
}

/// The budget the form gives, as it is being typed.
class _Result extends StatelessWidget {
  const _Result({required this.mode, required this.budget, required this.savings});

  final BudgetMode mode;
  final double? budget;
  final double? savings;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final days = daysInMonth(DateTime.now());
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      decoration: eco.glass(radius: 18, tint: eco.blueInk),
      child: budget == null
          ? Text(
              mode == BudgetMode.automatic
                  ? tr('Indiquez votre revenu mensuel pour calculer votre budget.')
                  : tr('Indiquez le montant de votre budget mensuel.'),
              style: context.type.bodyMedium,
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode == BudgetMode.automatic ? tr('Budget suggéré') : tr('Budget mensuel'),
                          style: context.type.titleSmall),
                      Text(
                        mode == BudgetMode.automatic && savings != null
                            ? tr('Épargne : {0} par mois', [money(savings!)])
                            : tr('Environ {0} par jour', [moneyApprox(budget! / days)]),
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(money(budget!), style: context.type.titleLarge?.copyWith(fontFeatures: tabular)),
              ],
            ),
    );
  }
}
