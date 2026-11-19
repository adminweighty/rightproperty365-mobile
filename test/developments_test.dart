import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/developments/development.dart';
import 'package:rightproperty365/features/developments/development_screens.dart';
import 'package:rightproperty365/features/directory/data/business_enquiry_repository.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/directory/presentation/profile_screen.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';
import 'package:rightproperty365/features/listings/presentation/widgets/listing_card.dart';
import 'package:rightproperty365/features/notifications/link_opener.dart';

import 'api_routes.dart';
import 'screens_test.dart' show contactDetail, fillGuestAndSubmit;
import 'support.dart';
import 'work_test.dart' show serve, settle, stampPng;

const base = 'http://api.test';

Map<String, dynamic> listItem({String slug = 'borrowdale-heights'}) => {
  'id': 'dev-1',
  'market': {'code': 'ZW', 'name': 'Zimbabwe'},
  'slug': slug,
  'name': 'Borrowdale Heights',
  'summary': 'Cluster homes and apartments in a gated estate.',
  'status': {'code': 'SELLING', 'label': 'Selling'},
  'completion': {'kind': 'QUARTER', 'value': '2027-Q3', 'label': 'Q3 2027'},
  'location': {
    'country': {'code': 'ZW', 'name': 'Zimbabwe'},
    'region': {'code': 'harare', 'label': 'Harare'},
    'city': {'code': 'harare', 'label': 'Harare'},
    'suburb': {'code': 'borrowdale', 'label': 'Borrowdale'},
    'coordinates': {
      'latitude': -17.75,
      'longitude': 31.09,
      'precision': 'APPROXIMATE',
    },
  },
  'cover_photo': {
    'url': '/v1/development-photos/p-1/large?v=1',
    'alt': 'The clubhouse',
    'width': 2048,
    'height': 1365,
    'variants': [
      {
        'width': 480,
        'height': 320,
        'url': '/v1/development-photos/p-1/small?v=1',
      },
      {
        'width': 1024,
        'height': 683,
        'url': '/v1/development-photos/p-1/medium?v=1',
      },
    ],
  },
  'price_from': {'amount': '95000.00', 'currency': 'USD'},
  'price_on_request': false,
  'unit_type_count': 3,
  'developer': {
    'kind': 'developers',
    'slug': 'sample-developments',
    'name': 'Sample Developments',
    'verified': true,
    'logo': null,
  },
  'published_at': '2026-11-01T00:00:00Z',
  'updated_at': '2026-11-01T00:00:00Z',
};

