import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/insight.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/insight_card.dart';
import '../l10n/l10n.dart';

/// Every insight, grouped by kind (alerts first).
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final insights = context.watch<AppState>().insights;
    final eco = context.eco;
    final byKind = <InsightKind, List<Insight>>{};
    for (final i in insights) {
      byKind.putIfAbsent(i.kind, () => []).add(i);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Conseils'))),
      body: insights.isEmpty
          ? EmptyState(
              icon: Icons.lightbulb_outline_rounded,
              title: tr('Rien à signaler'),
              message: tr('Continuez à noter vos dépenses : Tawfir apprend vos habitudes pour repérer ce qui sort de l\'ordinaire.'),
            )
          : ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    tr('Calculés à partir de vos dépenses, de vos budgets et de vos objectifs.'),
                    style: context.type.bodyMedium?.copyWith(color: eco.muted),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in byKind.entries)
                      _CountPill(style: InsightStyle.of(context, e.key), count: e.value.length),
                  ],
                ),
                for (final e in byKind.entries) ...[
                  SectionHeader(InsightStyle.of(context, e.key).heading),
                  Grouped(dividerIndent: 66, children: [for (final i in e.value) InsightRow(insight: i)]),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: eco.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(tr('Analyse faite sur votre téléphone, rien n\'est envoyé.'),
                          style: context.type.bodySmall),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.style, required this.count});

  final InsightStyle style;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: 6),
          Text(style.count(count), style: context.type.labelMedium?.copyWith(color: style.color)),
        ],
      ),
    );
  }
}
