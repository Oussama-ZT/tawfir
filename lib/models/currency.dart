import '../l10n/l10n.dart';

class Currency {
  final String code;
  final String symbol;
  final String _name;

  /// The currency's name in the current language.
  String get name => tr(_name);
  final int decimals;

  const Currency(this.code, this.symbol, this._name, [this.decimals = 2]);

  static const List<Currency> all = [
    Currency('MAD', 'DH', 'Dirham marocain'),
    Currency('EUR', '€', 'Euro'),
    Currency('USD', '\$', 'Dollar américain'),
    Currency('GBP', '£', 'Livre sterling'),
    Currency('CAD', '\$ CA', 'Dollar canadien'),
    Currency('CHF', 'CHF', 'Franc suisse'),
    Currency('AUD', '\$ AU', 'Dollar australien'),
    Currency('DZD', 'DA', 'Dinar algérien'),
    Currency('TND', 'DT', 'Dinar tunisien', 3),
    Currency('EGP', 'E£', 'Livre égyptienne'),
    Currency('SAR', 'SAR', 'Riyal saoudien'),
    Currency('AED', 'AED', 'Dirham des Émirats'),
    Currency('QAR', 'QAR', 'Riyal qatari'),
    Currency('XOF', 'FCFA', 'Franc CFA (Afrique de l\'Ouest)', 0),
    Currency('XAF', 'FCFA', 'Franc CFA (Afrique centrale)', 0),
    Currency('NGN', '₦', 'Naira nigérian'),
    Currency('ZAR', 'R', 'Rand sud-africain'),
    Currency('TRY', '₺', 'Livre turque'),
    Currency('INR', '₹', 'Roupie indienne'),
    Currency('CNY', '¥', 'Yuan chinois'),
    Currency('JPY', '¥', 'Yen japonais', 0),
    Currency('KRW', '₩', 'Won sud-coréen', 0),
    Currency('BRL', 'R\$', 'Real brésilien'),
    Currency('MXN', '\$ MX', 'Peso mexicain'),
    Currency('SEK', 'kr', 'Couronne suédoise'),
    Currency('RUB', '₽', 'Rouble russe'),
  ];

  static const Currency fallback = Currency('USD', '\$', 'Dollar américain');

  static Currency byCode(String? code) =>
      all.firstWhere((c) => c.code == code, orElse: () => fallback);

  /// Best guess from the phone's region, used as the default at sign-up.
  static Currency forCountry(String? countryCode) {
    const map = {
      'MA': 'MAD', 'FR': 'EUR', 'BE': 'EUR', 'DE': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'PT': 'EUR',
      'NL': 'EUR', 'IE': 'EUR', 'AT': 'EUR', 'FI': 'EUR', 'GR': 'EUR', 'LU': 'EUR',
      'US': 'USD', 'GB': 'GBP', 'CA': 'CAD', 'CH': 'CHF', 'AU': 'AUD', 'DZ': 'DZD', 'TN': 'TND',
      'EG': 'EGP', 'SA': 'SAR', 'AE': 'AED', 'QA': 'QAR', 'SN': 'XOF', 'CI': 'XOF', 'ML': 'XOF',
      'BF': 'XOF', 'BJ': 'XOF', 'TG': 'XOF', 'NE': 'XOF', 'CM': 'XAF', 'GA': 'XAF', 'CG': 'XAF',
      'TD': 'XAF', 'NG': 'NGN', 'ZA': 'ZAR', 'TR': 'TRY', 'IN': 'INR', 'CN': 'CNY', 'JP': 'JPY',
      'KR': 'KRW', 'BR': 'BRL', 'MX': 'MXN', 'SE': 'SEK', 'RU': 'RUB',
    };
    return byCode(map[countryCode?.toUpperCase()]);
  }
}
