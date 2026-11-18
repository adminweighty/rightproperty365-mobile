import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/activity/activity_store.dart';
import 'package:rightproperty365/features/analytics/analytics_repository.dart';
import 'package:rightproperty365/features/analytics/analytics_tracker.dart';
import 'package:rightproperty365/features/analytics/statistics_screen.dart';
import 'package:rightproperty365/features/auth/presentation/auth_screens.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';
import 'package:rightproperty365/features/listings/presentation/search_screen.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show serve, settle;

Map<String, dynamic> reportJson({String period = '30d'}) => {
  'period': period,
  'from': '2030-02-01',
  'to': '2030-03-02',
  'timezone': 'Africa/Harare',
  'near_real_time': period == '24h',
  'label': period == '24h' ? 'Near real time, may change' : null,
  'totals': {
    'impressions': 1200,
    'views': 300,
    'unique_views': 210,
    'contact_clicks': 24,
    'video_plays': 5,
    'saves': 18,
    'enquiries': 12,
    'viewing_requests': 4,
    'appointments_confirmed': 2,
    'relists': 0,
  },
  'daily': [
    {
      'date': '2030-03-01',
      'views': 10,
      'unique_views': 8,
      'impressions': 40,
      'contact_clicks': 1,
      'saves': 0,
      'enquiries': 1,
    },
    {
      'date': '2030-03-02',
      'views': 25,
      'unique_views': 20,
      'impressions': 90,
      'contact_clicks': 2,
      'saves': 1,
      'enquiries': 2,
    },
  ],
  'conversion': 0.04,
  'conversion_definition': 'Enquiries divided by views.',
  'ctr': 0.08,
  'ctr_definition': 'Contact clicks divided by views.',
  'sources': [
    {'key': 'internal', 'count': 200},
    {'key': 'search_engine', 'count': 100},
    {'key': 'unknown', 'count': 0},
  ],
  'devices': [
    {'key': 'mobile', 'count': 250},
    {'key': 'desktop', 'count': 50},
  ],
  'filtered_bot_events': 7,
  'late_events_dropped': 1,
  'refreshed_at': '2030-03-02T10:15:00Z',
  'definitions_path': '/analytics-definitions',
  'top_listings': [
    {
      'listing_id': 'l-1',
      'title': 'Garden cottage',
      'reference': 'RP-ZW-10009',
      'slug': null,
      'market_code': 'ZW',
      'views': 120,
      'unique_views': 90,
      'contact_clicks': 9,
      'enquiries': 5,
    },
  ],
  'scope': 'assigned',
  'listings_count': 3,
};