Map<String, dynamic> detail() => {
  ...listItem(),
  'description': 'Forty homes around a clubhouse.',
  'amenities': [
    {'code': 'clubhouse', 'label': 'Clubhouse'},
    {'code': 'borehole-water', 'label': 'Borehole water'},
  ],
  'investment_highlights': {
    'stated_by': 'DEVELOPER',
    'disclaimer':
        'Stated by the developer. These figures have not been verified by '
        'RightProperty365 and are not financial advice.',
    'items': [
      {'label': 'Expected rental yield', 'value': '8–10% a year'},
    ],
  },
  'photos': [
    {
      'url': '/assets/images/listing-house-borrowdale.jpg',
      'alt': 'A home',
      'variants': [],
    },
  ],
  'video': {
    'provider': 'YOUTUBE',
    'id': 'aqz-KE-bpKQ',
    'start_seconds': null,
    'embed_url': 'https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ',
    'watch_url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    'thumbnail_url': 'https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg',
  },
  'phases': [
    {
      'id': 'ph-1',
      'name': 'Phase 1',
      'status': {'code': 'SELLING', 'label': 'Selling'},
      'completion': {'kind': 'QUARTER', 'value': '2027-Q3', 'label': 'Q3 2027'},
      'unit_types': [
        {
          'id': 'ut-1',
          'name': 'Three-bedroom cluster home',
          'bedrooms': 3,
          'bathrooms': 2,
          'size_m2': {'min': 180, 'max': 210},
          'price': {
            'on_request': false,
            'from': '185000.00',
            'to': '240000.00',
            'currency': 'USD',
          },
          'units_total': 24,
          'units_available': 9,
          'available_listing_count': 1,
        },
        {
          'id': 'ut-2',
          'name': 'Two-bedroom apartment',
          'bedrooms': 2,
          'bathrooms': 1,
          'size_m2': {'min': 95, 'max': null},
          'price': {
            'on_request': false,
            'from': '95000.00',
            'to': null,
            'currency': 'USD',
          },
          'units_total': null,
          'units_available': null,
          'available_listing_count': 0,
        },
      ],
    },
    {
      'id': 'ph-2',
      'name': 'Phase 2',
      'status': {'code': 'PLANNED', 'label': 'Planned'},
      'completion': null,
      'unit_types': [
        {
          'id': 'ut-3',
          'name': 'Penthouse',
          'bedrooms': 4,
          'bathrooms': null,
          'size_m2': null,
          'price': {
            'on_request': true,
            'from': null,
            'to': null,
            'currency': null,
          },
          'units_total': 2,
          'units_available': 2,
          'available_listing_count': 0,
        },
      ],
    },
  ],
  'available_units': [
    {
      'unit_type_id': 'ut-1',
      'listing': {
        'id': 'l-1',
        'slug': 'three-bedroom-cluster-home-at-borrowdale-heights',
        'reference': 'RP-ZW-10042',
        'title': 'Three-bedroom cluster home at Borrowdale Heights',
        'price': {'amount': '195000.00', 'currency': 'USD'},
        'deal': {'code': 'sale', 'label': 'For sale'},
        'category': {'code': 'residential', 'label': 'Residential'},
        'property_type': {'code': 'cluster', 'label': 'Cluster home'},
        'city': {'label': 'Harare'},
        'suburb': {'label': 'Borrowdale'},
        'market_code': 'ZW',
        'advertiser': {'name': 'Sample Developments', 'verified': true},
        'photos': [
          {
            'url': '/assets/images/listing-house-glen-lorne.jpg',
            'alt': 'The cluster home',
            'variants': [],
          },
        ],
        'published_at': '2026-11-01T00:00:00Z',
      },
    },
  ],
};

void serveDevelopments(TestServices app) => serve(app, {
  'GET /v1/developments': (_) => {
    'items': [listItem()],
    'page': 1,
    'page_size': 12,
    'total': 1,
    'total_pages': 1,
  },
  'GET /v1/developments/ZW/borrowdale-heights': (_) => {
    'development': detail(),
  },
  'GET /v1/developments/ZW/ruwa-gardens-estate': (_) =>
      apiError(404, 'DEVELOPMENT_NOT_FOUND'),
  'GET /v1/directory/developers/sample-developments': (_) => {
    'profile': {
      'slug': 'sample-developments',
      'projects': [listItem()],
    },
  },
});

