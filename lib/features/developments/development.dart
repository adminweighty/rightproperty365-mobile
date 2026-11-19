/// The development and investment showcase (API 0.44.0): published
/// projects of verified developers, their phases and unit types. Public
/// answers never carry contact details: customers reach the developer only
/// through an enquiry. The developer's editor and the review queue are on
/// the website.
library;

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../listings/data/listing.dart';
import '../listings/data/video_tour.dart';

String _label(Object? value) => switch (value) {
  {'label': final String l} => l,
  {'name': final String n} => n,
  final String s => s,
  _ => '',
};

/// `{code, label}` of the API.
class Coded {
  const Coded(this.code, this.label);

  static Coded? fromJson(Object? json) => json is Map<String, dynamic>
      ? Coded(json['code'] as String? ?? '', _label(json))
      : null;

  final String code;
  final String label;
}

/// A photo of a project. [asset] is a sample photo bundled with the app
/// (the API serves those from /assets/images/); otherwise [url] is the
/// API's, already made absolute.
class DevelopmentPhoto {
  const DevelopmentPhoto({required this.alt, this.asset, this.url});

  static DevelopmentPhoto? fromJson(Object? json, String apiBase) {
    if (json is! Map<String, dynamic>) return null;
    final url = json['url'] as String?;
    if (url == null) return null;
    final alt = json['alt'] as String? ?? '';
    if (url.startsWith('/assets/images/')) {
      return DevelopmentPhoto(
        alt: alt,
        asset: 'assets/images/${url.substring('/assets/images/'.length)}',
      );
    }
    final variants = [
      for (final v in (json['variants'] as List?) ?? const [])
        v as Map<String, dynamic>,
    ]..sort((a, b) => (a['width'] as int? ?? 0) - (b['width'] as int? ?? 0));
    final medium = variants.where((v) => (v['width'] as int? ?? 0) >= 800);
    final chosen = medium.isEmpty ? url : medium.first['url'] as String;
    return DevelopmentPhoto(
      alt: alt,
      url: chosen.startsWith('http') ? chosen : '$apiBase$chosen',
    );
  }

  final String alt;
  final String? asset;
  final String? url;
}

/// The developer: name, verified and logo only. Never contact details.
class DeveloperCard {
  const DeveloperCard({
    required this.slug,
    required this.name,
    required this.verified,
  });

  factory DeveloperCard.fromJson(Map<String, dynamic>? json) => DeveloperCard(
    slug: json?['slug'] as String? ?? '',
    name: json?['name'] as String? ?? '',
    verified: json?['verified'] == true,
  );

  final String slug;
  final String name;
  final bool verified;
}

/// A unit type's price: a range, a "from" price, or on request.
class UnitPrice {
  const UnitPrice({this.onRequest = false, this.from, this.to});

  factory UnitPrice.fromJson(Map<String, dynamic>? json) {
    final currency = json?['currency'] as String?;
    Money? money(Object? amount) =>
        amount is String && currency != null ? Money(amount, currency) : null;
    final from = money(json?['from']);
    return UnitPrice(
      onRequest: json?['on_request'] == true || from == null,
      from: from,
      to: money(json?['to']),
    );
  }

  final bool onRequest;
  final Money? from;
  final Money? to;

  String get label {
    final from = this.from;
    if (onRequest || from == null) return 'Price on request';
    final to = this.to;
    if (to == null || to.amount == from.amount) {
      return 'From ${formatMoney(from)}';
    }
    return '${formatMoney(from)} to ${formatMoney(to)}';
  }
}

class UnitType {
  const UnitType({
    required this.id,
    required this.name,
    required this.price,
    this.bedrooms,
    this.bathrooms,
    this.sizeMin,
    this.sizeMax,
    this.unitsTotal,
    this.unitsAvailable,
    this.availableListings = 0,
  });

  factory UnitType.fromJson(Map<String, dynamic> json) {
    final size = json['size_m2'] as Map<String, dynamic>?;
    return UnitType(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      price: UnitPrice.fromJson(json['price'] as Map<String, dynamic>?),
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      sizeMin: size?['min'] as int?,
      sizeMax: size?['max'] as int?,
      unitsTotal: json['units_total'] as int?,
      unitsAvailable: json['units_available'] as int?,
      availableListings: json['available_listing_count'] as int? ?? 0,
    );
  }

  final String id;
  final String name;
  final UnitPrice price;
  final int? bedrooms;
  final int? bathrooms;
  final int? sizeMin;
  final int? sizeMax;
  final int? unitsTotal;
  final int? unitsAvailable;
  final int availableListings;

