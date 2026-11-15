import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/currency.dart';
import '../models/deposit.dart';
import '../models/plan.dart';
import '../models/wallet.dart';
import '../services/wallet_math.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../utils/ids.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/currency_picker.dart';
import '../widgets/expense_tile.dart';
import '../widgets/glass.dart';
import '../widgets/payment_card.dart';
import 'expense_form_screen.dart';
import 'home_shell.dart';
import 'money_form.dart';
import 'paywall_screen.dart';
import '../l10n/l10n.dart';

/// The light of each wallet type, on its card, avatar and home chip.
Color walletAccent(EcoColors eco, WalletType type) => switch (type) {
  WalletType.cash => eco.leaf,
  WalletType.bank => eco.blueInk,
  WalletType.card => eco.violet,
  WalletType.savings => eco.isDark ? eco.yellow : eco.amber,
  WalletType.mobile => eco.sky,
  WalletType.other => eco.muted,
};

/// The Wallets tab: wallet cards to swipe through, then what can be done
/// with the one in front (add, withdraw, transfer) and its history.
class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  static String planSummary(Plan p) => switch (p) {
    Plan.starter => tr('Starter : un portefeuille, espèces ou compte bancaire.'),
    Plan.pro => tr('Pro : deux portefeuilles, espèces et compte bancaire.'),
    Plan.premium => tr('Premium : autant de portefeuilles que vous voulez, de tous types.'),
  };

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  final _pages = PageController(viewportFraction: 0.86);

  /// Wallet in front; [_page] can also be the "new wallet" card after it.
  int _index = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    HomeShell.focusWallet.addListener(_focus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  @override
  void dispose() {
    HomeShell.focusWallet.removeListener(_focus);
    _pages.dispose();
    super.dispose();
  }

  /// Brings the wallet another screen asked for to the front.
  void _focus() {
    final id = HomeShell.focusWallet.value;
    if (id == null || !mounted) return;
    HomeShell.focusWallet.value = null;
    final i = context.read<AppState>().wallets.indexWhere((w) => w.id == id);
    if (i >= 0) _show(i);
  }

  void _show(int i) {
    setState(() => _index = _page = i);
    if (_pages.positions.length == 1) {
      _pages.animateToPage(i, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _setBalance(Wallet w, double? current) async {
    final app = context.read<AppState>();
    final value = await showAmountDialog(
      context,
      title: current == null ? tr('Solde actuel') : tr('Corriger le solde'),
      initial: current != null && current > 0 ? current : null,
      allowZero: true,
      currency: w.currencyOr(activeCurrency),
      helper: tr('Combien avez-vous vraiment dans « {0} » maintenant ?', [w.name]),
      confirmLabel: tr('Valider'),
    );
    if (value != null) await app.setBalance(w, value);
  }

  void _menu(Wallet w, String action) => switch (action) {
    'balance' => _setBalance(w, context.read<AppState>().balanceOf(w)),
    'delete' => deleteWalletFlow(context, w),
    _ => showWalletForm(context, w),
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final wallets = app.wallets;
    // The wallet in front was deleted: show the last one, card included.
    if (_index >= wallets.length) {
      _index = _page = wallets.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.positions.length == 1) _pages.jumpToPage(_index);
      });
    }
    final w = wallets[_index];
    final frozen = app.isWalletFrozen(w);
    final currency = w.currencyOr(activeCurrency);
    final since = app.flowsStart(w);
    final flows = since == null ? null : app.flowsSince(w, since);
    final month = monthStart(DateTime.now());

    // Everything converted to the main currency, for the line under the title.
    var total = 0.0;
    var tracked = 0;
    for (final x in wallets) {
      final b = app.balanceOf(x);
      if (b == null) continue;
      tracked++;
      total += x.isForeign(activeCurrency.code) ? b * x.rate! : b;
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          ScreenTitle(
            tr('Portefeuilles'),
            trailing: GlassIconButton(
              icon: Icons.add_rounded,
              tooltip: tr('Nouveau portefeuille'),
              onPressed: () => showWalletForm(context),
            ),
          ),
          // Always present, even empty: if this line came and went, the cards
          // below would change place in the list and be rebuilt while the old
          // ones still hold the page controller.
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, wallets.length > 1 && tracked > 0 ? 4 : 0),
            child: wallets.length > 1 && tracked > 0
                ? Text(
                    tr('{0}{1} au total{2}.', [app.hasForeignWallets ? tr('Environ ') : '', money(total), tracked < wallets.length ? tr(' dans les portefeuilles suivis') : '']),
                    style: context.type.bodyMedium?.copyWith(color: eco.muted),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            // A card's real proportions at the page's width, plus room for its shadow.
            height: (MediaQuery.sizeOf(context).width * 0.86 - 12) / cardAspectRatio + 16,
            child: PageView.builder(
              controller: _pages,
              // Let the front card's glow spill past the strip.
              clipBehavior: Clip.none,
              itemCount: wallets.length + 1,
              onPageChanged: (i) => setState(() {
                _page = i;
                if (i < wallets.length) _index = i;
              }),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: _pages,
                // Cards beside the front one recede a little.
                builder: (context, child) {
                  // Only read the position when exactly one page view holds it.
                  final single = _pages.positions.length == 1;
                  final page = single && _pages.position.haveDimensions ? _pages.page! : _page.toDouble();
                  final d = (page - i).abs().clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 1 - 0.06 * d,
                    child: Opacity(opacity: 1 - 0.4 * d, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: i < wallets.length
                      ? WalletCard(
                          wallet: wallets[i],
                          selected: i == _page,
                          onTap: i == _page ? null : () => _show(i),
                          onMenu: (action) => _menu(wallets[i], action),
                        )
                      : const _NewWalletCard(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _Dots(count: wallets.length + 1, index: _page),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (frozen) _FrozenBanner(needed: app.planToUnfreeze(w)) else MoneyActionsRow(wallet: w),
                if (app.reservedIn(w) > 0.005) ...[
                  const SizedBox(height: 12),
                  _ReservedRow(wallet: w),
                ],
                if (flows != null && !frozen) ...[
                  const SizedBox(height: 12),
                  _FlowsRow(
                    period: since == month ? tr('En {0}', [monthName(month)]) : tr('Depuis le {0}', [shortDate(since!)]),
                    received: flows.received,
                    spent: flows.spent,
                    withdrawn: flows.withdrawn,
                    currency: currency,
                  ),
                ],
                if (app.balanceOf(w) == null && !frozen)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 14, 4, 0),
                    child: Text(
                      tr('Ajoutez l\'argent que vous y mettez, ou indiquez ce que vous avez déjà avec « Corriger le solde » dans le menu de la carte : EcoBudget calculera ce qu\'il reste après chaque dépense.'),
                      style: context.type.bodySmall,
                    ),
                  ),
                _History(wallet: w),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colours of a wallet's card, from the dark corner to the lit one. Cards
/// keep their colour in both themes, like real cards.
(Color, Color) cardColors(WalletType type, {bool frozen = false}) {
  if (frozen) return (const Color(0xFF34384C), const Color(0xFF5D6279));
  return switch (type) {
    WalletType.cash => (const Color(0xFF07523D), const Color(0xFF1FB585)),
    WalletType.bank => (const Color(0xFF0F2A78), const Color(0xFF3F6CF0)),
    WalletType.card => (const Color(0xFF2E1882), const Color(0xFF8460F5)),
    WalletType.savings => (const Color(0xFF6B4300), const Color(0xFFD69A06)),
    WalletType.mobile => (const Color(0xFF064A5C), const Color(0xFF1CA9C7)),
    WalletType.other => (const Color(0xFF262C45), const Color(0xFF59627F)),
  };
}

/// One wallet drawn as a payment card: chip and contactless mark, the
/// balance where the card number goes, the holder's name, and the
/// currency in the corner where a card network's logo would be.
class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.wallet, this.selected = true, this.onTap, this.onMenu});

  final Wallet wallet;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final holder = context.watch<SessionState>().user?.name ?? '';
    final w = wallet;
    final frozen = app.isWalletFrozen(w);
    final (deep, lit) = cardColors(w.type, frozen: frozen);
    final currency = w.currencyOr(activeCurrency);
    // With part of it reserved for the budget, the card shows what is free.
    final reserved = app.reservedIn(w);
    final balance = reserved > 0.005 ? app.freeIn(w) : app.balanceOf(w);
    final main = app.isMainWallet(w) && app.hasSeveralWallets;
    final spentThisMonth = app.spentInWalletCurrency(monthStart(DateTime.now()), w);
    final caption = frozen
        ? tr('Gelé, consultation seulement')
        : reserved > 0.005
        ? tr('Libre, et {0} réservés au budget', [moneyIn(reserved, currency)])
        : w.isForeign(activeCurrency.code)
        ? rateLabel(Currency.byCode(w.currencyCode), w.rate!)
        : spentThisMonth == 0
        ? tr('Rien dépensé ce mois')
        : tr('Ce mois : −{0}', [moneyIn(spentThisMonth, currency)]);
    const white = Colors.white;
    final soft = white.withValues(alpha: 0.72);

    return Semantics(
      button: onTap != null,
      label:
          '${w.name}, ${balance == null ? 'solde pas encore suivi' : moneyIn(balance, currency)}'
          '${frozen ? ', gelé' : ''}',
      child: PaymentCardSurface(
        deep: deep,
        lit: lit,
        glow: selected && !frozen,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Issuer line: wallet name, then the app's mark.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.titleMedium?.copyWith(color: white, shadows: cardEmboss),
                      ),
                      // The type is left out when the name already says it.
                      if (frozen || main || w.type.label != w.name)
                        Text(
                          frozen ? tr('Gelé') : (main ? tr('Principal') : w.type.label),
                          style: context.type.labelSmall?.copyWith(color: soft),
                        ),
                    ],
                  ),
                ),
                if (frozen) Icon(Icons.lock_outline_rounded, color: soft, size: 20) else const EcoMark(size: 26),
                if (onMenu != null)
                  PopupMenuButton<String>(
                    tooltip: tr('Options du portefeuille'),
                    icon: Icon(Icons.more_vert_rounded, color: soft),
                    onSelected: onMenu,
                    itemBuilder: (_) => frozen
                        ? [PopupMenuItem(value: 'delete', child: Text(tr('Supprimer le portefeuille')))]
                        : [
                            PopupMenuItem(
                              value: 'balance',
                              child: Text(balance == null ? tr('Indiquer le solde actuel') : tr('Corriger le solde')),
                            ),
                            PopupMenuItem(value: 'edit', child: Text(tr('Modifier le portefeuille'))),
                            PopupMenuItem(value: 'delete', child: Text(tr('Supprimer le portefeuille'))),
                          ],
                  )
                else
                  const SizedBox(width: 14),
              ],
            ),
            const Spacer(),
            // Chip and contactless mark.
            Row(
              children: [
                CardChip(muted: frozen),
                if (!frozen) ...[const SizedBox(width: 10), Icon(Icons.contactless_outlined, color: soft, size: 24)],
              ],
            ),
            const Spacer(),
            // The balance takes the place of the card number.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: balance == null
                  ? Text(
                      tr('Solde à suivre'),
                      style: context.type.headlineSmall?.copyWith(color: soft, shadows: cardEmboss),
                    )
                  : Text(
                      moneyIn(balance, currency),
                      style: context.type.headlineMedium?.copyWith(
                        color: balance < 0 ? const Color(0xFFFFC2CD) : white,
                        fontFeatures: tabular,
                        letterSpacing: 0.5,
                        shadows: cardEmboss,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            // Holder line, and the currency where the network logo would be.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (holder.isNotEmpty)
                        Text(
                          holder.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.labelMedium?.copyWith(
                            color: white,
                            letterSpacing: 1.6,
                            shadows: cardEmboss,
                          ),
                        ),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.bodySmall?.copyWith(color: soft),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: Text(
                    currency.code,
                    style: TextStyle(
                      fontFamily: displayFont,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      fontSize: 24,
                      height: 1,
                      letterSpacing: -0.5,
                      color: white,
                      shadows: cardEmboss,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewWalletCard extends StatelessWidget {
  const _NewWalletCard();

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final plan = context.watch<PlanState>();
    final count = context.watch<AppState>().wallets.length;
    final atLimit = !plan.canAddWallet(count);
    return Container(
      decoration: eco.glass(radius: 28),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => showWalletForm(context),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: eco.blueInk.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: Icon(atLimit ? Icons.lock_outline_rounded : Icons.add_rounded, color: eco.blueInk),
                ),
                const SizedBox(height: 12),
                Text(tr('Nouveau portefeuille'), style: context.type.titleMedium),
                const SizedBox(height: 4),
                Text(
                  atLimit
                      ? tr('Plus de portefeuilles avec {0}', [Plan.forWalletCount(count + 1).label])
                      : tr('Espèces, banque, carte, épargne…'),
                  textAlign: TextAlign.center,
                  style: context.type.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? eco.blueInk : eco.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// How a wallet's money splits between what is free and what is still
/// reserved for this month's budget.
class _ReservedRow extends StatelessWidget {
  const _ReservedRow({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final w = wallet;
    final currency = w.currencyOr(activeCurrency);
    final reserved = app.reservedIn(w);
    final balance = app.balanceOf(w);
    final free = app.freeIn(w);
    Widget cell(String label, String value, Color? color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.labelSmall),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: color),
          ),
        ],
      ),
    );
    return GlassPanel(
      radius: 20,
      tint: eco.blueInk,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Budget de {0}', [monthName(DateTime.now())]), style: context.type.labelMedium?.copyWith(color: eco.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (free != null) cell(tr('Libre'), moneyIn(free, currency), free < 0 ? eco.coral : null),
              cell(tr('Réservé au budget'), moneyIn(reserved, currency), eco.blueInk),
              if (balance != null) cell(tr('Total'), moneyIn(balance, currency), null),
            ],
          ),
        ],
      ),
    );
  }
}

