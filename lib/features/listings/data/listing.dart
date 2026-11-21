import '../../../core/format.dart';
import '../../../core/terminology.dart';

enum DealType {
  sale('For sale'),
  rent('To rent');

  const DealType(this.label);
  final String label;
}

enum ListingCategory {
  residential('Residential'),
  commercial('Commercial'),
  land('Land'),
  shortStay('Short stay');

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
  const ListingImage({this.asset = '', this.url, required this.alt});

  /// Asset path, for example `assets/images/listing-house-borrowdale.jpg`;
  /// empty for a photo only the API has.
  final String asset;

  /// An uploaded photo served by the API, when there is no bundled one.
  final String? url;

  /// What the photo shows, for screen readers.
  final String alt;
}

/// Where a listing is on the map (API 0.29.0). An approximate one is
/// rounded by the API to about 1 km and is shown as an area, never a pin.
class ListingLocation {
  const ListingLocation({
    required this.latitude,
    required this.longitude,
    this.approximate = false,
  });

  static ListingLocation? fromJson(Object? json) => json is Map<String, dynamic>
      ? ListingLocation(
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
          approximate: json['precision'] == 'APPROXIMATE',
        )
      : null;

  final double latitude;
  final double longitude;
  final bool approximate;
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
    this.position,
    this.hasVideo = false,
    this.closedState,
  });

  /// From the API's public `Listing` (search results and the listing
  /// page). Photo URLs are relative to [apiBase]; the sample photos the API
  /// serves from /assets/images/ are the ones bundled with the app.
  factory Listing.fromApi(
    Map<String, dynamic> json, {
    required String apiBase,
  }) {
    String label(Object? value) => switch (value) {
      {'label': final String l} => l,
      {'name': final String n} => n,
      final String s => s,
      _ => '',
    };
    final price = json['price'] as Map<String, dynamic>;
    final advertiser = json['advertiser'] as Map<String, dynamic>? ?? const {};
    final display = advertiser['display'] as Map<String, dynamic>?;
    final agent = advertiser['agent_display'] as Map<String, dynamic>?;
    final photos = (json['photos'] as List?) ?? const [];
    final photo = photos.isEmpty ? null : photos.first as Map<String, dynamic>;
    final photoUrl = photo?['url'] as String?;
    final variants = (photo?['variants'] as List?) ?? const [];
    String? networkUrl;
    var asset = '';
    if (photoUrl != null && photoUrl.startsWith('/assets/images/')) {
      asset = 'assets/images/${photoUrl.substring('/assets/images/'.length)}';
    } else if (photoUrl != null) {
      final medium = variants.cast<Map<String, dynamic>>().where(
        (v) => (v['width'] as int? ?? 0) <= 1280,
      );
      final chosen = medium.isEmpty ? photoUrl : medium.first['url'] as String;
      networkUrl = chosen.startsWith('http') ? chosen : '$apiBase$chosen';
    }
    final category = (json['category'] as Map<String, dynamic>?)?['code'];
    return Listing(
      id: json['id'] as String,
      slug: json['slug'] as String,
      image: ListingImage(
        asset: asset,
        url: networkUrl,
        alt: photo?['alt'] as String? ?? label(json['title']),
      ),
      reference: json['reference'] as String? ?? '',
      listedBy: label(agent?['name'] ?? display?['name'] ?? advertiser['name']),
      publishedAt: DateTime.parse(
        json['published_at'] as String? ?? '1970-01-01T00:00:00Z',
      ),
      title: json['title'] as String,
      deal: (json['deal'] as Map<String, dynamic>?)?['code'] == 'rent'
          ? DealType.rent
          : DealType.sale,
      category: switch (category) {
        'commercial' => ListingCategory.commercial,
        'land' => ListingCategory.land,
        'short-stay' => ListingCategory.shortStay,
        _ => ListingCategory.residential,
      },
      propertyType: label(json['property_type']),
      price: Money(price['amount'] as String, price['currency'] as String),
      pricePerMonth: json['price_period'] == 'month',
      suburb: label(json['suburb']).isEmpty
          ? label(json['city'])
          : label(json['suburb']),
      city: label(json['city']).isEmpty
          ? label(json['country'])
          : label(json['city']),
      marketCode: json['market_code'] as String? ?? '',
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      floorArea: json['floor_area'] as int?,
      landArea: json['land_area'] as int?,
      summary: json['summary'] as String? ?? '',
      description: json['description'] as String? ?? '',
      features: [
        for (final f in (json['features'] as List?) ?? const []) label(f),
      ],
      advertiser: Advertiser(
        name: label(advertiser['name']),
        kind: advertiser['type'] == 'agency'
            ? AdvertiserKind.agency
            : AdvertiserKind.privateSeller,
        verified: advertiser['verified'] == true,
      ),
      featured: json['featured'] == true,
      position: ListingLocation.fromJson(json['location']),
      hasVideo: json['has_video'] == true,
      closedState: switch (json['closed_state']) {
        final String s when s == 'SOLD' || s == 'LET' => s,
        _ => null,
      },
    );
  }

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

  /// Only listings from the API carry these (the bundled sample has none).
  final ListingLocation? position;
  final bool hasVideo;

  /// `SOLD` or `LET` for 30 days after the advertiser marked it so (API
  /// 0.48.0): the page says so and offers no contact. Null otherwise.
  final String? closedState;

  /// The same listing placed at [where] (a bundled listing, located by the
  /// API).
  Listing withLocation(ListingLocation where) => Listing(
    id: id,
    slug: slug,
    image: image,
    reference: reference,
    listedBy: listedBy,
    publishedAt: publishedAt,
    title: title,
    deal: deal,
    category: category,
    propertyType: propertyType,
    price: price,
    pricePerMonth: pricePerMonth,
    suburb: suburb,
    city: city,
    marketCode: marketCode,
    summary: summary,
    description: description,
    features: features,
    advertiser: advertiser,
    bedrooms: bedrooms,
    bathrooms: bathrooms,
    floorArea: floorArea,
    landArea: landArea,
    featured: featured,
    position: where,
    hasVideo: hasVideo,
    closedState: closedState,
  );

  String get location => '$suburb, $city';

  /// Who a Property Seeker contacts about this listing, in real-estate terms:
  /// a Sales Agent or Lettings Agent for an agency listing, a Property Seller
  /// or Landlord when the owner lists it directly.
  String get contactTitle => advertiser.kind == AdvertiserKind.agency
      ? listingAgentTitle(forSale: deal == DealType.sale)
      : listingOwnerTitle(forSale: deal == DealType.sale);

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

  /// From `GET /v1/listings` parameters (a saved search's query); others
  /// are ignored.
  factory ListingFilters.fromApiQuery(Map<String, String> query) =>
      ListingFilters(
        query: query['q'] ?? '',
        deal: switch (query['deal']) {
          'rent' => DealType.rent,
          'sale' => DealType.sale,
          _ => null,
        },
        category: switch (query['category']) {
          'residential' => ListingCategory.residential,
          'commercial' => ListingCategory.commercial,
          'land' => ListingCategory.land,
          'short-stay' => ListingCategory.shortStay,
          _ => null,
        },
      );

  final DealType? deal;
  final ListingCategory? category;
  final String query;

  /// As `GET /v1/listings` takes them.
  Map<String, String> get apiQuery => {
    if (query.trim().isNotEmpty) 'q': query.trim(),
    'deal': ?deal?.name,
    'category': ?switch (category) {
      null => null,
      ListingCategory.shortStay => 'short-stay',
      final c => c.name,
    },
  };

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
