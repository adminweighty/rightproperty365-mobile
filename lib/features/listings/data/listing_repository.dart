import 'listing.dart';
import 'sample_listings.dart';

/// Where listings come from. The app only knows this interface, so an
/// implementation backed by the Go API can replace the sample one.
abstract interface class ListingRepository {
  Future<List<Listing>> search([
    ListingFilters filters = const ListingFilters(),
  ]);
  Future<List<Listing>> featured();
  Future<Listing?> bySlug(String slug);
}

/// SAMPLE DATA. Serves the hard-coded listings in sample_listings.dart.
class SampleListingRepository implements ListingRepository {
  const SampleListingRepository();

  @override
  Future<List<Listing>> search([
    ListingFilters filters = const ListingFilters(),
  ]) async => sampleListings.where(filters.matches).toList();

  @override
  Future<List<Listing>> featured() async =>
      sampleListings.where((listing) => listing.featured).toList();

  @override
  Future<Listing?> bySlug(String slug) async {
    for (final listing in sampleListings) {
      if (listing.slug == slug) return listing;
    }
    return null;
  }
}