/// Money in and out of the wallet since its balance has been tracked.
class _FlowsRow extends StatelessWidget {
  const _FlowsRow({
    required this.period,
    required this.received,
    required this.spent,
    required this.withdrawn,
    required this.currency,
  });

  final String period;
  final double received;
  final double spent;
  final double withdrawn;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    Widget cell(String label, String value, Color? color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.labelSmall),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: color),
          ),
        ],
      ),
    );
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(period, style: context.type.labelMedium?.copyWith(color: eco.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              cell(tr('Reçu'), '+${moneyIn(received, currency)}', eco.leaf),
              cell(tr('Dépensé'), '${spent > 0 ? '−' : ''}${moneyIn(spent, currency)}', null),
              if (withdrawn > 0) cell(tr('Retiré'), '−${moneyIn(withdrawn, currency)}', eco.coral),
            ],
          ),
        ],
      ),
    );
  }
}

/// Expenses and money movements of one wallet, newest first. Older ones are
/// listed but greyed out: they happened before the balance was tracked.
class _History extends StatelessWidget {
  const _History({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final w = wallet;
    final history = app.historyOf(w).take(80).toList();
    final start = WalletMath.trackingStart(w, app.deposits);

    final rows = <Widget>[];
    var markedStart = false;
    for (final item in history) {
      final before = start != null && item.date.isBefore(start);
      if (before && !markedStart) {
        markedStart = true;
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 10),
            child: Text(tr('Avant le {0} : pas compté dans le solde', [shortDate(start)]), style: context.type.labelSmall),
          ),
        );
      }
      final tile = item.expense != null
          ? ExpenseTile(
              expense: item.expense!,
              showDate: true,
              onTap: () => ExpenseFormScreen.open(context, item.expense),
            )
          : _DepositTile(wallet: w, deposit: item.deposit!);
      rows.add(before ? Opacity(opacity: 0.55, child: tile) : tile);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(tr('Historique de {0}', [w.name])),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(tr('Aucun mouvement pour l\'instant.'), style: context.type.bodyMedium?.copyWith(color: eco.muted)),
          )
        else
          Grouped(dividerIndent: 72, children: rows),
      ],
    );
  }
}

