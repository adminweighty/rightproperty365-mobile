import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/location.dart';
import 'package:rightproperty365/features/listings/data/api_listing_repository.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';
import 'package:rightproperty365/features/listings/presentation/search_screen.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show serve, settle, stampPng;

/// Tiles without a network: every tile is the same tiny image.
class BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(stampPng);
}

final testTiles = MapTiles(
  urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
  attribution: '© Test tiles',
  tileProvider: BlankTiles(),
);

Map<String, dynamic> apiListing(
  String n, {
  String? precision = 'EXACT',
  String category = 'residential',
  String photo = '/assets/images/listing-house-highlands.jpg',
}) => {
  'id': '0195c0de-0000-7000-8000-0000000000$n',
  'slug': 'listing-$n',
  'reference': 'RP-ZW-100$n',
  'title': 'Listing $n',
  'deal': {'code': 'rent', 'label': 'To rent'},
  'category': {'code': category, 'label': category},
  'property_type': {'code': 'house', 'label': 'House'},
  'price': {'amount': '850.00', 'currency': 'USD'},
  'price_period': 'month',
  'suburb': {'code': 'avondale', 'label': 'Avondale'},
  'city': {'code': 'harare', 'label': 'Harare'},
  'country': {'code': 'ZW', 'name': 'Zimbabwe'},
  'market_code': 'ZW',
  'bedrooms': 3,
  'summary': 'Sample',
  'description': 'Sample',
  'features': [
    {'code': 'garden', 'label': 'Garden'},
  ],
  'featured': false,
  'photos': [
    {
      'url': photo,
      'alt': 'A house',
      'width': 1200,
      'height': 800,
      'variants': photo.startsWith('/v1/')
          ? [
              {'width': 2048, 'height': 1365, 'url': '$photo?size=large'},
              {'width': 1280, 'height': 853, 'url': '$photo?size=medium'},
            ]
          : [],
    },
  ],
  'advertiser': {
    'type': 'agency',
    'name': 'Sample Estates',
    'verified': true,
    'display': {'name': 'Sample Estates'},
    'agent_display': {'name': 'Tendai Ncube'},
  },
  'location': precision == null
      ? null
      : {
          'latitude': precision == 'APPROXIMATE' ? -17.8 : -17.81234,
          'longitude': precision == 'APPROXIMATE' ? 31.05 : 31.04567,
          'precision': precision,
        },
  'has_video': false,
  'published_at': '2026-10-24T18:00:00Z',
};

Map<String, dynamic> results(List<Map<String, dynamic>> items, {int? total}) =>
    {
      'items': items,
      'page': 1,
      'page_size': 100,
      'total': total ?? items.length,
      'total_pages': 1,
      'mappable_total': items.length,
      'facets': {},
    };

