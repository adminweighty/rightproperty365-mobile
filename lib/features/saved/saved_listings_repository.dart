import '../../core/api/api_client.dart';
import '../../core/format.dart';

/// A saved property (`SavedListing`, API 0.27.0). When it is no longer
/// available the listing is the snapshot from when it was last public, and
/// it has no slug: it is never linked back to its page or into search.
class SavedListing {
  const SavedListing({
    required this.listingId,
    required this.savedAt,
    required this.available,
    required this.title,
    required this.reference,
    this.unavailableReason,
    this.unavailableLabel,
    this.slug,
    this.price,
    this.pricePeriod,
    this.city,
    this.country,
    this.category,
  });

  factory SavedListing.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>? ?? const {};
    final price = listing['price'] as Map<String, dynamic>?;
    final available = json['available'] == true;
    return SavedListing(
      listingId: json['listing_id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      available: available,
      unavailableReason: json['unavailable_reason'] as String?,
      unavailableLabel: json['unavailable_label'] as String?,
      // Only an available listing may be linked to.
      slug: available ? listing['slug'] as String? : null,
      title: listing['title'] as String? ?? 'Saved property',
      reference: listing['reference'] as String? ?? '',
      price: price == null
          ? null
          : Money(price['amount'] as String, price['currency'] as String),
      pricePeriod: listing['price_period'] as String?,
      city: (listing['city'] as Map<String, dynamic>?)?['label'] as String?,
      country:
          (listing['country'] as Map<String, dynamic>?)?['name'] as String?,
      category:
          (listing['category'] as Map<String, dynamic>?)?['label'] as String?,
    );
  }

  final String listingId;
  final DateTime savedAt;
  final bool available;

  /// EXPIRED, LET, SOLD or WITHDRAWN.
  final String? unavailableReason;

  /// The API's wording, such as "Let" or "No longer listed".
  final String? unavailableLabel;
  final String? slug;
  final String title;
  final String reference;
  final Money? price;
  final String? pricePeriod;
  final String? city;
  final String? country;
  final String? category;

  String get place => [?city, ?country].join(', ');

  String? get priceText => price == null
      ? null
      : '${formatMoney(price!)}${pricePeriod == null ? '' : ' / $pricePeriod'}';
}

/// The signed-in account's saved properties (`/v1/me/saved-listings`).
abstract interface class SavedListingsRepository {
  /// Every saved listing that is still public (at most 1000), for hearts.
  Future<Set<String>> ids();

  /// One page, newest saved first.
  Future<({List<SavedListing> items, int total, int totalPages})> list({
    int page = 1,
    int pageSize = 24,
  });

  /// Saves a listing; saving it again changes nothing. A listing that is not
  /// public now is `404 LISTING_NOT_FOUND`.
  Future<void> save(String listingId);

  /// Removes it; removing an unknown one is not an error.
  Future<void> remove(String listingId);
}

class ApiSavedListingsRepository implements SavedListingsRepository {
  ApiSavedListingsRepository(this._api);

  final ApiClient _api;
  static const _base = '/v1/me/saved-listings';

  @override
  Future<Set<String>> ids() async {
    final body = (await _api.get('$_base/ids')).body;
    return {for (final id in (body['ids'] as List?) ?? const []) id as String};
  }

  @override
  Future<({List<SavedListing> items, int total, int totalPages})> list({
    int page = 1,
    int pageSize = 24,
  }) async {
    final body = (await _api.get('$_base?page=$page&page_size=$pageSize')).body;
    return (
      items: [
        for (final item in (body['items'] as List?) ?? const [])
          SavedListing.fromJson(item as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
      totalPages: body['total_pages'] as int? ?? 0,
    );
  }

  @override
  Future<void> save(String listingId) async {
    try {
      await _api.putJson('$_base/${Uri.encodeComponent(listingId)}', const {});
    } on ApiFailure catch (failure) {
      throw failure.code == 'LISTING_NOT_FOUND'
          ? failure.withMessage(
              'This property is no longer listed, so it cannot be saved.',
            )
          : failure;
    }
  }

  @override
  Future<void> remove(String listingId) async =>
      _api.delete('$_base/${Uri.encodeComponent(listingId)}');
}
