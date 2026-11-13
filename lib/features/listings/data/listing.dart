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

/// A bundled sample photo. Real photos will come from object storage.
class ListingImage {
  const ListingImage({required this.asset, required this.alt});

  /// Asset path, for example `assets/images/listing-house-borrowdale.jpg`.
  final String asset;

  /// What the photo shows, for screen readers.
  final String alt;
}

class Listing {
  const Listing({
    required this.id,
    required this.slug,
    required this.image,
    required this.reference,
    required this.listedBy,
    required this.publishedAt,
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
    this.pricePerMonth = false,
    this.bedrooms,
    this.bathrooms,
    this.floorArea,
    this.landArea,
    this.featured = false,
  });

  /// Parses one entry of assets/data/listings.json (the web's `Listing`).
  factory Listing.fromJson(Map<String, dynamic> json) {
    final price = json['price'] as Map<String, dynamic>;
    final advertiser = json['advertiser'] as Map<String, dynamic>;
    final image = json['image'] as Map<String, dynamic>;
    return Listing(
      id: json['id'] as String,
      slug: json['slug'] as String,
      image: ListingImage(
        asset: 'assets/images/${image['file']}',
        alt: image['alt'] as String,
      ),
      reference: json['reference'] as String,
      listedBy: json['listedBy'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      title: json['title'] as String,
      deal: DealType.values.byName(json['deal'] as String),
      category: ListingCategory.values.byName(json['category'] as String),
      propertyType: json['propertyType'] as String,
      price: Money(price['amount'] as String, price['currency'] as String),
      pricePerMonth: json['pricePeriod'] == 'month',
      suburb: json['suburb'] as String,
      city: json['city'] as String,
      marketCode: json['marketCode'] as String,
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      floorArea: json['floorArea'] as int?,
      landArea: json['landArea'] as int?,
      summary: json['summary'] as String,
      description: json['description'] as String,
      features: List<String>.from(json['features'] as List),
      advertiser: Advertiser(
        name: advertiser['name'] as String,
        kind: advertiser['kind'] == 'agency'
            ? AdvertiserKind.agency
            : AdvertiserKind.privateSeller,
        verified: advertiser['verified'] as bool,
      ),
      featured: json['featured'] as bool? ?? false,
    );
  }

  final String id;
  final String slug;
  final ListingImage image;
  final String reference;

  /// The assigned agent, or the owner for a private sale.
  final String listedBy;

  /// UTC instant the current 90-day publication cycle started.
  final DateTime publishedAt;
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