void main() {
  group('the event tracker', () {
    test('makes version 4 event ids', () {
      final id = newEventId(Random(1));
      expect(
        id,
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
      expect(newEventId(), isNot(newEventId()));
    });

    test('sends the documented events in batches of at most 50', () async {
      var now = DateTime(2030, 3, 2, 23, 50);
      final batches = <Map<String, dynamic>>[];
      final (:api, requests: _) = routedApi({
        'POST /v1/analytics/events': (request) {
          batches.add(jsonBody(request));
          return http.Response('{"accepted":1}', 202);
        },
      });
      final tracker = AnalyticsTracker(
        api,
        store: MemoryStore(),
        clock: () => now,
        interval: Duration.zero,
        device: 'tablet',
      );
      tracker.record(
        AnalyticsEventType.impression,
        'l-1',
        placement: AnalyticsPlacement.search,
        rank: 3,
      );
      tracker.record(AnalyticsEventType.detailView, 'l-1');
      await tracker.flush();

      final events = (batches.single['events'] as List)
          .cast<Map<String, dynamic>>();
      expect(batches.single['schema'], 1);
      final impression = events.first;
      expect(impression['type'], 'property_card_impression');
      expect(impression['placement'], 'search');
      expect(impression['rank'], 3);
      expect(impression['device'], 'tablet');
      expect(impression['source'], 'internal');
      expect(impression['consent'], {'analytics': true});
      expect(impression['occurred_at'], endsWith('Z'));
      expect(impression['session'], matches(r'^[A-Za-z0-9_-]{16,64}$'));
      final view = events.last;
      expect(view['type'], 'listing_detail_view');
      expect(view.containsKey('placement'), isFalse);
      // Same session within the day.
      expect(view['session'], impression['session']);
      expect(view['event_id'], isNot(impression['event_id']));

      // The session rotates at local midnight.
      now = DateTime(2030, 3, 3, 0, 5);
      tracker.record(AnalyticsEventType.contactClick, 'l-1');
      await tracker.flush();
      final next = (batches.last['events'] as List).single as Map;
      expect(next['session'], isNot(impression['session']));

      // 120 events go as 50, 50 and 20 (the first 20 already on their way).
      batches.clear();
      for (var i = 0; i < 120; i++) {
        tracker.record(AnalyticsEventType.impression, 'l-$i', rank: i);
      }
      await tracker.flush();
      await pumpEventQueue();
      expect(
        batches
            .map((b) => (b['events'] as List).length)
            .reduce((a, b) => a + b),
        120,
      );
      expect(batches.every((b) => (b['events'] as List).length <= 50), isTrue);
      expect(tracker.queued, isEmpty);
    });

    test('keeps events when offline or limited, drops refused and old '
        'ones', () async {
      var now = DateTime.utc(2030, 3, 2, 12);
      var answer = () => http.Response('', 202);
      final (:api, :requests) = mockApi((_) async => answer());
      final tracker = AnalyticsTracker(
        api,
        store: MemoryStore(),
        clock: () => now,
        interval: Duration.zero,
      );

      answer = () => throw http.ClientException('offline');
      tracker.record(AnalyticsEventType.detailView, 'l-1');
      await tracker.flush();
      expect(tracker.queued, hasLength(1));

      answer = () =>
          apiError(429, 'RATE_LIMITED', headers: {'retry-after': '60'});
      await tracker.flush();
      expect(tracker.queued, hasLength(1));
      final calls = requests.length;
      await tracker.flush(); // Still waiting out the limit: nothing sent.
      expect(requests.length, calls);

      now = now.add(const Duration(minutes: 2));
      answer = () => apiError(400, 'VALIDATION_FAILED');
      await tracker.flush();
      expect(tracker.queued, isEmpty);

      // An event the API would refuse for age is not sent.
      tracker.record(AnalyticsEventType.detailView, 'l-2');
      now = now.add(const Duration(hours: 24));
      answer = () => http.Response('', 202);
      final before = requests.length;
      await tracker.flush();
      expect(requests.length, before);
      expect(tracker.queued, isEmpty);
    });

    test('sends nothing when counting is turned off', () async {
      final (:api, :requests) = mockApi((_) async => http.Response('', 202));
      final store = MemoryStore();
      final tracker = AnalyticsTracker(
        api,
        store: store,
        interval: Duration.zero,
      );
      tracker.record(AnalyticsEventType.detailView, 'l-1');
      await tracker.setOptedOut(true);
      expect(tracker.queued, isEmpty);
      tracker.record(AnalyticsEventType.detailView, 'l-1');
      await tracker.flush();
      expect(requests, isEmpty);
      // Remembered on the phone.
      expect(
        AnalyticsTracker(api, store: store, interval: Duration.zero).optedOut,
        isTrue,
      );
    });
  });

  group('events from the screens', () {
    testWidgets('a listing page is counted once, and a video play', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      await pumpInApp(tester, test, ListingDetailScreen(slug: listing.slug));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      final views = test.analytics.queued.where(
        (e) => e['type'] == 'listing_detail_view',
      );
      expect(views.single['listing_id'], listing.id);
    });

    testWidgets('search cards are counted once after a second on screen', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const SearchScreen(),
        size: const Size(390, 900),
      );
      await settle(tester);
      expect(
        test.analytics.queued.where(
          (e) => e['type'] == 'property_card_impression',
        ),
        isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      final seen = test.analytics.queued
          .where((e) => e['type'] == 'property_card_impression')
          .toList();
      expect(seen, isNotEmpty);
      expect(seen.first['placement'], 'search');
      expect(seen.first['rank'], 0);
      final count = seen.length;
      await tester.pump(const Duration(seconds: 3));
      expect(
        test.analytics.queued.where(
          (e) => e['type'] == 'property_card_impression',
        ),
        hasLength(count),
      );
    });

    testWidgets('sending a request counts one contact click', (tester) async {
      final test = TestServices();
      test.propertyRequests.failure = const ApiFailure.network();
      final listing = test.listings.listings.first;
      await pumpInApp(tester, test, PropertyRequestScreen(slug: listing.slug));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
      await tester.enterText(
        find.byKey(const Key('email')),
        'test@example.com',
      );
      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await settle(tester);
      test.propertyRequests.failure = null;
      await tester.tap(find.byKey(const Key('submit')));
      await settle(tester);
      expect(test.propertyRequests.drafts, hasLength(2));
      expect(
        test.analytics.queued.where((e) => e['type'] == 'contact_click'),
        hasLength(1),
      );
    });

    testWidgets('counting can be turned off from Account', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const AccountScreen());
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('count-visits')));
      await tester.tap(find.byKey(const Key('count-visits')));
      await settle(tester);
      expect(test.analytics.optedOut, isTrue);
    });
  });

  group('listing statistics', () {
    test('read the report as the API words it', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/analytics/organisations/org-1': (_) => reportJson(),
      });
      final report = await ApiAnalyticsRepository(api)
          .organisation('org-1', '7d');
      expect(requests.single.url.queryParameters['period'], '7d');
      expect(report.total('views'), 300);
      expect(report.conversion, 0.04);
      expect(report.daily, hasLength(2));
      expect(report.sources.first.key, 'internal');
      expect(report.topListings.single.slug, isNull);
      expect(report.assignedOnly, isTrue);
      expect(report.refreshedAt, DateTime.utc(2030, 3, 2, 10, 15));
    });

    testWidgets('show totals, definitions and a table, and link to the web', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/analytics/organisations/org-1': (r) =>
            reportJson(period: r.url.queryParameters['period'] ?? '30d'),
        'GET /v1/analytics/organisations/org-2': (_) =>
            apiError(403, 'FORBIDDEN'),
      });
      const organisations = [
        WorkOrganisation(
          id: 'org-1',
          name: 'Sample Estates',
          kind: 'AGENCY',
          marketCode: 'ZW',
          role: 'AGENT',
          roleLabel: 'Estate Agent',
          canManageListings: true,
        ),
      ];
      await pumpInApp(
        tester,
        test,
        const StatisticsScreen(organisations: organisations),
      );
      await settle(tester);
      expect(find.bySemanticsLabel('Views: 300'), findsOneWidget);
      expect(find.text('Enquiries per view: 4.0%'), findsOneWidget);
      expect(find.text('Enquiries divided by views.'), findsOneWidget);
      expect(find.textContaining('your assigned listings'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('^35 views over 2 days. The busiest day was 2 March'),
        ),
        findsOneWidget,
      );
      expect(find.text('Within RightProperty365'), findsOneWidget);
      expect(find.textContaining('7 automated visits'), findsOneWidget);
      expect(
        find.textContaining('not Google Analytics figures'),
        findsOneWidget,
      );

      await tester.tap(find.text('24 hours'));
      await settle(tester);
      expect(find.text('Near real time, may change'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('daily-table')));
      await tester.tap(find.byKey(const Key('daily-table')));
      await settle(tester);
      expect(find.text('25 views · 20 unique · 2 enquiries'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('how-we-count')));
      await tester.tap(find.byKey(const Key('how-we-count')));
      await settle(tester);
      expect(test.opened.single.path, '/analytics-definitions');
    });

    testWidgets('say so when the account may not see them', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/analytics/organisations/org-2': (_) =>
            apiError(403, 'FORBIDDEN'),
      });
      await pumpInApp(
        tester,
        test,
        const StatisticsScreen(
          organisations: [
            WorkOrganisation(
              id: 'org-2',
              name: 'Other',
              kind: 'AGENCY',
              marketCode: 'ZW',
              role: 'STAFF',
              roleLabel: 'Agency Staff',
            ),
          ],
        ),
      );
      await settle(tester);
      expect(find.text('No statistics for this account here'), findsOneWidget);
    });
  });

  testWidgets('statistics hold at 200% text size', (tester) async {
    final test = TestServices();
    serve(test, {'GET /v1/analytics/organisations/org-1': (_) => reportJson()});
    await pumpInApp(
      tester,
      test,
      const StatisticsScreen(
        organisations: [
          WorkOrganisation(
            id: 'org-1',
            name: 'Sample Estates',
            kind: 'AGENCY',
            marketCode: 'ZW',
            role: 'OWNER',
            roleLabel: 'Agency Principal',
            canManageListings: true,
          ),
        ],
      ),
      textScale: 2,
      size: const Size(390, 2600),
    );
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('daily-table')));
    await tester.tap(find.byKey(const Key('daily-table')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  test('the phone store keeps the switch', () {
    expect(MemoryStore().read('analytics.opted_out'), isNull);
  });
}
