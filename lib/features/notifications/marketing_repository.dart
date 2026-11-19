import '../../core/api/api_client.dart';

/// The opt-in wording this app shows, by consent text version. The API
/// names the current version; the app may record consent only to wording
/// it actually showed. Must match the website's wording for each version.
const marketingConsentTexts = {
  'marketing-2026-01':
      'Send me news, tips and offers from RightProperty365 by email. I can '
      'stop them at any time.',
};

class MarketingChange {
  const MarketingChange({
    required this.optIn,
    required this.changedAt,
    this.source,
    this.context,
  });

  factory MarketingChange.fromJson(Map<String, dynamic> json) =>
      MarketingChange(
        optIn: json['marketing_opt_in'] as bool? ?? false,
        changedAt: DateTime.parse(json['changed_at'] as String).toLocal(),
        source: json['source'] as String?,
        context: json['context'] as String?,
      );

  final bool optIn;
  final DateTime changedAt;

  /// web, app or api.
  final String? source;

  /// REGISTRATION, PREFERENCES, MIGRATION, ADMIN or UNSUBSCRIBE.
  final String? context;

  String get where => switch ((context, source)) {
    ('REGISTRATION', _) => 'when you registered',
    ('MIGRATION', _) => 'before this setting existed',
    ('UNSUBSCRIBE', _) => 'from an unsubscribe link',
    ('ADMIN', _) => 'by RightProperty365 support',
    (_, 'app') => 'in the app',
    (_, 'web') => 'on the website',
    _ => '',
  };
}

class MarketingPreferences {
  const MarketingPreferences({
    required this.optIn,
    required this.currentVersion,
    this.last,
    this.history = const [],
  });

  factory MarketingPreferences.fromJson(Map<String, dynamic> json) =>
      MarketingPreferences(
        optIn: json['marketing_opt_in'] as bool? ?? false,
        currentVersion: json['current_consent_text_version'] as String? ?? '',
        last: json['changed_at'] == null
            ? null
            : MarketingChange.fromJson(json),
        history: [
          for (final h in json['history'] as List? ?? const [])
            MarketingChange.fromJson(h as Map<String, dynamic>),
        ],
      );

  final bool optIn;

  /// The wording version to show now.
  final String currentVersion;

  /// The latest change; null when the person never chose.
  final MarketingChange? last;

  /// Newest first, at most 20.
  final List<MarketingChange> history;

  /// The wording for [currentVersion], if this app has it.
  String? get consentText => marketingConsentTexts[currentVersion];
}

class MarketingRepository {
  MarketingRepository(this._api);

  final ApiClient _api;

  static const _path = '/v1/me/marketing-preferences';

  Future<MarketingPreferences> get() async =>
      MarketingPreferences.fromJson((await _api.get(_path)).body);

  /// Opting in records the wording version shown ([version]); setting the
  /// value already held changes nothing.
  Future<MarketingPreferences> set(bool optIn, {String? version}) async {
    try {
      return MarketingPreferences.fromJson(
        (await _api.putJson(
          _path,
          {
            'marketing_opt_in': optIn,
            if (optIn && version != null) 'consent_text_version': version,
          },
          headers: const {'X-Client': 'app'},
        )).body,
      );
    } on ApiFailure catch (failure) {
      if (failure.fields.containsKey('consent_text_version')) {
        throw failure.withMessage(
          'The wording has changed. Check the new wording and try again.',
        );
      }
      rethrow;
    }
  }
}
