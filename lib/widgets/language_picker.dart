import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';

/// Lets the person pick the app's language, or follow the phone's.
Future<void> showLanguagePicker(BuildContext context) {
  final session = context.read<SessionState>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final eco = ctx.eco;
      Widget option(AppLanguage? l) {
        final selected = session.languageChoice == l;
        return ListTile(
          leading: Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? eco.blueInk : eco.muted,
          ),
          // Each language is written in itself, so anyone can find theirs.
          title: Text(l?.nativeName ?? tr('Automatique'), style: ctx.type.titleMedium),
          subtitle: l == null ? Text(tr('Langue du téléphone : {0}', [AppLanguage.system.nativeName])) : null,
          onTap: () {
            Navigator.pop(ctx);
            session.setLanguage(l);
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(tr('Langue'), style: ctx.type.headlineSmall),
            ),
            option(null),
            for (final l in AppLanguage.values) option(l),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// Compact language button for screens shown before sign-in.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SessionState>().language;
    return TextButton.icon(
      onPressed: () => showLanguagePicker(context),
      style: TextButton.styleFrom(foregroundColor: color),
      icon: const Icon(Icons.translate_rounded, size: 18),
      label: Text(language.nativeName),
    );
  }
}
