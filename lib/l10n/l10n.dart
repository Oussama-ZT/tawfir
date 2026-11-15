import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:intl/intl.dart';

import 'ar.dart';
import 'en.dart';

/// The app's languages. French is the source: its texts are the keys of the
/// other dictionaries, and anything not translated yet shows in French.
enum AppLanguage {
  fr('Français'),
  en('English'),
  ar('العربية');

  const AppLanguage(this.nativeName);

  /// The language's name in itself, as shown in the language picker.
  final String nativeName;

  Locale get locale => Locale(name);
  bool get isRtl => this == ar;

  /// Locale for dates: Algerian Arabic has Maghreb month names and Latin digits.
  String get dateLocale => this == ar ? 'ar_DZ' : name;

  static AppLanguage? byCode(String? code) {
    for (final l in values) {
      if (l.name == code) return l;
    }
    return null;
  }

  /// The phone's language if the app has it, French otherwise.
  static AppLanguage get system => byCode(PlatformDispatcher.instance.locale.languageCode) ?? fr;
}

AppLanguage _language = AppLanguage.fr;

/// The language texts are currently shown in.
AppLanguage get appLanguage => _language;

void setAppLanguage(AppLanguage l) {
  _language = l;
  Intl.defaultLocale = l.dateLocale;
}

const _dictionaries = <AppLanguage, Map<String, String>>{
  AppLanguage.en: en,
  AppLanguage.ar: ar,
};

/// Translates a French text into the current language. Values go in
/// [args] and replace `{0}`, `{1}`… so each language can place them where
/// its grammar wants.
String tr(String french, [List<Object?> args = const []]) {
  var text = _dictionaries[_language]?[french] ?? french;
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

/// Whether [n] takes the singular: French says "0 dépense", English
/// "0 expenses". Arabic texts here use the plural form for counts.
bool isSingular(num n) => switch (_language) {
      AppLanguage.fr => n <= 1,
      AppLanguage.en => n == 1,
      AppLanguage.ar => n == 1,
    };
