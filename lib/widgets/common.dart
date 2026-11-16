import 'package:material_ui/material_ui.dart';

import '../models/currency.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../l10n/l10n.dart';

/// iOS-style grouped list: one flat surface, rows separated by inset hairlines.
class Grouped extends StatelessWidget {
  const Grouped({super.key, required this.children, this.dividerIndent = 16, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final double dividerIndent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: eco.glass(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: dividerIndent, height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Large screen title used at the top of each tab.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.type.displayMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 24, 0, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.type.titleLarge)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Compact month switcher shaped as a pill.
class MonthSelector extends StatelessWidget {
  const MonthSelector({super.key, required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final isCurrent = sameMonth(month, DateTime.now());
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        decoration: eco.glass(radius: 40),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: tr('Mois précédent'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => onChanged(addMonths(month, -1)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
              child: Text(monthYear(month), textAlign: TextAlign.center, style: context.type.titleSmall),
            ),
            IconButton(
              tooltip: tr('Mois suivant'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: isCurrent ? null : () => onChanged(addMonths(month, 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: eco.surfaceSunken, borderRadius: BorderRadius.circular(24)),
              child: Icon(icon, size: 34, color: eco.blueInk),
            ),
            const SizedBox(height: 20),
            Text(title, style: context.type.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(message, style: context.type.bodyMedium?.copyWith(color: eco.muted), textAlign: TextAlign.center),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Thin progress bar: blue while comfortable, amber near the limit, coral past it.
class BudgetProgress extends StatelessWidget {
  const BudgetProgress({super.key, required this.spent, required this.budget, this.height = 6});

  final double spent;
  final double budget;
  final double height;

  static Color colorFor(BuildContext context, double ratio) {
    final eco = context.eco;
    if (ratio > 1) return eco.coral;
    if (ratio >= 0.8) return eco.amber;
    return eco.blueInk;
  }

  /// A recessed track with a lit bar that glows in its status colour.
  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final color = colorFor(context, ratio);
    return Semantics(
      label: tr('{0} % utilisé', [(ratio * 100).round()]),
      child: Container(
        height: height,
        decoration: BoxDecoration(color: eco.surfaceSunken, borderRadius: BorderRadius.circular(height)),
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => FractionallySizedBox(
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
                boxShadow: value > 0 ? eco.neon(color, strength: 0.6) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Amount in the display face with the currency symbol set smaller beside it.
class AmountText extends StatelessWidget {
  const AmountText(this.value, {super.key, this.style, this.symbolColor, this.currency});

  final double value;
  final TextStyle? style;
  final Color? symbolColor;

  /// Defaults to the account's currency.
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? context.type.displayMedium)!.copyWith(fontFeatures: tabular);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: amountOnly(value, currency)),
        TextSpan(
          text: ' ${currency?.symbol ?? currencySymbol}',
          style: base.copyWith(
            fontSize: (base.fontSize ?? 32) * 0.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: symbolColor ?? base.color,
          ),
        ),
      ]),
      style: base,
      // The number and its symbol read left to right in every language.
      textDirection: TextDirection.ltr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Asks for an amount. Returns null if cancelled. With [allowZero], an empty
/// field or 0 returns 0 (used to remove a budget).
Future<double?> showAmountDialog(
  BuildContext context, {
  required String title,
  double? initial,
  String? helper,
  bool allowZero = false,
  String? confirmLabel,
  Currency? currency,
  double? max,
  String? maxError,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _AmountDialog(
      title: title,
      initial: initial,
      helper: helper,
      allowZero: allowZero,
      confirmLabel: confirmLabel ?? tr('Enregistrer'),
      currency: currency,
      max: max,
      maxError: maxError,
    ),
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    this.initial,
    this.helper,
    required this.allowZero,
    required this.confirmLabel,
    this.currency,
    this.max,
    this.maxError,
  });

  /// Highest amount accepted, with the message shown beyond it.
  final double? max;
  final String? maxError;

  final String title;
  final double? initial;
  final String? helper;
  final bool allowZero;
  final String confirmLabel;
  final Currency? currency;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _controller = TextEditingController(
      text: initial == null || initial <= 0 ? '' : initial.toStringAsFixed(initial.truncateToDouble() == initial ? 0 : 2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && widget.allowZero) {
      Navigator.pop(context, 0.0);
      return;
    }
    final value = parseAmount(text);
    if (value == null || value < 0 || (value == 0 && !widget.allowZero)) {
      setState(() => _error = tr('Entrez un montant supérieur à 0.'));
      return;
    }
    if (widget.max != null && value > widget.max! + 0.005) {
      setState(() => _error = widget.maxError ?? tr('Au plus {0}.', [money(widget.max!)]));
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: context.type.headlineSmall?.copyWith(fontFeatures: tabular),
        decoration: InputDecoration(
          suffixText: widget.currency?.symbol ?? currencySymbol,
          helperText: widget.helper,
          helperMaxLines: 3,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String? confirmLabel, bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 44),
            backgroundColor: destructive ? ctx.eco.coral : null,
          ),
          child: Text(confirmLabel ?? tr('Confirmer')),
        ),
      ],
    ),
  );
  return result ?? false;
}
