/// Saved searches and their alerts (API 0.52.0). A saved search keeps the
/// public search's query string, the same one the website stores.
library;

import '../../core/api/api_client.dart';
import '../listings/data/listing.dart';

enum AlertFrequency {
  instant('INSTANT', 'As soon as they appear'),
  daily('DAILY', 'Once a day'),
  weekly('WEEKLY', 'Once a week'),
  off('OFF', 'No alerts');

  const AlertFrequency(this.wire, this.label);
  final String wire;
  final String label;

  static AlertFrequency from(Object? wire) => values.firstWhere(
    (f) => f.wire == wire,
    orElse: () => AlertFrequency.daily,
  );
}

/// The parameters the app's search has, in the API's query string. Other
/// filters a search saved on the website may carry are kept as they are.
String searchQueryOf(ListingFilters filters) {
  final query = filters.apiQuery;
  return query.isEmpty ? '' : Uri(queryParameters: query).query;
}

/// A summary to name a search by default: "Houses to rent in Avondale".
String searchSummary(ListingFilters f) {
  final what = switch (f.category) {
    ListingCategory.commercial => 'Commercial property',
    ListingCategory.land => 'Land',
    ListingCategory.shortStay => 'Short stays',
    ListingCategory.residential => 'Homes',
    null => 'Property',
  };
  final deal = switch (f.deal) {
    DealType.rent => ' to rent',
    DealType.sale => ' for sale',
    null => '',
  };
  final term = f.query.trim();
  final summary = '$what$deal${term.isEmpty ? '' : ': $term'}';
  return summary.length > 80 ? summary.substring(0, 80) : summary;
}

class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
    required this.frequency,
    this.lastAlertAt,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    query: json['query'] as String? ?? '',
    frequency: AlertFrequency.from(json['frequency']),
    lastAlertAt: DateTime.tryParse(json['last_alert_at'] as String? ?? ''),
  );

  final String id;
  final String name;

  /// As `GET /v1/listings` takes it, for example `deal=rent&q=Avondale`.
  final String query;
  final AlertFrequency frequency;
  final DateTime? lastAlertAt;

  Map<String, String> get parameters =>
      query.isEmpty ? const {} : Uri.splitQueryString(query);

  /// The filters the app's search can show.
  ListingFilters get filters => ListingFilters.fromApiQuery(parameters);

  /// Filters this search has that the app's search does not (price,
  /// bedrooms and the like, saved on the website).
  bool get hasWebOnlyFilters =>
      parameters.keys.any((k) => !const {'q', 'deal', 'category'}.contains(k));
}

class SavedSearchesRepository {
  SavedSearchesRepository(this._api);

  final ApiClient _api;

  static const _base = '/v1/me/saved-searches';

  static SavedSearch _one(ApiResponse r) =>
      SavedSearch.fromJson(switch (r.body['saved_search']) {
        final Map<String, dynamic> s => s,
        _ => r.body,
      });

  Future<List<SavedSearch>> list() async {
    final body = (await _api.get(_base)).body;
    return [
      for (final s in (body['items'] as List?) ?? const [])
        SavedSearch.fromJson(s as Map<String, dynamic>),
    ];
  }

  Future<SavedSearch> create({
    required String name,
    required ListingFilters filters,
    AlertFrequency frequency = AlertFrequency.daily,
  }) async {
    try {
      return _one(
        await _api.postJson(_base, {
          'name': name.trim(),
          'query': searchQueryOf(filters),
          'frequency': frequency.wire,
        }),
      );
    } on ApiFailure catch (failure) {
      throw failure.code == 'SAVED_SEARCH_LIMIT'
          ? failure.withMessage(
              'You have 25 saved searches, the most there can be. Delete one '
              'to save this search.',
            )
          : failure;
    }
  }

  Future<SavedSearch> update(
    String id, {
    String? name,
    AlertFrequency? frequency,
  }) async => _one(
    await _api.patchJson('$_base/${Uri.encodeComponent(id)}', {
      if (name != null) 'name': name.trim(),
      if (frequency != null) 'frequency': frequency.wire,
    }),
  );

  Future<void> delete(String id) =>
      _api.delete('$_base/${Uri.encodeComponent(id)}');
}
