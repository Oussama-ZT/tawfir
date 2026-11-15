import 'package:material_ui/material_ui.dart';

import '../models/insight.dart';
import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

class InsightStyle {
  final Color color;
  final IconData icon;

  /// Singular noun, pluralized by [count].
  final String noun;

  /// Heading for a group of insights of this kind.
  final String heading;

  const InsightStyle(this.color, this.icon, this.noun, this.heading);

  static InsightStyle of(BuildContext context, InsightKind kind) {
    final eco = context.eco;
    return switch (kind) {
      InsightKind.danger => InsightStyle(eco.coral, Icons.error_outline_rounded, 'alerte', tr('Alertes')),
      InsightKind.anomaly => InsightStyle(eco.violet, Icons.troubleshoot_rounded, 'anomalie', tr('Dépenses inhabituelles')),
      InsightKind.warning => InsightStyle(eco.amber, Icons.speed_rounded, 'avertissement', tr('À surveiller')),
      InsightKind.tip => InsightStyle(eco.sky, Icons.lightbulb_outline_rounded, 'conseil', tr('Conseils')),
      InsightKind.success => InsightStyle(eco.leaf, Icons.verified_outlined, 'réussite', tr('Réussites')),
    };
  }

  /// "1 alerte", "3 alertes": singular and plural are separate texts,
  /// since each language builds its plural differently.
  String count(int n) => isSingular(n) ? tr('{0} $noun', [n]) : tr('{0} ${noun}s', [n]);
}

/// One insight as a row inside a [Grouped] list.
class InsightRow extends StatelessWidget {
  const InsightRow({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final style = InsightStyle.of(context, insight.kind);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: style.color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(style.icon, size: 20, color: style.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: context.type.titleSmall),
                const SizedBox(height: 3),
                Text(insight.message, style: context.type.bodyMedium?.copyWith(color: context.eco.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