  /// "3 bedrooms · 2 bathrooms · 180 to 210 m²".
  String get facts {
    final size = switch ((sizeMin, sizeMax)) {
      (final int a, final int b) when a != b => '$a to $b m²',
      (final int a, _) => '$a m²',
      (null, final int b) => 'up to $b m²',
      _ => null,
    };
    return [
      if (bedrooms != null) bedrooms == 1 ? '1 bedroom' : '$bedrooms bedrooms',
      if (bathrooms != null)
        bathrooms == 1 ? '1 bathroom' : '$bathrooms bathrooms',
      ?size,
    ].join(' · ');
  }

  String? get availability => switch ((unitsAvailable, unitsTotal)) {
    (final int a, final int t) => '$a of $t available',
    (final int a, null) => '$a available',
    _ => null,
  };
}

class Phase {
  const Phase({
    required this.id,
    required this.name,
    required this.unitTypes,
    this.status,
    this.completion,
  });

  factory Phase.fromJson(Map<String, dynamic> json) => Phase(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    status: Coded.fromJson(json['status']),
    completion: _label(json['completion']).ifEmpty,
    unitTypes: [
      for (final u in (json['unit_types'] as List?) ?? const [])
        UnitType.fromJson(u as Map<String, dynamic>),
    ],
  );

  final String id;
  final String name;
  final Coded? status;

  /// "Q3 2027" or "30 June 2027".
  final String? completion;
  final List<UnitType> unitTypes;
}

/// The developer's own statements, never advice, with the API's disclaimer.
class InvestmentHighlights {
  const InvestmentHighlights({required this.disclaimer, required this.items});

  static const fallbackDisclaimer =
      'Stated by the developer. These figures have not been verified by '
      'RightProperty365 and are not financial advice.';

  factory InvestmentHighlights.fromJson(Map<String, dynamic>? json) =>
      InvestmentHighlights(
        disclaimer:
            (json?['disclaimer'] as String?)?.ifEmpty ?? fallbackDisclaimer,
        items: [
          for (final i in (json?['items'] as List?) ?? const [])
            (
              label: (i as Map<String, dynamic>)['label'] as String? ?? '',
              value: i['value'] as String? ?? '',
            ),
        ],
      );

  final String disclaimer;
  final List<({String label, String value})> items;
}

/// A project as the list and the directory show it, and with [detail] the
/// rest of its page.
class Development {
  const Development({
    required this.id,
    required this.market,
    required this.marketName,
    required this.slug,
    required this.name,
    required this.summary,
    required this.place,
    required this.developer,
    this.status,
    this.completion,
    this.cover,
    this.priceFrom,
    this.priceOnRequest = false,
    this.unitTypeCount = 0,
    this.detail,
  });

  factory Development.fromJson(Map<String, dynamic> json, String apiBase) {
    final market = json['market'] as Map<String, dynamic>? ?? const {};
    final location = json['location'] as Map<String, dynamic>? ?? const {};
    final price = json['price_from'] as Map<String, dynamic>?;
    final hasDetail = json.containsKey('phases');
    return Development(
      id: json['id'] as String,
      market: market['code'] as String? ?? '',
      marketName: market['name'] as String? ?? '',
      slug: json['slug'] as String,
      name: json['name'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      place: [
        _label(location['suburb']),
        _label(location['city']),
        _label(location['country']),
      ].where((p) => p.isNotEmpty).join(', '),
      developer: DeveloperCard.fromJson(
        json['developer'] as Map<String, dynamic>?,
      ),
      status: Coded.fromJson(json['status']),
      completion: _label(json['completion']).ifEmpty,
      cover: DevelopmentPhoto.fromJson(json['cover_photo'], apiBase),
      priceFrom: price == null
          ? null
          : Money(price['amount'] as String, price['currency'] as String),
      priceOnRequest: json['price_on_request'] == true,
      unitTypeCount: json['unit_type_count'] as int? ?? 0,
      detail: hasDetail ? DevelopmentDetail._fromJson(json, apiBase) : null,
    );
  }

  final String id;
  final String market;
  final String marketName;
  final String slug;
  final String name;
  final String summary;

  /// "Borrowdale, Harare, Zimbabwe": never a street address.
  final String place;
  final DeveloperCard developer;
  final Coded? status;
  final String? completion;
  final DevelopmentPhoto? cover;
  final Money? priceFrom;
  final bool priceOnRequest;
  final int unitTypeCount;
  final DevelopmentDetail? detail;

  String get priceLabel {
    final from = priceFrom;
    if (from == null) return 'Price on request';
    return 'From ${formatMoney(from)}';
  }
}

class DevelopmentDetail {
  const DevelopmentDetail({
    required this.description,
    required this.amenities,
    required this.highlights,
    required this.photos,
    required this.phases,
    required this.availableUnits,
    this.video,
  });

