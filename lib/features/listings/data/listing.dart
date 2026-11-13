import '../../../core/format.dart';

enum DealType {
  sale('For sale'),
  rent('To rent');

  const DealType(this.label);
  final String label;
}

enum ListingCategory {
  residential('Residential'),
  commercial('Commercial'),
  land('Land');

  const ListingCategory(this.label);
  final String label;
}

enum AdvertiserKind { agency, privateSeller }

/// Tint of the placeholder artwork shown until real photos exist.
enum ListingTone { primary, accent, neutral }

class Advertiser {
  const Advertiser({
    required this.name,
    required this.kind,
    required this.verified,
  });
  final String name;
  final AdvertiserKind kind;
  final bool verified;
}

class Listing {
  const Listing({
    required this.id,
    required this.slug,
    required this.reference,
    required this.title,
    required this.deal,
    required this.category,
    required this.propertyType,
    required this.price,
    required this.suburb,
    required this.city,
    required this.marketCode,
    required this.summary,
    required this.description,
    required this.features,
    required this.advertiser,
    required this.tone,
    this.pricePerMonth = false,
    this.bedrooms,
    this.bathrooms,
    this.floorArea,
    this.landArea,
    this.featured = false,
  });

  final String id;
  final String slug;
  final String reference;
  final String title;
  final DealType deal;
  final ListingCategory category;
  final String propertyType;
  final Money price;
  final bool pricePerMonth;
  final String suburb;
  final String city;
  final String marketCode;
  final int? bedrooms;
  final int? bathrooms;
  final int? floorArea;
  final int? landArea;
  final String summary;
  final String description;
  final List<String> features;
  final Advertiser advertiser;
  final bool featured;
  final ListingTone tone;

  String get location => '$suburb, $city';

  /// One sentence for screen readers, so a card reads as a single item.
  String get spokenSummary => [
    deal.label,
    title,
    location,
    '${formatMoney(price)}${pricePerMonth ? ' per month' : ''}',
    if (bedrooms != null) '$bedrooms bedrooms',
    if (bathrooms != null) '$bathrooms bathrooms',
  ].join(', ');
}

class ListingFilters {
  const ListingFilters({this.deal, this.category, this.query = ''});
  final DealType? deal;
  final ListingCategory? category;
  final String query;

  bool matches(Listing listing) {
    final term = query.trim().toLowerCase();
    return (deal == null || listing.deal == deal) &&
        (category == null || listing.category == category) &&
        (term.isEmpty ||
            '${listing.title} ${listing.suburb} ${listing.city} ${listing.propertyType}'
                .toLowerCase()
                .contains(term));
  }
}