/// A phone-sized surface tall enough for a whole project page.
void tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('the models', () {
    final d = Development.fromJson(detail(), base);

    test('prices: a range, a "from", and on request', () {
      final units = d.detail!.phases.expand((p) => p.unitTypes).toList();
      expect(units[0].price.label, 'USD 185,000 to USD 240,000');
      expect(units[1].price.label, 'From USD 95,000');
      expect(units[2].price.label, 'Price on request');
      expect(units[2].price.onRequest, isTrue);
      expect(d.priceLabel, 'From USD 95,000');
      expect(
        Development.fromJson({
          ...listItem(),
          'price_from': null,
          'price_on_request': true,
        }, base).priceLabel,
        'Price on request',
      );
    });

    test('facts, place, completion and photos', () {
      final units = d.detail!.phases.first.unitTypes;
      expect(units[0].facts, '3 bedrooms · 2 bathrooms · 180 to 210 m²');
      expect(units[0].availability, '9 of 24 available');
      expect(units[1].facts, '2 bedrooms · 1 bathroom · 95 m²');
      expect(d.place, 'Borrowdale, Harare, Zimbabwe');
      expect(d.completion, 'Q3 2027');
      expect(d.cover!.url, '$base/v1/development-photos/p-1/medium?v=1');
      expect(
        d.detail!.photos.single.asset,
        'assets/images/listing-house-borrowdale.jpg',
      );
      expect(d.detail!.video!.id, 'aqz-KE-bpKQ');
      expect(d.detail!.highlights.disclaimer, contains('not financial advice'));
      expect(d.detail!.availableUnits.single.listing.slug, endsWith('heights'));
      expect(d.detail!.unitType('ut-3')!.name, 'Penthouse');
    });
  });

  group('the repository', () {
    test(
      'lists, opens by market and slug, and says plainly when not public',
      () async {
        final (:api, :requests) = routedApi({
          'GET /v1/developments': (_) => {
            'items': [listItem()],
            'page': 1,
            'total': 1,
            'total_pages': 1,
          },
          'GET /v1/developments/ZW/borrowdale-heights': (_) => {
            'development': detail(),
          },
          'GET /v1/developments/ZW/ruwa-gardens-estate': (_) =>
              apiError(404, 'DEVELOPMENT_NOT_FOUND'),
        });
        final repo = DevelopmentsRepository(api, apiBase: base);
        final page = await repo.list(query: ' borrowdale ');
        expect(page.items.single.slug, 'borrowdale-heights');
        expect(requests.last.url.queryParameters, {
          'q': 'borrowdale',
          'page': '1',
          'page_size': '12',
        });
        // The website's lower-case market works too.
        expect((await repo.get('zw', 'borrowdale-heights')).detail, isNotNull);
        await expectLater(
          repo.get('zw', 'ruwa-gardens-estate'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('not available'),
            ),
          ),
        );
      },
    );

    test('a developer\'s projects come from the directory profile', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/directory/developers/sample-developments': (_) => {
          'profile': {
            'projects': [listItem()],
          },
        },
      });
      final repo = DevelopmentsRepository(api, apiBase: base);
      expect(
        (await repo.ofDeveloper('sample-developments')).single.name,
        'Borrowdale Heights',
      );
      expect(await repo.ofDeveloper('someone-else'), isEmpty);
    });

    test('the enquiry carries the project, not a recipient', () {
      final body = const BusinessEnquiryDraft(
        development: (
          market: 'ZW',
          slug: 'borrowdale-heights',
          unitTypeId: 'ut-1',
        ),
        message: ' Is a 3-bedroom still available? ',
        contactMethod: ContactMethod.email,
        contact: EnquiryContact(),
        consentAccepted: true,
        privacyVersion: 'v1',
      ).toJson('key-1');
      expect(body['recipient'], isNull);
      expect(body['development'], {
        'market': 'ZW',
        'slug': 'borrowdale-heights',
        'unit_type_id': 'ut-1',
      });
      expect(
        const BusinessEnquiryDraft(
          development: (
            market: 'ZW',
            slug: 'borrowdale-heights',
            unitTypeId: null,
          ),
          message: 'x',
          contactMethod: ContactMethod.email,
          contact: EnquiryContact(),
          consentAccepted: true,
          privacyVersion: 'v1',
        ).toJson('k')['development'],
        {'market': 'ZW', 'slug': 'borrowdale-heights'},
      );
    });
  });

  group('the screens', () {
    testWidgets('list, project page, a unit type enquiry', (tester) async {
      final app = TestServices();
      serveDevelopments(app);
      tallPhone(tester);
      final router = buildRouter();
      await tester.pumpWidget(appWith(app, router));
      await settle(tester);
      router.push(Routes.developments);
      await settle(tester);
      expect(find.text('Borrowdale Heights'), findsOneWidget);
      expect(find.text('From USD 95,000'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('development-ZW-borrowdale-heights')),
      );
      await settle(tester);
      expect(find.byType(DevelopmentScreen), findsOneWidget);
      expect(find.text('Phase 1'), findsOneWidget);
      expect(find.text('Phase 2'), findsOneWidget);
      expect(find.text('USD 185,000 to USD 240,000'), findsOneWidget);
      expect(find.text('Price on request'), findsOneWidget);
      expect(find.text('9 of 24 available'), findsOneWidget);
      // Highlights: the developer's words, with the label and disclaimer.
      expect(find.text('Stated by the developer, not advice'), findsOneWidget);
      expect(find.textContaining('not financial advice'), findsOneWidget);
      expect(find.text('Borehole water'), findsOneWidget);
      // The video tour is there, and nothing opens until it is tapped (the
      // poster cannot load without a network: the fallback link shows).
      expect(find.text('Video tour'), findsOneWidget);
      expect(app.opened, isEmpty);
      // No contact details anywhere on the page.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final value = t.data ?? t.textSpan?.toPlainText() ?? '';
        if (value.contains(r'$') || value.contains('m²')) continue;
        expect(contactDetail.hasMatch(value), isFalse, reason: value);
      }

      // A linked listing opens the listing screen.
      await tester.ensureVisible(find.byType(ListingCard));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListingCard));
      await settle(tester);
      final opened = tester.widget<ListingDetailScreen>(
        find.byType(ListingDetailScreen),
      );
      expect(opened.slug, 'three-bedroom-cluster-home-at-borrowdale-heights');
      router.pop();
      await settle(tester);

      await tester.ensureVisible(find.byKey(const Key('unit-ask-ut-3')));
      await tester.tap(find.byKey(const Key('unit-ask-ut-3')));
      await settle(tester);
      expect(find.byType(DevelopmentEnquiryScreen), findsOneWidget);
      expect(
        find.textContaining('Penthouse at Borrowdale Heights'),
        findsWidgets,
      );
      await fillGuestAndSubmit(tester);
      final draft = app.businessEnquiries.drafts.single;
      expect(draft.recipient, isNull);
      expect(draft.development, (
        market: 'ZW',
        slug: 'borrowdale-heights',
        unitTypeId: 'ut-3',
      ));
    });

    testWidgets('a draft project is not found', (tester) async {
      final app = TestServices();
      serveDevelopments(app);
      await pumpInApp(
        tester,
        app,
        const DevelopmentScreen(market: 'zw', slug: 'ruwa-gardens-estate'),
      );
      await settle(tester);
      expect(
        find.textContaining('This project is not available'),
        findsOneWidget,
      );
    });

    testWidgets('the developer\'s profile lists the projects', (tester) async {
      final app = TestServices();
      serveDevelopments(app);
      await pumpInApp(
        tester,
        app,
        const ProfileScreen(
          kind: DirectoryKind.developers,
          slug: 'sample-developments',
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('developer-projects')), findsOneWidget);
      expect(find.text('Borrowdale Heights'), findsOneWidget);
    });

    testWidgets('the project page holds at 200% text size', (tester) async {
      final app = TestServices();
      serveDevelopments(app);
      await pumpInApp(
        tester,
        app,
        DevelopmentScreen(
          market: 'zw',
          slug: 'borrowdale-heights',
          posterImage: MemoryImage(stampPng),
        ),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      expect(find.text('Borrowdale Heights'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('website links', () {
    test('open the app\'s screens as they are', () {
      for (final link in [
        '/developments',
        '/developments/zw/borrowdale-heights',
      ]) {
        expect(webLinkRedirect(Uri.parse(link)), isNull, reason: link);
      }
      expect(
        Routes.development('ZW', 'borrowdale-heights'),
        '/developments/zw/borrowdale-heights',
      );
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:path="/developments"'));
      expect(manifest, contains('android:pathPrefix="/developments/"'));
    });

    testWidgets('a project link opens the project', (tester) async {
      final app = TestServices();
      serveDevelopments(app);
      tallPhone(tester);
      final router = buildRouter();
      await tester.pumpWidget(appWith(app, router));
      await settle(tester);
      router.go('/developments/zw/borrowdale-heights');
      await settle(tester);
      expect(find.byType(DevelopmentScreen), findsOneWidget);
      expect(find.text('Phase 1'), findsOneWidget);
    });
  });
}
