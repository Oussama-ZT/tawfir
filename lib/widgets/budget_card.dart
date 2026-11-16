import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/budget_math.dart';
import '../state/app_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import 'brand.dart';
import 'month_track.dart';
import 'payment_card.dart';
import '../l10n/l10n.dart';

/// The month's budget drawn as a payment card: what is left where the card
/// number goes, the neon month track beside the chip, the end of the month
/// as the expiry date, and the share used where a network logo would be.
/// Indigo within budget, amber from 80 % used, crimson once exceeded.
class BudgetCard extends StatelessWidget {
  const BudgetCard({super.key, required this.month, this.onTap, this.onEdit});

  final DateTime month;
  final VoidCallback? onTap;

  /// Shows a pencil in the corner.
  final VoidCallback? onEdit;

  static const _onTrack = (Color(0xFF141A5E), Color(0xFF4B55F0));
  static const _near = (Color(0xFF5E3A06), Color(0xFFD9861C));
  static const _over = (Color(0xFF5C0B26), Color(0xFFE0335B));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holder = context.watch<SessionState>().user?.name ?? '';
    final now = DateTime.now();
    final current = sameMonth(month, now);
    // Every expense of the month counts against the budget of that month.
    final st = state.budgetStatus(month);
    final budget = st.budget;
    final hasBudget = st.hasBudget;
    final over = st.level == BudgetLevel.exceeded;
    final days = st.daysInMonth;
    final today = current ? now.day : (month.isBefore(now) ? days : 1);
    final name = monthName(month);
    final elided = 'aeiouéâ'.contains(name[0]);

    final status = !hasBudget
        ? tr('Dépensé en {0}', [name])
        : over
        ? tr('Budget dépassé')
        : tr('Reste à dépenser');
    final amount = !hasBudget ? st.spent : (over ? st.overspent : st.remaining);
    final detail = !hasBudget
        ? (onTap != null ? tr('Touchez la carte pour fixer votre budget.') : tr('Aucun budget fixé.'))
        : over
        ? tr('Dépensé : {0} sur {1}', [money(st.spent), money(budget)])
        : current
        ? tr("Jusqu'à {0} par jour, sur {1}", [moneyApprox(st.dailyAllowance), money(budget)])
        : tr('{0} dépensés sur {1}', [money(st.spent), money(budget)]);
    final spent = st.spent;
    // Indigo within budget, amber when getting close, crimson beyond.
    final (deep, lit) = switch (st.level) {
      BudgetLevel.exceeded => _over,
      BudgetLevel.approaching => _near,
      _ => _onTrack,
    };
    const white = Colors.white;
    final soft = white.withValues(alpha: 0.72);

    return Semantics(
      button: onTap != null,
      label: '$status : ${money(amount)}. $detail',
      excludeSemantics: true,
      child: PaymentCardSurface(
        deep: deep,
        lit: lit,
        glow: true,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          elided ? tr("Budget d'{0}", [name]) : tr('Budget de {0}', [name]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleMedium?.copyWith(color: white, shadows: cardEmboss),
                        ),
                        Text(status, style: context.type.labelSmall?.copyWith(color: soft)),
                      ],
                    ),
                  ),
                  const EcoMark(size: 26),
                  if (onEdit != null)
                    IconButton(
                      tooltip: tr('Modifier le budget global'),
                      onPressed: onEdit,
                      icon: Icon(Icons.edit_outlined, color: soft, size: 20),
                    )
                  else
                    const SizedBox(width: 14),
                ],
              ),
              const Spacer(),
              // The chip, with the days of the month lit beside it.
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 14),
                child: Row(
                  children: [
                    const CardChip(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: MonthTrack(days: days, today: today, usedRatio: hasBudget ? spent / budget : null),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  money(amount),
                  style: context.type.headlineMedium?.copyWith(
                    color: white,
                    fontFeatures: tabular,
                    letterSpacing: 0.5,
                    shadows: cardEmboss,
                  ),
                ),
              ),
              // Dropped on small cards so the holder line keeps its room.
              if (box.maxHeight > 196)
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodySmall?.copyWith(color: soft),
                ),
              const SizedBox(height: 6),
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
                          current ? tr('Jour {0} sur {1}', [now.day, days]) : monthYear(month),
                          style: context.type.bodySmall?.copyWith(color: soft),
                        ),
                      ],
                    ),
                  ),
                  // Expiry: the budget starts again next month.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tr('Jusqu\'au'), style: context.type.labelSmall?.copyWith(color: soft, fontSize: 10)),
                      Text(
                        '$days/${month.month.toString().padLeft(2, '0')}',
                        style: context.type.labelMedium?.copyWith(
                          color: white,
                          fontFeatures: tabular,
                          shadows: cardEmboss,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: Text(
                      hasBudget ? percent(st.ratio) : activeCurrency.code,
                      style: TextStyle(
                        fontFamily: displayFont,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        fontSize: 24,
                        height: 1,
                        letterSpacing: -0.5,
                        color: over ? const Color(0xFFFFD1DA) : white,
                        shadows: cardEmboss,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
