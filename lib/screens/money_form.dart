import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/currency.dart';
import '../models/deposit.dart';
import '../models/plan.dart';
import '../models/wallet.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../utils/ids.dart';
import '../widgets/common.dart';
import 'paywall_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

/// The three things you can do with money that are not expenses.
enum MoneyAction {
  topUp('Ajouter', Icons.add_rounded),
  withdraw('Retirer', Icons.remove_rounded),
  transfer('Transférer', Icons.swap_horiz_rounded);

  const MoneyAction(this._label, this.icon);

  final String _label;
  final IconData icon;

  String get label => tr(_label);

  static MoneyAction of(DepositKind k) => switch (k) {
        DepositKind.withdrawal => withdraw,
        DepositKind.transfer => transfer,
        _ => topUp,
      };
}

/// Opens the money form. [wallet] is preselected (as the source for a
/// transfer). With [deposit], edits that movement instead.
Future<void> showMoneyForm(BuildContext context, MoneyAction action, {Wallet? wallet, Deposit? deposit}) async {
  final app = context.read<AppState>();
  if (action == MoneyAction.transfer && deposit == null && app.activeWallets.length < 2) {
    // A transfer needs a second wallet: create one first (Pro or higher).
    final plan = context.read<PlanState>();
    final ok = await requirePlan(context,
        allowed: plan.canAddWallet(app.wallets.length),
        needed: Plan.pro,
        reason: tr('Un transfert déplace de l\'argent entre deux portefeuilles, par exemple de la banque vers les espèces. Pro permet d\'avoir deux portefeuilles.'));
    if (!ok || !context.mounted) return;
    await showWalletForm(context);
    if (!context.mounted || context.read<AppState>().activeWallets.length < 2) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MoneyForm(action: action, wallet: wallet, deposit: deposit),
  );
}

