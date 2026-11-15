import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

/// Sets the month's budget by reserving money in one or more wallets.
Future<void> showEnvelopeForm(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _EnvelopeForm(),
    );

class _EnvelopeForm extends StatefulWidget {
  const _EnvelopeForm();

  @override
  State<_EnvelopeForm> createState() => _EnvelopeFormState();
}

class _EnvelopeFormState extends State<_EnvelopeForm> {
  final _fields = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final env = app.envelope;
    for (final w in app.activeWallets) {
      // A budget set before envelopes existed starts in the main wallet.
      final share = env.shared ? (app.isMainWallet(w) ? env.total : 0.0) : (env.funds[w.id] ?? 0.0);
      _fields[w.id] = TextEditingController(text: share > 0 ? _plain(share) : '')..addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  static String _plain(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  double _share(String walletId) => parseAmount(_fields[walletId]!.text.trim()) ?? 0;

  double get _total => _fields.keys.fold(0.0, (s, id) => s + _share(id));

  Future<void> _save({bool remove = false}) async {
    setState(() => _saving = true);
    final app = context.read<AppState>();
    await app.setEnvelope(remove ? const {} : {for (final id in _fields.keys) id: _share(id)});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final hadBudget = app.totalBudget > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Budget du mois'), style: context.type.headlineSmall),
            const SizedBox(height: 8),
            Text(
              tr('Mettez de côté dans vos portefeuilles l\'argent de vos dépenses du mois. Il y reste, mais il est réservé : chaque achat payé avec un portefeuille est pris sur sa part. Au-delà, la dépense est hors budget.'),
              style: context.type.bodyMedium?.copyWith(color: eco.muted),
            ),
            const SizedBox(height: 18),
            Grouped(
              dividerIndent: 70,
              children: [for (final w in app.activeWallets) _shareRow(context, app, w)],
            ),
            const SizedBox(height: 14),
            GlassTotal(total: _total),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving || (_total <= 0 && !hadBudget) ? null : () => _save(),
              child: Text(_total <= 0 && hadBudget ? tr('Retirer le budget') : tr('Enregistrer le budget')),
            ),
            if (hadBudget && _total > 0)
              TextButton(
                onPressed: _saving ? null : () => _save(remove: true),
                child: Text(tr('Retirer le budget')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _shareRow(BuildContext context, AppState app, Wallet w) {
    final eco = context.eco;
    final balance = app.balanceOf(w);
    final foreign = w.isForeign(activeCurrency.code);
    final currency = w.currencyOr(activeCurrency);
    // What is in the wallet, in the main currency, to compare with the share.
    final inMain = balance == null ? null : (foreign ? balance * w.rate! : balance);
    final share = _share(w.id);
    final tooMuch = inMain != null && share > inMain + 0.005;
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
                  balance == null
                      ? tr('Solde pas encore suivi')
                      : tooMuch
                      ? tr('Plus que les {0} du portefeuille', [moneyIn(balance, currency)])
                      : tr('Solde : {0}', [moneyIn(balance, currency)]),
                  style: context.type.bodySmall?.copyWith(color: tooMuch ? eco.amber : null),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 128,
            child: TextField(
              controller: _fields[w.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              style: context.type.titleMedium?.copyWith(fontFeatures: tabular),
              decoration: InputDecoration(
                hintText: '0',
                suffixText: activeCurrency.symbol,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The envelope's total, under the wallet shares.
class GlassTotal extends StatelessWidget {
  const GlassTotal({super.key, required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      decoration: eco.glass(radius: 18, tint: eco.blueInk),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Budget de chaque mois'), style: context.type.titleSmall),
                Text(tr('Le même montant est réservé au début de chaque mois.'), style: context.type.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(money(total), style: context.type.titleLarge?.copyWith(fontFeatures: tabular)),
        ],
      ),
    );
  }
}
