import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 42});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(category.icon, color: category.color, size: size * 0.52),
    );
  }
}

/// Expense row for a [Grouped] list.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, this.onTap, this.showDate = false});

  final Expense expense;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final cat = ExpenseCategory.byId(expense.categoryId);
    final eco = context.eco;
    final title = expense.note.isNotEmpty ? expense.note : cat.label;
    final refund = expense.isRefund;
    final subtitle = [
      if (expense.note.isNotEmpty) cat.label,
      if (refund) tr('remboursement'),
    ].join(', ');
    // Paid from a wallet in another currency: show what was paid, and the
    // converted value counted in totals.
    final foreign = expense.isConverted && expense.originalCurrency != activeCurrency.code;
    final outside = context.select<AppState, bool>((s) => s.isOverBudget(expense));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CategoryAvatar(category: cat),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty || outside) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        if (subtitle.isNotEmpty) TextSpan(text: subtitle),
                        if (subtitle.isNotEmpty && outside) const TextSpan(text: ', '),
                        if (outside)
                          TextSpan(
                            text: tr('hors budget'),
                            style: TextStyle(color: eco.coral, fontWeight: FontWeight.w600),
                          ),
                      ]),
                      style: context.type.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // Spent: "−500 DA". Given back: "+500 DA" in green.
                  '${refund ? '+' : '−'}${foreign ? moneyIn(expense.originalAmount!.abs(), Currency.byCode(expense.originalCurrency)) : money(expense.amount.abs())}',
                  style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: refund ? eco.leaf : null),
                ),
                if (showDate || foreign) ...[
                  const SizedBox(height: 2),
                  Text(
                    [if (showDate) shortDate(expense.date), if (foreign) '≈ ${money(expense.amount.abs())}'].join(', '),
                    style: context.type.bodySmall?.copyWith(color: eco.muted, fontFeatures: tabular),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
