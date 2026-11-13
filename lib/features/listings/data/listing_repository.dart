import 'dart:convert';

import 'listing.dart';

/// Where listings come from. The app only knows this interface, so an
/// implementation backed by the Go API can replace the sample one.
abstract interface class ListingRepository {
  Future<List<Listing>> search([
    ListingFilters filters = const ListingFilters(),
  ]);
  Future<Listing?> bySlug(String slug);
}

/// SAMPLE DATA. Serves assets/data/listings.json, which is mirrored from the
/// web repository by tool/sync_web_data.mjs. The ids match the listings
/// seeded in the backend's in-memory dev store.
class SampleListingRepository implements ListingRepository {
  const SampleListingRepository(this.listings);

  factory SampleListingRepository.fromJson(String source) =>
      SampleListingRepository([
        for (final listing in jsonDecode(source) as List)
          Listing.fromJson(listing as Map<String, dynamic>),
      ]);

  final List<Listing> listings;

  @override
  Future<List<Listing>> search([
    ListingFilters filters = const ListingFilters(),
  ]) async => listings.where(filters.matches).toList();

  @override
  Future<Listing?> bySlug(String slug) async {
    for (final listing in listings) {
      if (listing.slug == slug) return listing;
    }
    return null;
  }
}