/// Small wallet chip for the home screen; opens the Wallets tab on it.
class WalletChip extends StatelessWidget {
  const WalletChip({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final w = wallet;
    final frozen = app.isWalletFrozen(w);
    final balance = app.reservedIn(w) > 0.005 ? app.freeIn(w) : app.balanceOf(w);
    final currency = w.currencyOr(activeCurrency);
    return SizedBox(
      width: 168,
      child: Container(
        decoration: eco.glass(radius: 20),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => HomeShell.showWallet(context, w.id),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
              child: Row(
                children: [
                  _MiniCard(type: w.type, frozen: frozen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(w.name, style: context.type.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          balance == null ? tr('À suivre') : moneyIn(balance, currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleSmall?.copyWith(
                            fontFeatures: tabular,
                            color: frozen || balance == null ? eco.muted : (balance < 0 ? eco.coral : null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WalletAvatar extends StatelessWidget {
  const WalletAvatar({super.key, required this.type, this.size = 42, this.frozen = false});

  final WalletType type;
  final double size;

  /// Shows a lock instead of the wallet icon.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final color = frozen ? eco.muted : walletAccent(eco, type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: eco.isDark ? 0.16 : 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(frozen ? Icons.lock_outline_rounded : type.icon, color: color, size: size * 0.52),
    );
  }
}

/// Deletes a wallet after the person has chosen which wallet receives its
/// money and expenses. The only wallet cannot be deleted. Returns true if
/// the wallet was deleted.
Future<bool> deleteWalletFlow(BuildContext context, Wallet wallet) async {
  final app = context.read<AppState>();
  final others = app.wallets.where((w) => w.id != wallet.id).toList();
  if (others.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Impossible de supprimer « {0} »', [wallet.name])),
        content: Text(
          tr('C\'est votre seul portefeuille : il en faut au moins un pour noter vos dépenses. Créez-en un autre pour pouvoir supprimer celui-ci.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Compris'))),
        ],
      ),
    );
    return false;
  }
  // Frozen wallets cannot receive money, except the one that becomes the
  // main wallet (and so active) when the main wallet is deleted.
  final nextMain = app.isMainWallet(wallet) ? others.first : null;
  final targets = others.where((w) => !app.isWalletFrozen(w) || w.id == nextMain?.id).toList();
  final target = await showDialog<Wallet>(
    context: context,
    builder: (_) => _DeleteWalletDialog(wallet: wallet, targets: targets.isEmpty ? others : targets, nextMain: nextMain),
  );
  if (target == null || !context.mounted) return false;
  await app.deleteWallet(wallet, moveTo: target);
  return true;
}

class _DeleteWalletDialog extends StatefulWidget {
  const _DeleteWalletDialog({required this.wallet, required this.targets, this.nextMain});

  final Wallet wallet;
  final List<Wallet> targets;
  final Wallet? nextMain;

  @override
  State<_DeleteWalletDialog> createState() => _DeleteWalletDialogState();
}

class _DeleteWalletDialogState extends State<_DeleteWalletDialog> {
  /// Nothing is chosen at first: the person picks where the money goes.
  String? _targetId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final w = widget.wallet;
    final currency = w.currencyOr(activeCurrency);
    final left = app.balanceOf(w);
    final hasMoney = left != null && left.abs() >= 0.005;
    final share = app.envelope.funds[w.id];
    final main = activeCurrency.code;

    // What the chosen wallet would receive, in its own currency.
    String receives(Wallet t) {
      final inMain = w.isForeign(main) ? left! * w.rate! : left!;
      final inTarget = t.isForeign(main) ? inMain / t.rate! : inMain;
      final sameCurrency = t.currencyOr(activeCurrency).code == currency.code;
      return '${sameCurrency ? 'Recevra' : 'Recevra environ'} ${moneyIn(inTarget, t.currencyOr(activeCurrency))}';
    }

    return AlertDialog(
      title: Text(tr('Supprimer « {0} » ?', [w.name])),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasMoney
                ? tr('Il reste {0} dans ce portefeuille. Choisissez où va cet argent : ses dépenses y seront aussi déplacées.', [moneyIn(left, currency)])
                : tr('Choisissez le portefeuille qui reprend ses dépenses.'),
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: 14),
          for (final t in widget.targets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: t.id == _targetId ? eco.blueInk.withValues(alpha: 0.12) : eco.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: t.id == _targetId ? eco.blueInk : eco.glassBorder, width: t.id == _targetId ? 1.5 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _targetId = t.id),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        WalletAvatar(type: t.type, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                hasMoney
                                    ? receives(t)
                                    : app.balanceOf(t) == null
                                    ? tr('Solde pas encore suivi')
                                    : tr('Solde : {0}', [moneyIn(app.balanceOf(t)!, t.currencyOr(activeCurrency))]),
                                style: context.type.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          t.id == _targetId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: t.id == _targetId ? eco.blueInk : eco.muted,
                          semanticLabel: t.id == _targetId ? tr('Choisi') : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (share != null && share > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Sa part du budget ({0}) passera aussi dans ce portefeuille.', [money(share)]),
                style: context.type.bodySmall,
              ),
            ),
          if (widget.nextMain != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('C\'est votre portefeuille principal : « {0} » le deviendra.', [widget.nextMain!.name]),
                style: context.type.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: _targetId == null
              ? null
              : () => Navigator.pop(context, widget.targets.firstWhere((t) => t.id == _targetId)),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44), backgroundColor: eco.coral),
          child: Text(tr('Supprimer')),
        ),
      ],
    );
  }
}

/// Explains a frozen item and offers the plan that unfreezes it.
/// [frozen] is the full phrase, e.g. "La catégorie « Animaux » est gelée".
Future<void> explainFrozen(BuildContext context, {required String frozen, required Plan needed}) => showPlans(
  context,
  suggested: needed,
  reason:
      tr('{0} : votre formule actuelle ne l\'inclut plus. Tout reste consultable, et {1} permet de l\'utiliser de nouveau.', [frozen, needed.label]),
);

/// Creates (no [wallet]) or edits a wallet. Creating past the plan's limit
/// opens the plans screen first.
Future<void> showWalletForm(BuildContext context, [Wallet? wallet]) async {
  if (wallet == null) {
    final count = context.read<AppState>().wallets.length;
    final needed = Plan.forWalletCount(count + 1);
    final ok = await requirePlan(
      context,
      allowed: context.read<PlanState>().canAddWallet(count),
      needed: needed,
      reason:
          '${WalletsScreen.planSummary(context.read<PlanState>().plan)} '
          '${needed == Plan.pro ? 'Pro ajoute un deuxième portefeuille.' : 'Premium permet d\'en créer autant que vous voulez.'}',
    );
    if (!ok || !context.mounted) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WalletForm(wallet: wallet),
  );
}

