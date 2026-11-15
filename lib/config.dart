/// Settings the team fills in or tunes. See README, section "Mise en ligne".
class AppConfig {
  /// Test version: while real payments are not set up, anyone can try Pro
  /// and Premium for free from the plans screen (nothing is charged, the
  /// choice lasts until the app is closed). On by default for the test
  /// builds; build the public release with `--dart-define=EB_TEST_MODE=false`.
  static const testMode = bool.fromEnvironment('EB_TEST_MODE', defaultValue: true);

  /// RevenueCat public SDK keys (RevenueCat > Project > API keys).
  /// Leave empty until the stores are set up: the plans screen then shows
  /// that subscriptions are not available yet.
  static const revenueCatGoogleKey = ''; // starts with goog_
  static const revenueCatAppleKey = ''; // starts with appl_

  /// RevenueCat entitlement identifiers. The Premium products must unlock
  /// both entitlements (Premium includes everything in Pro).
  static const proEntitlement = 'pro';
  static const premiumEntitlement = 'premium';

  /// RevenueCat offering identifiers, one per paid plan (each with its
  /// monthly and/or annual package).
  static const proOffering = 'pro';
  static const premiumOffering = 'premium';
}
