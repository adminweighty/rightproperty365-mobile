/// Build-time configuration, set with `--dart-define`.
abstract final class AppConfig {
  /// Base URL of the RightProperty365 Go API, without a trailing slash.
  ///
  /// The default reaches a server on the development machine from the Android
  /// emulator. Use http://localhost:8080 for the iOS simulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// Version of the privacy notice a customer consents to with a request.
  static const privacyNoticeVersion = '2026-11-draft';

  /// The demo signing code a test server accepts (staging: 1234), shown as a
  /// hint on the signing screen. Empty for production builds.
  static const demoSigningCode = String.fromEnvironment('DEMO_SIGNING_CODE');

  /// Map tiles: a URL template such as `https://tiles.example.com/{z}/{x}/{y}.png`
  /// and the attribution the provider requires. Empty means no map: search
  /// stays a list. Use the same source as the website; a provider key goes in
  /// the URL here, never in the code.
  static const mapTileUrl = String.fromEnvironment('MAP_TILE_URL');
  static const mapAttribution = String.fromEnvironment('MAP_ATTRIBUTION');

  static bool get mapEnabled =>
      mapTileUrl.isNotEmpty && mapAttribution.isNotEmpty;
}