class _WalletForm extends StatefulWidget {
  const _WalletForm({this.wallet});

  final Wallet? wallet;

  @override
  State<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends State<_WalletForm> {
  late final TextEditingController _name = TextEditingController(text: widget.wallet?.name ?? '');
  late WalletType _type;
  late Currency _currency;
  late final TextEditingController _rate;
  String? _error;
  String? _rateError;

  bool get _foreign => _currency.code != activeCurrency.code;

  @override
  void initState() {
    super.initState();
    final existing = widget.wallet;
    _currency = existing?.currencyOr(activeCurrency) ?? activeCurrency;
    final r = existing?.rate;
    _rate = TextEditingController(
      text: r == null || !_foreign ? '' : r.toStringAsFixed(r.truncateToDouble() == r ? 0 : 2).replaceAll('.', ','),
    );
    if (existing != null) {
      _type = existing.type;
    } else {
      // Suggest the kind the person does not have yet.
      final used = context.read<AppState>().wallets.map((w) => w.type).toSet();
      _type = used.contains(WalletType.cash) ? WalletType.bank : WalletType.cash;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _pickCurrency() async {
    if (!context.read<PlanState>().canUseForeignCurrency) {
      final ok = await requirePlan(
        context,
        allowed: false,
        needed: Plan.premium,
        reason:
            tr('Avec Premium, gardez un portefeuille dans une autre devise, par exemple un compte Paysera en euros à côté de vos dinars.'),
      );
      if (!ok || !mounted) return;
    }
    final picked = await showCurrencyPicker(context, selected: _currency);
    if (picked != null) {
      setState(() {
        _currency = picked;
        _rateError = null;
      });
    }
  }

  Future<void> _pickType(WalletType t) async {
    if (!context.read<PlanState>().canUseWalletType(t)) {
      final ok = await requirePlan(
        context,
        allowed: false,
        needed: Plan.premium,
        reason: tr('Les cartes, l\'épargne, le paiement mobile et les noms libres sont inclus dans Premium.'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _type = t);
  }

  Future<void> _save() async {
    final plan = context.read<PlanState>().plan;
    final typed = _name.text.trim();
    final name = plan.customWalletNames && typed.isNotEmpty ? typed : _type.label;
    if (plan.customWalletNames && typed.isEmpty) {
      setState(() => _error = tr('Donnez un nom à ce portefeuille.'));
      return;
    }
    double? rate;
    if (_foreign) {
      rate = parseAmount(_rate.text);
      if (rate == null || rate <= 0) {
        setState(() => _rateError = tr('Entrez le taux auquel vous changez cet argent.'));
        return;
      }
    }
    final app = context.read<AppState>();
    final existing = widget.wallet;
    final base = existing ?? Wallet(id: newId('w'), name: name, type: _type, createdAt: DateTime.now());
    await app.saveWallet(
      _foreign
          ? base.copyWith(name: name, type: _type, currencyCode: _currency.code, rate: rate)
          : base.copyWith(name: name, type: _type, mainCurrency: true),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (await deleteWalletFlow(context, widget.wallet!) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final planState = context.watch<PlanState>();
    final canDelete = widget.wallet != null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.wallet == null ? tr('Nouveau portefeuille') : tr('Modifier le portefeuille'),
            style: context.type.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(tr('Type'), style: context.type.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in WalletType.values)
                ChoiceChip(
                  selected: _type == t,
                  onSelected: (_) => _pickType(t),
                  avatar: Icon(
                    planState.canUseWalletType(t) ? t.icon : Icons.lock_outline_rounded,
                    size: 17,
                    color: _type == t ? eco.onBlue : eco.muted,
                  ),
                  label: Text(t.label),
                  labelStyle: context.type.labelMedium?.copyWith(color: _type == t ? eco.onBlue : eco.ink),
                  side: BorderSide(color: _type == t ? eco.blue : eco.hairline),
                ),
            ],
          ),
          if (planState.plan.customWalletNames) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 30,
              decoration: InputDecoration(labelText: tr('Nom'), hintText: tr('Ex. : Carte Visa, Livret A'), errorText: _error),
            ),
          ],
          const SizedBox(height: 12),
          _CurrencyRow(
            currency: _currency,
            locked: !planState.canUseForeignCurrency && !_foreign,
            onTap: _pickCurrency,
          ),
          if (_foreign) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 17, end: 10),
                  child: Text('1 ${_currency.symbol} =', style: context.type.titleMedium),
                ),
                Expanded(
                  child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (_rateError != null) setState(() => _rateError = null);
                    },
                    decoration: InputDecoration(
                      labelText: tr('Taux de change'),
                      suffixText: activeCurrency.symbol,
                      errorText: _rateError,
                      helperText: widget.wallet == null
                          ? tr('Le taux auquel vous changez réellement votre argent.')
                          : tr('Un nouveau taux s\'applique aux prochaines dépenses.'),
                      helperMaxLines: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(widget.wallet == null ? tr('Créer le portefeuille') : tr('Enregistrer'))),
          if (canDelete)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: eco.coral),
              child: Text(tr('Supprimer ce portefeuille')),
            ),
        ],
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.currency, required this.locked, required this.onTap});

  final Currency currency;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final main = currency.code == activeCurrency.code;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(locked ? Icons.lock_outline_rounded : Icons.currency_exchange_rounded, size: 20, color: eco.muted),
              const SizedBox(width: 14),
              Expanded(child: Text(tr('Devise'), style: context.type.titleSmall)),
              Flexible(
                child: Text(
                  main ? '${currency.code} (principale)' : currency.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyMedium?.copyWith(color: eco.muted),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: eco.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _FrozenBanner extends StatelessWidget {
  const _FrozenBanner({required this.needed});

  final Plan needed;

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
              Text(tr('Portefeuille gelé'), style: context.type.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text(
              tr('Votre formule ne l\'inclut plus. Son solde et son historique restent consultables, mais il ne peut plus recevoir de dépenses, d\'ajouts ni de transferts.'),
              style: context.type.bodyMedium?.copyWith(color: eco.muted),
            ),
          ),
          TextButton(
            onPressed: () => showPlans(context, suggested: needed),
            child: Text(tr('Le réactiver avec {0}', [needed.label])),
          ),
        ],
      ),
    );
  }
}

