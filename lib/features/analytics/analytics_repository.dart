import '../../core/api/api_client.dart';

/// One day of a report, in the market's local time.
class AnalyticsDay {
  const AnalyticsDay({
    required this.date,
    required this.views,
    required this.uniqueViews,
    required this.enquiries,
  });

  final DateTime date;
  final int views;
  final int uniqueViews;
  final int enquiries;
}

class AnalyticsTopListing {
  const AnalyticsTopListing({
    required this.title,
    required this.reference,
    required this.views,
    required this.enquiries,
    this.slug,
  });

  final String title;
  final String reference;

  /// Null unless the listing is public now.
  final String? slug;
  final int views;
  final int enquiries;
}

/// `AnalyticsReport` (API 0.30.0): first-party figures, not Google
/// Analytics figures.
class AnalyticsReport {
  const AnalyticsReport({
    required this.period,
    required this.from,
    required this.to,
    required this.timezone,
    required this.totals,
    required this.daily,
    required this.sources,
    required this.devices,
    required this.topListings,
    this.conversion,
    this.ctr,
    this.conversionDefinition,
    this.ctrDefinition,
    this.label,
    this.nearRealTime = false,
    this.refreshedAt,
    this.filteredBotEvents = 0,
    this.lateEventsDropped = 0,
    this.definitionsPath = '/analytics-definitions',
    this.listingsCount,
    this.assignedOnly = false,
  });

  factory AnalyticsReport.fromJson(Map<String, dynamic> json) {
    List<({String key, int count})> counts(Object? list) => [
      for (final item in (list as List?) ?? const [])
        (
          key: (item as Map<String, dynamic>)['key'] as String,
          count: item['count'] as int? ?? 0,
        ),
    ];
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return AnalyticsReport(
      period: json['period'] as String? ?? '30d',
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      timezone: json['timezone'] as String? ?? '',
      totals: {
        for (final e in totals.entries)
          if (e.value is int) e.key: e.value as int,
      },
      daily: [
        for (final d in (json['daily'] as List?) ?? const [])
          AnalyticsDay(
            date: DateTime.parse((d as Map<String, dynamic>)['date'] as String),
            views: d['views'] as int? ?? 0,
            uniqueViews: d['unique_views'] as int? ?? 0,
            enquiries: d['enquiries'] as int? ?? 0,
          ),
      ],
      conversion: (json['conversion'] as num?)?.toDouble(),
      ctr: (json['ctr'] as num?)?.toDouble(),
      conversionDefinition: json['conversion_definition'] as String?,
      ctrDefinition: json['ctr_definition'] as String?,
      sources: counts(json['sources']),
      devices: counts(json['devices']),
      label: json['label'] as String?,
      nearRealTime: json['near_real_time'] == true,
      refreshedAt: switch (json['refreshed_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      filteredBotEvents: json['filtered_bot_events'] as int? ?? 0,
      lateEventsDropped: json['late_events_dropped'] as int? ?? 0,
      definitionsPath:
          json['definitions_path'] as String? ?? '/analytics-definitions',
      topListings: [
        for (final t in (json['top_listings'] as List?) ?? const [])
          AnalyticsTopListing(
            title: (t as Map<String, dynamic>)['title'] as String? ?? '',
            reference: t['reference'] as String? ?? '',
            slug: t['slug'] as String?,
            views: t['views'] as int? ?? 0,
            enquiries: t['enquiries'] as int? ?? 0,
          ),
      ],
      listingsCount: json['listings_count'] as int?,
      assignedOnly: json['scope'] == 'assigned',
    );
  }

  final String period;
  final DateTime from;
  final DateTime to;
  final String timezone;

  /// impressions, views, unique_views, contact_clicks, video_plays, saves,
  /// enquiries, viewing_requests, appointments_confirmed, relists.
  final Map<String, int> totals;
  final List<AnalyticsDay> daily;
  final double? conversion;
  final double? ctr;
  final String? conversionDefinition;
  final String? ctrDefinition;
  final List<({String key, int count})> sources;
  final List<({String key, int count})> devices;
  final List<AnalyticsTopListing> topListings;

  /// "Near real time, may change" for the last 24 hours.
  final String? label;
  final bool nearRealTime;
  final DateTime? refreshedAt;
  final int filteredBotEvents;
  final int lateEventsDropped;
  final String definitionsPath;
  final int? listingsCount;

  /// An agent sees only the listings assigned to them.
  final bool assignedOnly;

  int total(String key) => totals[key] ?? 0;
}

/// Professionals' listing statistics (`/v1/analytics/...`). Throws
/// [ApiFailure]: 403 for a member whose role manages no listings, 404 for
/// someone outside the organisation.
abstract interface class AnalyticsRepository {
  /// [period] is `24h`, `7d` or `30d`.
  Future<AnalyticsReport> organisation(String organisationId, String period);
}

class ApiAnalyticsRepository implements AnalyticsRepository {
  ApiAnalyticsRepository(this._api);

  final ApiClient _api;

  @override
  Future<AnalyticsReport> organisation(
    String organisationId,
    String period,
  ) async => AnalyticsReport.fromJson(
    (await _api.get(
      '/v1/analytics/organisations/${Uri.encodeComponent(organisationId)}'
      '?period=${Uri.encodeQueryComponent(period)}',
    )).body,
  );
}