void main() {
  group('listings from the API', () {
    test('map to the app\'s listing, photos and positions included', () {
      final bundled = Listing.fromApi(apiListing('01'), apiBase: 'http://api');
      expect(bundled.image.asset, 'assets/images/listing-house-highlands.jpg');
      expect(bundled.deal, DealType.rent);
      expect(bundled.pricePerMonth, isTrue);
      expect(bundled.listedBy, 'Tendai Ncube');
      expect(bundled.location, 'Avondale, Harare');
      expect(bundled.position!.approximate, isFalse);
      expect(bundled.features, ['Garden']);

      final uploaded = Listing.fromApi(
        apiListing(
          '02',
          precision: 'APPROXIMATE',
          category: 'short-stay',
          photo: '/v1/listing-photos/p1/large',
        ),
        apiBase: 'http://api',
      );
      expect(uploaded.image.asset, isEmpty);
      expect(
        uploaded.image.url,
        'http://api/v1/listing-photos/p1/large?size=medium',
      );
      expect(uploaded.category, ListingCategory.shortStay);
      expect(uploaded.position!.approximate, isTrue);
      expect(
        Listing.fromApi(
          apiListing('03', precision: null),
          apiBase: '',
        ).position,
        isNull,
      );
    });

    test('searches by box or for anything mappable', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/listings': (_) => results([apiListing('01')], total: 4),
        'GET /v1/listings/listing-09': (_) => {'listing': apiListing('09')},
        'GET /v1/listings/gone': (_) => apiError(404, 'LISTING_NOT_FOUND'),
      });
      final search = ApiListingSearch(api, apiBase: 'http://api');
      const filters = ListingFilters(
        deal: DealType.rent,
        category: ListingCategory.shortStay,
        query: ' pool ',
      );

      final page = await search.mappable(filters);
      expect(requests.last.url.queryParameters, {
        'q': 'pool',
        'deal': 'rent',
        'category': 'short-stay',
        'has_location': 'true',
        'page_size': '48',
      });
      expect(page.listings.single.slug, 'listing-01');

      await search.mappable(
        filters,
        bounds: const MapBounds(
          west: 30.9,
          south: -17.9,
          east: 31.2,
          north: -17.7,
        ),
      );
      expect(
        requests.last.url.queryParameters['bbox'],
        '30.900000,-17.900000,31.200000,-17.700000',
      );
      expect(
        requests.last.url.queryParameters.containsKey('has_location'),
        isFalse,
      );
      expect(
        const MapBounds(west: 1, south: 0, east: 1, north: 2).valid,
        isFalse,
      );

      final counts = await search.counts(filters);
      expect(counts, (total: 4, mappable: 1));

      // A listing the bundled sample does not have comes from the API.
      final listings = SampleThenApiListingRepository(sampleListings(), search);
      expect((await listings.bySlug('listing-09'))!.title, 'Listing 09');
      expect(await listings.bySlug('gone'), isNull);
      final bundled = sampleListings().listings.first;
      final calls = requests.length;
      expect((await listings.bySlug(bundled.slug))!.id, bundled.id);
      expect(requests.length, calls);
    });
  });

  group('the map', () {
    testWidgets('is not offered without a tile source', (tester) async {
      await pumpInApp(tester, TestServices(), const SearchScreen());
      await settle(tester);
      expect(find.byKey(const Key('search-view')), findsNothing);
    });

    testWidgets('shows pins and areas, lists them too, and asks before '
        'locating', (tester) async {
      final test = TestServices(mapTiles: testTiles);
      serve(test, {
        'GET /v1/listings': (request) =>
            request.url.queryParameters['page_size'] == '1'
            ? {...results([], total: 3), 'mappable_total': 2}
            : results([
                apiListing('01'),
                apiListing('02', precision: 'APPROXIMATE'),
              ]),
      });
      await pumpInApp(
        tester,
        test,
        const SearchScreen(),
        size: const Size(390, 1400),
      );
      await settle(tester);
      await tester.tap(find.text('Map'));
      await settle(tester);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('© Test tiles'), findsOneWidget);
      expect(
        find.textContaining(
          '2 properties on the map. 1 result has no location',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Listing 01, USD 850 per month')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Approximate area of Listing 02')),
        findsOneWidget,
      );
      // The same results are listed below the map.
      expect(find.text('Listing 02'), findsWidgets);

      await tester.tap(find.byKey(const Key('near-me')));
      await settle(tester);
      expect(find.text('Show properties near you?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('near-me-continue')));
      await settle(tester);
      expect(find.text('Location is not allowed.'), findsOneWidget);

      test.located = const Located.at(-17.82, 31.05);
      await tester.tap(find.byKey(const Key('near-me')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('near-me-continue')));
      await settle(tester);
      expect(
        test.workRequests.where(
          (r) => r.url.queryParameters.containsKey('bbox'),
        ),
        isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a listing page shows an approximate area with a note', (
      tester,
    ) async {
      final test = TestServices(mapTiles: testTiles);
      final listing = test.listings.listings.first;
      serve(test, {
        'GET /v1/listings/${listing.slug}': (_) => {
          'listing': {
            ...apiListing('01', precision: 'APPROXIMATE'),
            'slug': listing.slug,
          },
        },
      });
      await pumpInApp(tester, test, ListingDetailScreen(slug: listing.slug));
      await settle(tester);
      expect(find.text('Location'), findsOneWidget);
      expect(find.textContaining('Approximate location'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Map of .*Tap to move and zoom it')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('listing-map-activate')));
      await settle(tester);
      expect(find.byKey(const Key('listing-map-activate')), findsNothing);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices(mapTiles: testTiles);
      serve(test, {
        'GET /v1/listings': (_) => results([
          apiListing('01'),
          apiListing('02', precision: 'APPROXIMATE'),
        ]),
      });
      await pumpInApp(
        tester,
        test,
        const SearchScreen(),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      await tester.tap(find.text('Map'));
      await settle(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