class _DepositTile extends StatelessWidget {
  const _DepositTile({required this.wallet, required this.deposit});

  final Wallet wallet;
  final Deposit deposit;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final app = context.read<AppState>();
    final outgoing = deposit.sourceWalletId == wallet.id;
    final value = outgoing
        ? -deposit.sentAmount
        : deposit.kind == DepositKind.withdrawal
        ? -deposit.amount
        : deposit.amount;
    final other = outgoing ? deposit.walletId : deposit.sourceWalletId;
    final otherName = other == null || !app.wallets.any((w) => w.id == other) ? null : app.walletById(other).name;

    final (icon, label) = switch (deposit.kind) {
      DepositKind.transfer when outgoing => (Icons.north_east_rounded, tr('Vers {0}', [otherName ?? tr('un autre portefeuille')])),
      DepositKind.transfer => (Icons.south_west_rounded, tr('Depuis {0}', [otherName ?? tr('un autre portefeuille')])),
      DepositKind.withdrawal => (Icons.remove_rounded, deposit.note.isEmpty ? tr('Retrait') : deposit.note),
      DepositKind.adjustment => (Icons.tune_rounded, deposit.note.isEmpty ? tr('Correction du solde') : deposit.note),
      DepositKind.income => (Icons.add_rounded, deposit.note.isEmpty ? tr('Ajout d\'argent') : deposit.note),
    };
    final withdrawal = deposit.kind == DepositKind.withdrawal;
    final color = withdrawal ? eco.coral : (value < 0 ? eco.muted : eco.leaf);
    final currency = wallet.currencyOr(activeCurrency);
    final subtitle = deposit.kind == DepositKind.transfer && deposit.note.isNotEmpty
        ? '${deposit.note}, ${shortDate(deposit.date)}'
        : shortDate(deposit.date);