/// Ajouter / Retirer / Transférer buttons, shown on the home screen and on
/// each wallet's screen.
class MoneyActionsRow extends StatelessWidget {
  const MoneyActionsRow({super.key, this.wallet});

  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    context.watch<AppState>();
    return Row(
      children: [
        for (final a in MoneyAction.values) ...[
          if (a != MoneyAction.topUp) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: a == MoneyAction.topUp ? eco.yellow : eco.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: a == MoneyAction.topUp ? BorderSide.none : BorderSide(color: eco.glassBorder),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showMoneyForm(context, a, wallet: wallet),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        a.icon,
                        color: switch (a) {
                          MoneyAction.topUp => eco.onYellow,
                          MoneyAction.withdraw => eco.coral,
                          MoneyAction.transfer => eco.blueInk,
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.label,
                        style: context.type.labelMedium?.copyWith(color: a == MoneyAction.topUp ? eco.onYellow : eco.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Future<String?> pickWallet(BuildContext context, {required String title, required List<Wallet> from, String? selected}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(title, style: ctx.type.headlineSmall),
            ),
            for (final w in from)
              ListTile(
                leading: WalletAvatar(type: w.type, size: 38),
                title: Text(w.name, style: ctx.type.titleSmall),
                subtitle: _balanceText(ctx, w),
                trailing: w.id == selected ? Icon(Icons.check_rounded, color: ctx.eco.blueInk) : null,
                onTap: () => Navigator.pop(ctx, w.id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

Widget? _balanceText(BuildContext context, Wallet w) {
  final b = context.read<AppState>().balanceOf(w);
  return b == null ? null : Text('${moneyIn(b, w.currencyOr(activeCurrency))} restants', style: context.type.bodySmall);
}

class _MoneyForm extends StatefulWidget {
  const _MoneyForm({required this.action, this.wallet, this.deposit});

  final MoneyAction action;
  final Wallet? wallet;
  final Deposit? deposit;

  @override
  State<_MoneyForm> createState() => _MoneyFormState();
}

class _MoneyFormState extends State<_MoneyForm> {
  late MoneyAction _action;
  late final TextEditingController _amount;
  late final TextEditingController _received;
  late final TextEditingController _note;
  late String _walletId; // top-up / withdraw target, or transfer source
  String? _toId; // transfer destination
  late DateTime _date;
  bool _receivedEdited = false;
  String? _error;

  AppState get _app => context.read<AppState>();
  bool get _editing => widget.deposit != null;

  Wallet get _wallet => _app.walletById(_walletId);
  Wallet? get _to => _toId == null || !_app.wallets.any((w) => w.id == _toId) ? null : _app.walletById(_toId);
  Currency get _currency => _wallet.currencyOr(activeCurrency);
  bool get _crossCurrency =>
      _action == MoneyAction.transfer && _to != null && _to!.currencyOr(activeCurrency).code != _currency.code;

  static String _fmt(double? v) =>
      v == null ? '' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    final d = widget.deposit;
    _action = d == null ? widget.action : MoneyAction.of(d.kind);
    _date = d?.date ?? DateTime.now();
    _note = TextEditingController(text: d?.note ?? '');
    if (d != null && d.kind == DepositKind.transfer) {
      // Stored as received by walletId, sent from sourceWalletId.
      _walletId = d.sourceWalletId ?? d.walletId;
      _toId = d.walletId;
      _amount = TextEditingController(text: _fmt(d.sentAmount));
      _received = TextEditingController(text: _fmt(d.amount));
      _receivedEdited = d.sourceAmount != null;
    } else {
      final preset = widget.wallet;
      _walletId = d?.walletId ?? (preset != null && !_app.isWalletFrozen(preset) ? preset.id : _app.defaultWallet.id);
      _amount = TextEditingController(text: _fmt(d?.amount));
      _received = TextEditingController();
      _toId = _defaultDestination();
    }
  }

  /// Bank to cash is the usual move; otherwise the first other wallet.
  String? _defaultDestination() {
    final others = _app.activeWallets.where((w) => w.id != _walletId).toList();
    if (others.isEmpty) return null;
    final source = _app.walletById(_walletId);
    final preferred = others.where((w) => w.type == (source.type == WalletType.cash ? WalletType.bank : WalletType.cash));
    return (preferred.isNotEmpty ? preferred.first : others.first).id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _received.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Suggests what arrives in the other currency using the wallets' rates.
  void _suggestReceived() {
    if (_receivedEdited || !_crossCurrency) return;
    final sent = parseAmount(_amount.text);
    if (sent == null) {
      _received.text = '';
      return;
    }
    final main = _wallet.isForeign(activeCurrency.code) ? sent * _wallet.rate! : sent;
    final to = _to!;
    final received = to.isForeign(activeCurrency.code) ? main / to.rate! : main;
    _received.text = _fmt(double.parse(received.toStringAsFixed(2)));
  }

  void _swap() {
    final to = _toId;
    if (to == null) return;
    setState(() {
      _toId = _walletId;
      _walletId = to;
      _receivedEdited = false;
      _suggestReceived();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    // Earlier days start at midnight so that day's expenses come after it.
    setState(() => _date = sameDay(picked, now) ? now : DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final value = parseAmount(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = tr('Entrez un montant supérieur à 0.'));
      return;
    }
    double? received;
    if (_action == MoneyAction.transfer) {
      if (_to == null || _toId == _walletId) {
        setState(() => _error = tr('Choisissez deux portefeuilles différents.'));
        return;
      }
      if (_crossCurrency) {
        received = parseAmount(_received.text);
        if (received == null || received <= 0) {
          setState(() => _error = tr('Indiquez le montant reçu sur « {0} ».', [_to!.name]));
          return;
        }
      }
    }

    // Taking out more than what is left: probably a missing top-up.
    if (_action != MoneyAction.topUp && !_editing) {
      final left = _app.balanceOf(_wallet);
      if (left != null && value > left + 0.005) {
        final ok = await confirm(context,
            title: tr('Solde insuffisant'),
            message: tr('Il ne reste que {0} dans « {1} ». Le solde deviendra négatif. Continuer ?', [moneyIn(left, _currency), _wallet.name]),
            confirmLabel: tr('Continuer'));
        if (!ok || !mounted) return;
      }
    }

    final id = widget.deposit?.id ?? newId('d');
    final note = _note.text.trim();
    final deposit = switch (_action) {
      MoneyAction.topUp =>
        Deposit(id: id, walletId: _walletId, amount: value, date: _date, kind: DepositKind.income, note: note),
      MoneyAction.withdraw =>
        Deposit(id: id, walletId: _walletId, amount: value, date: _date, kind: DepositKind.withdrawal, note: note),
      MoneyAction.transfer => Deposit(
          id: id,
          walletId: _toId!,
          amount: received ?? value,
          date: _date,
          kind: DepositKind.transfer,
          note: note,
          sourceWalletId: _walletId,
          sourceAmount: received == null ? null : value,
        ),
    };
    await _app.saveDeposit(deposit);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: tr('Supprimer ce mouvement ?'),
        message: tr('Le solde sera recalculé sans lui.'),
        confirmLabel: tr('Supprimer'),
        destructive: true);
    if (!ok || !mounted) return;
    await _app.deleteDeposit(widget.deposit!);
    if (mounted) Navigator.pop(context);
  }

  String get _helper => switch (_action) {
        MoneyAction.topUp => tr('Salaire, retrait au distributeur, cadeau, remboursement…'),
        MoneyAction.withdraw =>
          tr('L\'argent sort du portefeuille sans compter comme dépense : mis de côté, prêté, déposé ailleurs. Pour un achat, notez plutôt une dépense.'),
        MoneyAction.transfer => tr('L\'argent passe d\'un portefeuille à l\'autre, sans changer vos dépenses.'),
      };

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final app = context.watch<AppState>();
    final amountStyle = context.type.displayMedium?.copyWith(fontFeatures: tabular);
    final actions = [
      MoneyAction.topUp,
      MoneyAction.withdraw,
      if (app.activeWallets.length > 1 || _action == MoneyAction.transfer) MoneyAction.transfer,
    ];

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_editing)
              SegmentedButton<MoneyAction>(
                segments: [for (final a in actions) ButtonSegment(value: a, label: Text(a.label))],
                selected: {_action},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _action = s.first;
                  _error = null;
                  _toId ??= _defaultDestination();
                  _suggestReceived();
                }),
              )
            else
              Text(tr('Modifier : {0}', [_action.label.toLowerCase()]), style: context.type.headlineSmall),
            const SizedBox(height: 8),
            Text(_helper, style: context.type.bodySmall),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _action == MoneyAction.topUp ? '+' : '−',
                    style: amountStyle?.copyWith(color: _action == MoneyAction.topUp ? eco.leaf : eco.muted),
                  ),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amount,
                      autofocus: !_editing,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: amountStyle,
                      onChanged: (_) => setState(() {
                        _error = null;
                        _suggestReceived();
                      }),
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
                  Text(_currency.symbol, style: context.type.titleLarge?.copyWith(color: eco.muted)),
                ],
              ),
            ),
            Grouped(
              dividerIndent: 54,
              children: [
                _walletRow(
                  context,
                  icon: _action == MoneyAction.transfer ? Icons.north_east_rounded : Icons.account_balance_wallet_outlined,
                  title: switch (_action) {
                    MoneyAction.topUp => tr('Vers'),
                    MoneyAction.withdraw => tr('Depuis'),
                    MoneyAction.transfer => tr('De'),
                  },
                  wallet: _wallet,
                  onTap: () async {
                    final id = await pickWallet(context, title: tr('Choisir le portefeuille'), from: app.activeWallets, selected: _walletId);
                    if (id == null) return;
                    setState(() {
                      if (id == _toId) _toId = _walletId;
                      _walletId = id;
                      _receivedEdited = false;
                      _suggestReceived();
                    });
                  },
                ),
                if (_action == MoneyAction.transfer)
                  _walletRow(
                    context,
                    icon: Icons.south_west_rounded,
                    title: tr('Vers'),
                    wallet: _to,
                    trailing: IconButton(
                      tooltip: tr('Inverser'),
                      onPressed: _swap,
                      icon: Icon(Icons.swap_vert_rounded, color: eco.blueInk),
                    ),
                    onTap: () async {
                      final others = app.activeWallets.where((w) => w.id != _walletId).toList();
                      final id = await pickWallet(context, title: tr('Vers quel portefeuille ?'), from: others, selected: _toId);
                      if (id == null) return;
                      setState(() {
                        _toId = id;
                        _receivedEdited = false;
                        _suggestReceived();
                      });
                    },
                  ),
                if (_crossCurrency)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.currency_exchange_rounded, size: 22, color: eco.muted),
                        const SizedBox(width: 16),
                        Expanded(child: Text(tr('Montant reçu'), style: context.type.titleSmall)),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _received,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => _receivedEdited = true,
                            decoration: InputDecoration(
                              suffixText: ' ${_to!.currencyOr(activeCurrency).symbol}',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          maxLength: 60,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: switch (_action) {
                              MoneyAction.topUp => tr('Ex. : Salaire, Retrait'),
                              MoneyAction.withdraw => tr('Ex. : Mis de côté, Prêt à Karim'),
                              MoneyAction.transfer => tr('Note (facultatif)'),
                            },
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: context.type.bodyMedium?.copyWith(color: eco.coral)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              // Money leaving: the same red as withdrawals in the history.
              style: _action == MoneyAction.withdraw
                  ? FilledButton.styleFrom(backgroundColor: context.eco.coral, foregroundColor: Colors.white)
                  : null,
              child: Text(_editing
                  ? tr('Enregistrer')
                  : switch (_action) {
                      MoneyAction.topUp => tr('Ajouter l\'argent'),
                      MoneyAction.withdraw => tr('Retirer l\'argent'),
                      MoneyAction.transfer => tr('Transférer'),
                    }),
            ),
            if (_editing)
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: eco.coral),
                child: Text(tr('Supprimer ce mouvement')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _walletRow(BuildContext context,
      {required IconData icon, required String title, required Wallet? wallet, required VoidCallback onTap, Widget? trailing}) {
    final eco = context.eco;
    final left = wallet == null ? null : context.read<AppState>().balanceOf(wallet);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16, trailing == null ? 15 : 6, trailing == null ? 16 : 4, trailing == null ? 15 : 6),
        child: Row(
          children: [
            Icon(icon, size: 22, color: eco.muted),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: context.type.titleSmall)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(wallet?.name ?? tr('Choisir'), style: context.type.bodyMedium?.copyWith(color: eco.ink)),
                if (left != null)
                  Text('${moneyIn(left, wallet!.currencyOr(activeCurrency))} restants', style: context.type.bodySmall),
              ],
            ),
            if (trailing != null) trailing else Icon(Icons.chevron_right_rounded, color: eco.muted),
          ],
        ),
      ),
    );
  }
}
