import 'package:flutter/foundation.dart' show kDebugMode;

import 'location.dart';

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

  /// The website, for pages the app hands over to (detailed reports, how
  /// statistics are counted).
  static const webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://rightproperty365.com',
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

  /// OpenStreetMap's public tiles, as the website uses outside production.
  /// Their usage policy does not allow them for a published app, so they are
  /// the default in debug builds only.
  static const _osmTiles = MapTiles(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
  );

  /// The map's tiles: the configured source, OpenStreetMap in a debug build,
  /// or null (no map; search stays a list).
  static MapTiles? get mapTiles => mapEnabled
      ? const MapTiles(urlTemplate: mapTileUrl, attribution: mapAttribution)
      : kDebugMode
      ? _osmTiles
      : null;
}