  factory DevelopmentDetail._fromJson(
    Map<String, dynamic> json,
    String apiBase,
  ) => DevelopmentDetail(
    description: json['description'] as String? ?? '',
    amenities: [
      for (final a in (json['amenities'] as List?) ?? const []) _label(a),
    ]..removeWhere((a) => a.isEmpty),
    highlights: InvestmentHighlights.fromJson(
      json['investment_highlights'] as Map<String, dynamic>?,
    ),
    photos: [
      for (final p in (json['photos'] as List?) ?? const [])
        ?DevelopmentPhoto.fromJson(p, apiBase),
    ],
    video: json['video'] is Map<String, dynamic>
        ? VideoTour.fromJson(json['video'] as Map<String, dynamic>)
        : null,
    phases: [
      for (final p in (json['phases'] as List?) ?? const [])
        Phase.fromJson(p as Map<String, dynamic>),
    ],
    availableUnits: [
      for (final u in (json['available_units'] as List?) ?? const [])
        (
          unitTypeId: (u as Map<String, dynamic>)['unit_type_id'] as String?,
          listing: Listing.fromApi(
            u['listing'] as Map<String, dynamic>,
            apiBase: apiBase,
          ),
        ),
    ],
  );

  final String description;
  final List<String> amenities;
  final InvestmentHighlights highlights;
  final List<DevelopmentPhoto> photos;
  final VideoTour? video;
  final List<Phase> phases;

  /// The project's listings that are public now, with their unit type.
  final List<({String? unitTypeId, Listing listing})> availableUnits;

  UnitType? unitType(String id) {
    for (final phase in phases) {
      for (final u in phase.unitTypes) {
        if (u.id == id) return u;
      }
    }
    return null;
  }
}

class DevelopmentPage {
  const DevelopmentPage(
    this.items, {
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final List<Development> items;
  final int page;
  final int totalPages;
  final int total;
}

class DevelopmentsRepository {
  DevelopmentsRepository(this._api, {required this.apiBase});

  final ApiClient _api;
  final String apiBase;

  static const _notFound =
      'This project is not available. It may have been taken down or not '
      'published yet.';

  Future<DevelopmentPage> list({
    String? query,
    String? market,
    String? status,
    int page = 1,
  }) async {
    final params = {
      if ((query ?? '').trim().isNotEmpty) 'q': query!.trim(),
      'market': ?market,
      'status': ?status,
      'page': '$page',
      'page_size': '12',
    };
    final body = (await _api.get(
      '/v1/developments?${Uri(queryParameters: params).query}',
    )).body;
    return DevelopmentPage(
      [
        for (final item in (body['items'] as List?) ?? const [])
          Development.fromJson(item as Map<String, dynamic>, apiBase),
      ],
      page: body['page'] as int? ?? page,
      totalPages: body['total_pages'] as int? ?? 1,
      total: body['total'] as int? ?? 0,
    );
  }

  /// The project's page. Throws [ApiFailure]; 404 when it is not public.
  Future<Development> get(String market, String slug) async {
    try {
      final body = (await _api.get(
        '/v1/developments/${Uri.encodeComponent(market.toUpperCase())}/'
        '${Uri.encodeComponent(slug)}',
      )).body;
      return Development.fromJson(
        body['development'] as Map<String, dynamic>,
        apiBase,
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'DEVELOPMENT_NOT_FOUND' || failure.status == 404) {
        throw failure.withMessage(_notFound);
      }
      rethrow;
    }
  }

  /// A developer's public projects, from their directory profile (empty
  /// when the API has none, or cannot be reached).
  Future<List<Development>> ofDeveloper(String slug) async {
    try {
      final body = (await _api.get(
        '/v1/directory/developers/${Uri.encodeComponent(slug)}',
      )).body;
      final profile = body['profile'] as Map<String, dynamic>? ?? const {};
      return [
        for (final p in (profile['projects'] as List?) ?? const [])
          Development.fromJson(p as Map<String, dynamic>, apiBase),
      ];
    } on ApiFailure {
      return const [];
    }
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
