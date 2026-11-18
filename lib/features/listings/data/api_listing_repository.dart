import '../../../core/api/api_client.dart';
import 'listing.dart';
import 'listing_repository.dart';

/// The area shown on the map, in decimal degrees. The API does not search
/// across the antimeridian, so west is always less than east.
class MapBounds {
  const MapBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double west;
  final double south;
  final double east;
  final double north;

  /// `bbox=west,south,east,north`, at most 6 decimals, clamped to the
  /// ranges the API accepts.
  String get query {
    String f(double v, double limit) =>
        v.clamp(-limit, limit).toStringAsFixed(6);
    return '${f(west, 180)},${f(south, 90)},${f(east, 180)},${f(north, 90)}';
  }

  bool get valid => west < east && south < north;
}

/// One page of map search results.
class MapSearchPage {
  const MapSearchPage({
    required this.listings,
    required this.total,
    required this.mappableTotal,
  });

  final List<Listing> listings;
  final int total;

  /// How many of the matching listings have a location at all.
  final int mappableTotal;
}

/// Listings from the API (`GET /v1/listings`), for the map, and for opening
/// a listing the bundled sample does not have.
class ApiListingSearch {
  ApiListingSearch(this._api, {required this.apiBase});

  final ApiClient _api;
  final String apiBase;

  /// The API's maximum page size for listing search.
  static const pageSize = 48;

  Map<String, String> _filters(ListingFilters filters) => {
    if (filters.query.trim().isNotEmpty) 'q': filters.query.trim(),
    'deal': ?filters.deal?.name,
    'category': ?switch (filters.category) {
      null => null,
      ListingCategory.shortStay => 'short-stay',
      final c => c.name,
    },
  };

  /// Listings with a location matching [filters]: inside [bounds] when
  /// given, otherwise all of them (the first map view).
  Future<MapSearchPage> mappable(
    ListingFilters filters, {
    MapBounds? bounds,
  }) async {
    final query = {
      ..._filters(filters),
      if (bounds != null) 'bbox': bounds.query else 'has_location': 'true',
      'page_size': '$pageSize',
    };
    final body = (await _api.get(
      Uri(path: '/v1/listings', queryParameters: query).toString(),
    )).body;
    final listings = [
      for (final item in (body['items'] as List?) ?? const [])
        Listing.fromApi(item as Map<String, dynamic>, apiBase: apiBase),
    ];
    return MapSearchPage(
      listings: listings,
      total: body['total'] as int? ?? listings.length,
      mappableTotal: body['mappable_total'] as int? ?? listings.length,
    );
  }

  /// How many results the same filters have in all, and how many of them
  /// can be shown on a map.
  Future<({int total, int mappable})> counts(ListingFilters filters) async {
    final body = (await _api.get(
      Uri(
        path: '/v1/listings',
        queryParameters: {..._filters(filters), 'page_size': '1'},
      ).toString(),
    )).body;
    return (
      total: body['total'] as int? ?? 0,
      mappable: body['mappable_total'] as int? ?? 0,
    );
  }

  /// One public listing, or null when it is not public (404 / 410).
  Future<Listing?> bySlug(String slug) async {
    try {
      final body = (await _api.get('/v1/listings/${Uri.encodeComponent(slug)}'))
          .body;
      return Listing.fromApi(
        body['listing'] as Map<String, dynamic>,
        apiBase: apiBase,
      );
    } on ApiFailure catch (failure) {
      if (failure.status == 404 || failure.status == 410) return null;
      rethrow;
    }
  }
}

/// The bundled sample listings for browsing, with the API behind them for a
/// listing the sample does not have (one opened from the map or a link).
class SampleThenApiListingRepository implements ListingRepository {
  SampleThenApiListingRepository(this.sample, this.api);

  final ListingRepository sample;
  final ApiListingSearch api;

  @override
  Future<List<Listing>> search([
    ListingFilters filters = const ListingFilters(),
  ]) => sample.search(filters);

  @override
  Future<Listing?> bySlug(String slug) async {
    final bundled = await sample.bySlug(slug);
    if (bundled != null) return bundled;
    try {
      return await api.bySlug(slug);
    } on ApiFailure {
      return null; // Offline: the listing page says it is not available.
    }
  }
}
