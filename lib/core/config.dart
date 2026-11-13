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
}
