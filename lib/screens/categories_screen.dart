import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/plan.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../utils/ids.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import 'paywall_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

/// Default categories, plus the person's own ones (Pro and Premium).
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final plan = context.watch<PlanState>();
    final eco = context.eco;

    final frozen = !plan.canCustomizeCategories;
    Widget row(ExpenseCategory c, {VoidCallback? onTap, bool locked = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Opacity(opacity: locked ? 0.5 : 1, child: CategoryAvatar(category: c, size: 38)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: context.type.titleSmall?.copyWith(color: locked ? eco.muted : null)),
                      if (locked) Text(tr('Gelée'), style: context.type.bodySmall),
                    ],
                  ),
                ),
                if (locked)
                  Icon(Icons.lock_outline_rounded, color: eco.muted, size: 20)
                else if (onTap != null)
                  Icon(Icons.chevron_right_rounded, color: eco.muted),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Catégories')),
        actions: [
          IconButton(
            tooltip: tr('Nouvelle catégorie'),
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showCategoryForm(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
        children: [
          SectionHeader(tr('Mes catégories')),
          if (app.customCategories.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: eco.glass(radius: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.canCustomizeCategories
                        ? tr('Créez vos propres catégories : animaux, enfants, sport, cadeaux…')
                        : tr('Avec Pro, créez vos propres catégories : animaux, enfants, sport, cadeaux…'),
                    style: context.type.bodyMedium?.copyWith(color: eco.muted),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showCategoryForm(context),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(plan.canCustomizeCategories ? tr('Créer une catégorie') : tr('Voir les formules')),
                  ),
                ],
              ),
            )
          else
            Grouped(
              dividerIndent: 68,
              children: [
                for (final c in app.customCategories)
                  row(
                    c,
                    locked: frozen,
                    onTap: frozen
                        ? () => explainFrozen(context, frozen: tr('La catégorie « {0} » est gelée', [c.label]), needed: Plan.pro)
                        : () => showCategoryForm(context, c),
                  ),
              ],
            ),
          SectionHeader(tr('Catégories de base')),
          Grouped(
            dividerIndent: 68,
            children: [for (final c in ExpenseCategory.defaults) row(c)],
          ),
        ],
      ),
    );
  }
}

/// Creates (no [category]) or edits a custom category. Returns the saved
/// category. Creating one on Starter opens the plans screen first.
Future<ExpenseCategory?> showCategoryForm(BuildContext context, [ExpenseCategory? category]) async {
  if (category == null) {
    final ok = await requirePlan(context,
        allowed: context.read<PlanState>().canCustomizeCategories,
        needed: Plan.pro,
        reason: tr('Starter utilise les catégories de base. Avec Pro, créez les vôtres.'));
    if (!ok || !context.mounted) return null;
  }
  return showModalBottomSheet<ExpenseCategory>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategoryForm(category: category),
  );
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.category});

  final ExpenseCategory? category;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _name = TextEditingController(text: widget.category?.label ?? '');
  late String _icon = widget.category?.iconKey ?? ExpenseCategory.icons.keys.first;
  late Color _color = widget.category?.color ?? ExpenseCategory.palette[2];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _name.text.trim();
    if (label.isEmpty) {
      setState(() => _error = tr('Donnez un nom à cette catégorie.'));
      return;
    }
    final taken = ExpenseCategory.visible
        .any((c) => c.id != widget.category?.id && c.label.toLowerCase() == label.toLowerCase());
    if (taken) {
      setState(() => _error = tr('Une catégorie porte déjà ce nom.'));
      return;
    }
    final saved = widget.category == null
        ? ExpenseCategory.custom(id: newId('c'), label: label, iconKey: _icon, color: _color)
        : widget.category!.copyWith(label: label, iconKey: _icon, color: _color);
    await context.read<AppState>().saveCategory(saved);
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final c = widget.category!;
    final ok = await confirm(context,
        title: tr('Supprimer « {0} » ?', [c.label]),
        message: tr('Ses dépenses passeront dans « Autre » et son budget sera retiré.'),
        confirmLabel: tr('Supprimer'),
        destructive: true);
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteCategory(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final preview = ExpenseCategory.custom(
      id: 'preview',
      label: _name.text.trim().isEmpty ? tr('Catégorie') : _name.text.trim(),
      iconKey: _icon,
      color: _color,
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(category: preview, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Text(widget.category == null ? tr('Nouvelle catégorie') : tr('Modifier la catégorie'),
                    style: context.type.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 24,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(labelText: tr('Nom'), hintText: tr('Ex. : Animaux, Enfants'), errorText: _error),
          ),
          const SizedBox(height: 8),
          Text(tr('Icône'), style: context.type.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in ExpenseCategory.icons.entries)
                _Choice(
                  selected: _icon == e.key,
                  color: _color,
                  onTap: () => setState(() => _icon = e.key),
                  child: Icon(e.value, size: 22, color: _icon == e.key ? Colors.white : _color),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(tr('Couleur'), style: context.type.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in ExpenseCategory.palette)
                Semantics(
                  button: true,
                  selected: _color == c,
                  child: GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: _color == c ? eco.ink : Colors.transparent, width: 2.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(widget.category == null ? tr('Créer la catégorie') : tr('Enregistrer')),
          ),
          if (widget.category != null)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: eco.coral),
              child: Text(tr('Supprimer cette catégorie')),
            ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.color, required this.onTap, required this.child});

  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );
  }
}
