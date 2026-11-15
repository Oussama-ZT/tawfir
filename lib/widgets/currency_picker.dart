import 'package:material_ui/material_ui.dart';

import '../models/currency.dart';
import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// Searchable list of currencies in a bottom sheet. Returns the chosen one.
Future<Currency?> showCurrencyPicker(BuildContext context, {required Currency selected}) {
  return showModalBottomSheet<Currency>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => _CurrencyList(selected: selected, controller: controller),
    ),
  );
}

class _CurrencyList extends StatefulWidget {
  const _CurrencyList({required this.selected, required this.controller});

  final Currency selected;
  final ScrollController controller;

  @override
  State<_CurrencyList> createState() => _CurrencyListState();
}

class _CurrencyListState extends State<_CurrencyList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final q = _query.trim().toLowerCase();
    final items = Currency.all
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
          child: Text(tr('Choisir la devise'), style: context.type.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: tr('Rechercher (euro, USD…)'),
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(tr('Aucune devise ne correspond à « {0} ».', [_query]), style: context.type.bodyMedium))
              : ListView.builder(
                  controller: widget.controller,
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    final isSelected = c.code == widget.selected.code;
                    return Material(
                      color: isSelected ? eco.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected ? eco.blue : eco.surfaceSunken,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  c.symbol,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: displayFont,
                                    fontWeight: FontWeight.w700,
                                    fontSize: c.symbol.length > 2 ? 12 : 16,
                                    color: isSelected ? eco.onBlue : eco.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Text(c.name, style: context.type.titleSmall)),
                              Text(c.code, style: context.type.bodySmall),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_rounded, color: eco.blueInk, size: 20),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