    final involvesFrozen = [
      deposit.walletId,
      deposit.sourceWalletId,
    ].any((id) => id != null && app.wallets.any((x) => x.id == id && app.isWalletFrozen(x)));
    return InkWell(
      onTap: () => involvesFrozen
          ? explainFrozen(context, frozen: tr('Ce mouvement concerne un portefeuille gelé'), needed: Plan.premium)
          : deposit.kind == DepositKind.adjustment
          ? _confirmDelete(context)
          : showMoneyForm(context, MoneyAction.of(deposit.kind), deposit: deposit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.type.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${value < 0 ? '−' : '+'}${moneyIn(value.abs(), currency)}',
              style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: withdrawal ? eco.coral : (value < 0 ? null : eco.leaf)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await confirm(
      context,
      title: tr('Supprimer cette correction ?'),
      message: tr('Le solde sera recalculé sans elle.'),
      confirmLabel: tr('Supprimer'),
      destructive: true,
    );
    if (ok) await app.deleteDeposit(deposit);
  }
}

/// A wallet's card in miniature, for the home chips.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.type, required this.frozen});

  final WalletType type;
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final (deep, lit) = cardColors(type, frozen: frozen);
    return Container(
      width: 38,
      height: 38 / cardAspectRatio,
      padding: const EdgeInsetsDirectional.fromSTEB(5, 0, 0, 0),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [deep, lit]),
        boxShadow: [BoxShadow(color: deep.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: frozen
          ? const Icon(Icons.lock_outline_rounded, size: 12, color: Colors.white70)
          : const CardChip(size: Size(10, 8)),
    );
  }
}
