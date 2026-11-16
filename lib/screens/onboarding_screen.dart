import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/currency.dart';
import '../models/insight.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import '../widgets/insight_card.dart';
import '../widgets/month_track.dart';
import '../l10n/l10n.dart';
import '../widgets/language_picker.dart';

/// Three-step introduction shown once, on the first launch, before sign-in.
/// Each step previews the real interface rather than an abstract picture.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Step {
  const _Step(this.title, this.body, this.preview);
  final String title;
  final String body;
  final Widget preview;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static List<_Step> get _steps => [
        _Step(
          tr('Notez une dépense en quelques secondes'),
          tr('Un montant, une catégorie, c\'est fait. Retrouvez ensuite tout votre mois, jour par jour.'),
          const _ExpensesPreview(),
        ),
        _Step(
          tr('Voyez où en est votre budget'),
          tr('Chaque trait est un jour du mois. Quand le jaune dépasse le point d\'aujourd\'hui, vous dépensez plus vite que prévu.'),
          const _BudgetPreview(),
        ),
        _Step(
          tr('Recevez des conseils, atteignez vos objectifs'),
          tr('Tawfir repère les dépenses inhabituelles et calcule combien mettre de côté chaque mois. Tout reste sur votre téléphone.'),
          const _AdvicePreview(),
        ),
      ];

  bool get _isLast => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    // Sample amounts use the currency of the phone's region until sign-in.
    activeCurrency = Currency.forCountry(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => context.read<SessionState>().finishIntro();

  void _next() {
    if (_isLast) return _finish();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(_index + 1);
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: GlowBackdrop(
          night: true,
          child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 12, 0),
                child: Row(
                  children: [
                    const EcoMark(size: 30),
                    const SizedBox(width: 10),
                    Text('Tawfir', style: context.type.titleLarge?.copyWith(color: eco.onBlue)),
                    const Spacer(),
                    LanguageButton(color: eco.onBlueMuted),
                    AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        onPressed: _isLast ? null : _finish,
                        style: TextButton.styleFrom(foregroundColor: eco.onBlueMuted),
                        child: Text(tr('Passer')),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _StepPage(step: _steps[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(28, 8, 24, 20),
                child: Row(
                  children: [
                    Semantics(
                      label: tr('Étape {0} sur {1}', [_index + 1, _steps.length]),
                      child: Row(
                        children: [
                          for (var i = 0; i < _steps.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              width: i == _index ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _index ? eco.yellow : eco.onBlue.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: eco.yellow,
                        foregroundColor: eco.onYellow,
                        minimumSize: const Size(148, 54),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: Text(_isLast ? tr('Commencer') : tr('Suivant')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(28, 16, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: 340, child: step.preview),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(step.title, style: context.type.headlineMedium?.copyWith(color: eco.onBlue)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(step.body, style: context.type.bodyLarge?.copyWith(color: eco.onBlueMuted)),
          ),
        ],
      ),
    );
  }
}

/// Step 1: a few expenses as they appear in the list, and the add button.
class _ExpensesPreview extends StatelessWidget {
  const _ExpensesPreview();

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    Widget row(String category, String note, double amount) {
      final c = ExpenseCategory.byId(category);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CategoryAvatar(category: c, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note, style: context.type.titleSmall),
                  Text(c.label, style: context.type.bodySmall),
                ],
              ),
            ),
            Text(money(amount), style: context.type.titleSmall?.copyWith(fontFeatures: tabular)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 28, end: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Extra room at the bottom so the add button never covers a row.
          Container(
            padding: const EdgeInsets.only(bottom: 26),
            decoration: eco.glass(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 2),
                  child: Text(tr('Aujourd\'hui'), style: context.type.labelSmall),
                ),
                row('food', tr('Marché'), 245),
                const Divider(indent: 68, height: 1),
                row('transport', tr('Tram'), 14),
                const Divider(indent: 68, height: 1),
                row('restaurant', tr('Déjeuner'), 85),
              ],
            ),
          ),
          Positioned(
            right: -12,
            bottom: -28,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: eco.yellow,
                shape: BoxShape.circle,
                border: Border.all(color: eco.blue, width: 5),
              ),
              child: Icon(Icons.add_rounded, size: 30, color: eco.onYellow),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: the home screen's budget block with the month track.
class _BudgetPreview extends StatelessWidget {
  const _BudgetPreview();

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    Widget legend(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: context.type.labelSmall?.copyWith(color: eco.onBlueMuted)),
          ],
        );

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 18),
      decoration: BoxDecoration(color: eco.blueDeep, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Reste à dépenser'), style: context.type.titleSmall?.copyWith(color: eco.onBlueMuted)),
          const SizedBox(height: 4),
          AmountText(
            1840,
            style: context.type.displayMedium?.copyWith(color: eco.onBlue),
            symbolColor: eco.onBlueMuted,
          ),
          const SizedBox(height: 18),
          const MonthTrack(days: 30, today: 14, usedRatio: 0.58),
          const SizedBox(height: 12),
          Row(
            children: [
              legend(eco.yellow, tr('Budget utilisé')),
              const SizedBox(width: 16),
              legend(eco.onBlue, tr('Aujourd\'hui')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Step 3: an unusual-expense alert and a savings goal.
class _AdvicePreview extends StatelessWidget {
  const _AdvicePreview();

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Grouped(
      children: [
        InsightRow(
          insight: Insight(
            kind: InsightKind.anomaly,
            title: tr('Dépense inhabituelle'),
            message: tr('Shopping : {0}, environ 4 fois votre dépense habituelle.', [money(2400)]),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
          child: Row(
            children: [
              ProgressRing(
                progress: 0.62,
                size: 48,
                stroke: 5,
                child: Text('62 %', style: context.type.labelSmall?.copyWith(color: eco.ink, fontSize: 11)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Voyage à Marrakech'), style: context.type.titleSmall),
                    const SizedBox(height: 3),
                    Text(tr('Mettez {0} de côté par mois pour partir en juin.', [money(450)]),
                        style: context.type.bodyMedium?.copyWith(color: eco.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
