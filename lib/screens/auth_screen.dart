import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/currency.dart';
import '../services/auth/auth_backend.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/brand.dart';
import '../widgets/currency_picker.dart';
import '../l10n/l10n.dart';
import '../widgets/language_picker.dart';

/// Sign in (Google, Apple on Apple devices, or e-mail) before using the app.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  late Currency _currency =
      Currency.forCountry(WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(bool signUp) {
    if (signUp == _signUp) return;
    setState(() {
      _signUp = signUp;
      _error = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionState>();
    try {
      if (_signUp) {
        await session.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          currency: _currency,
        );
      } else {
        await session.login(_email.text, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Google or Apple. The currency picked below (or guessed from the region)
  /// is used if this creates the account.
  Future<void> _social(Future<void> Function(SessionState session, Currency currency) signIn) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signIn(context.read<SessionState>(), _currency);
    } on AuthException catch (e) {
      if (mounted && !e.cancelled) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (AuthValidators.email(email) != null) {
      setState(() => _error = tr('Entrez d\'abord votre e-mail ci-dessus.'));
      return;
    }
    try {
      await context.read<SessionState>().sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('E-mail envoyé à {0} pour choisir un nouveau mot de passe.', [email]))),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickCurrency() async {
    final c = await showCurrencyPicker(context, selected: _currency);
    if (c != null) setState(() => _currency = c);
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: GlowBackdrop(
          night: true,
          child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(28, 24, 28, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const EcoMark(size: 52),
                                const Spacer(),
                                LanguageButton(color: eco.onBlue),
                              ],
                            ),
                            const Spacer(),
                            const SizedBox(height: 32),
                            Text('Tawfir',
                                style: context.type.displayLarge?.copyWith(color: eco.onBlue, fontSize: 52)),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: Text(
                                tr('Notez vos dépenses, tenez votre budget et épargnez pour ce qui compte.'),
                                style: context.type.bodyLarge?.copyWith(color: eco.onBlueMuted, fontSize: 17),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _panel(context),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final eco = context.eco;
    final session = context.watch<SessionState>();
    return Container(
      decoration: BoxDecoration(
        color: eco.sheet.withValues(alpha: eco.isDark ? 0.88 : 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: eco.heroBorder)),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SocialButton.google(onPressed: _busy ? null : () => _social((s, c) => s.signInWithGoogle(c))),
            if (Platform.isIOS || Platform.isMacOS) ...[
              const SizedBox(height: 10),
              _SocialButton.apple(onPressed: _busy ? null : () => _social((s, c) => s.signInWithApple(c))),
            ],
            const _OrDivider(),
            _ModeSwitch(signUp: _signUp, onChanged: _switchMode),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _signUp
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.givenName],
                        decoration: InputDecoration(labelText: tr('Prénom')),
                        validator: AuthValidators.name,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('Mot de passe'),
                helperText: _signUp ? tr('Au moins 6 caractères.') : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? tr('Afficher le mot de passe') : tr('Masquer le mot de passe'),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: AuthValidators.password,
            ),
            if (!_signUp && session.supportsPasswordReset)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: _busy ? null : _resetPassword, child: Text(tr('Mot de passe oublié ?'))),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _signUp
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _CurrencyField(currency: _currency, onTap: _pickCurrency),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: eco.coral),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: context.type.bodyMedium?.copyWith(color: eco.coral)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: eco.onBlue),
                    )
                  : Text(_signUp ? tr('Créer mon compte') : tr('Se connecter')),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: eco.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    session.isCloud
                        ? tr('Vos données sont protégées et liées à votre compte.')
                        : tr('Votre compte et vos données restent sur ce téléphone.'),
                    style: context.type.bodySmall,
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

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    Widget option(String label, bool value) {
      final selected = signUp == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: selected ? eco.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: context.type.labelMedium?.copyWith(color: selected ? eco.ink : eco.muted),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: eco.surfaceSunken, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [option(tr('Connexion'), false), option(tr('Inscription'), true)]),
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.currency, required this.onTap});

  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: eco.surfaceSunken, borderRadius: BorderRadius.circular(10)),
                child: Text(currency.symbol,
                    style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, color: eco.ink,
                        fontSize: currency.symbol.length > 2 ? 11 : 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Devise'), style: context.type.bodySmall),
                    Text('${currency.name} (${currency.code})', style: context.type.titleSmall),
                  ],
                ),
              ),
              Text(tr('Changer'), style: context.type.labelMedium?.copyWith(color: eco.blueInk)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Continuer avec Google" / "Continuer avec Apple".
class _SocialButton extends StatelessWidget {
  const _SocialButton.google({required this.onPressed}) : apple = false;
  const _SocialButton.apple({required this.onPressed}) : apple = true;

  final bool apple;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Apple's button is black on light backgrounds and white on dark ones.
    final bg = apple ? (dark ? Colors.white : Colors.black) : eco.surface;
    final fg = apple ? (dark ? Colors.black : Colors.white) : eco.ink;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        side: apple ? BorderSide.none : BorderSide(color: eco.hairline),
        minimumSize: const Size.fromHeight(54),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (apple) Icon(Icons.apple, size: 24, color: fg) else const _GoogleLogo(size: 20),
          const SizedBox(width: 12),
          Text(apple ? tr('Continuer avec Apple') : tr('Continuer avec Google')),
        ],
      ),
    );
  }
}

/// The four-colour Google "G".
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.2;
    final rect = (Offset.zero & size).deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    double deg(double d) => d * 3.1415926535 / 180;
    canvas.drawArc(rect, deg(0), deg(45), false, p..color = _blue);
    canvas.drawArc(rect, deg(45), deg(100), false, p..color = _green);
    canvas.drawArc(rect, deg(145), deg(70), false, p..color = _yellow);
    canvas.drawArc(rect, deg(215), deg(105), false, p..color = _red);
    final c = size.center(Offset.zero);
    canvas.drawRect(Rect.fromLTRB(c.dx, c.dy - w / 2, size.width, c.dy + w / 2), Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(tr('ou avec votre e-mail'), style: context.type.bodySmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
