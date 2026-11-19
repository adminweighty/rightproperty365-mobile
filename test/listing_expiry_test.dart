import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/features/listings/manage/my_listings.dart';
import 'package:rightproperty365/features/listings/manage/my_listings_screens.dart';
import 'package:rightproperty365/features/notifications/notifications_screens.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';

import 'developments_test.dart' show tallPhone;
import 'notifications_test.dart' show itemJson, pageJson;
import 'support.dart';
import 'work_test.dart' show failure, serve, settle;

Map<String, dynamic>? expiryJson(String state, int days) => {
  'expires_at': '2026-12-04T12:00:00Z',
  'days_left': days,
  'state': state,
  'relist_no': 1,
};

Map<String, dynamic> rowJson(
  String id,
  String title, {
  String status = 'PUBLISHED',
  Map<String, dynamic>? expiry,
}) => {
  'id': id,
  'slug': 'slug-$id',
  'reference': 'RP-ZW-$id',
  'title': title,
  'status': status,
  'city': {'name': 'Harare'},
  'country': {'code': 'ZW'},
  'price': {'amount': '1200.00', 'currency': 'USD'},
  'can_edit': true,
  'expiry': expiry,
};

Map<String, dynamic> managedJson(
  String id, {
  String status = 'PUBLISHED',
  bool public = true,
  List<String> actions = const ['archive'],
  Map<String, dynamic>? expiry,
}) => {
  'listing': {
    'id': id,
    'slug': 'slug-$id',
    'reference': 'RP-ZW-$id',
    'status': status,
    'status_label': listingStatusLabel(status),
    'public': public,
    'content': {'title': 'Garden cottage in Avondale'},
    'actions': actions,
    'can_edit': true,
    'published_at': '2026-09-05T12:00:00Z',
    'expires_at': '2026-12-04T12:00:00Z',
    'expiry': expiry,
  },
};

final rows = [
  rowJson('l-1', 'Garden cottage', expiry: expiryJson('EXPIRING_SOON', 6)),
  rowJson('l-2', 'Flat in Avondale', expiry: expiryJson('EXPIRING_SOON', 1)),
  rowJson(
    'l-3',
    'House in Borrowdale',
    status: 'EXPIRED',
    expiry: expiryJson('EXPIRED', 0),
  ),
  // Archived before its end: not live, so EXPIRED state, but no "Expired on".
  rowJson(
    'l-6',
    'Archived flat',
    status: 'ARCHIVED',
    expiry: expiryJson('EXPIRED', 0),
  ),
  rowJson('l-4', 'Townhouse in Mt Pleasant', expiry: expiryJson('ACTIVE', 40)),
  rowJson('l-5', 'Draft plot', status: 'DRAFT'),
];

void main() {
  group('the model', () {
    test('reads the expiry, and null for a listing never published', () {
      final l = MyListing.fromJson(rows[0]);
      expect(l.expiry!.state, ExpiryState.expiringSoon);
      expect(l.expiry!.daysLeft, 6);
      expect(l.expiry!.relistNo, 1);
      expect(l.city, 'Harare');
      expect(MyListing.fromJson(rows.last).expiry, isNull);
      // A newer API state reads as active rather than failing.
      expect(ExpiryState.from('SOMETHING_NEW'), ExpiryState.active);
    });

    test('a relist in review shows the last cycle as expired', () {
      final m = ManagedListing.fromJson(
        managedJson(
          'l-3',
          status: 'PENDING_REVIEW',
          actions: const [],
          expiry: expiryJson('EXPIRED', 0),
        )['listing'],
      );
      expect(m.relistInReview, isTrue);
      expect(m.canRelist, isFalse);
    });

    test('My listings is offered to those who manage listings', () {
      expect(
        Workspace.fromJson({
          'capabilities': {'manages_listings': true},
        }).managesListings,
        isTrue,
      );
      expect(Workspace.fromJson(const {}).managesListings, isFalse);
    });

    test('wording', () {
      final soon = ListingExpiry.fromJson(expiryJson('EXPIRING_SOON', 6));
      final tomorrow = ListingExpiry.fromJson(expiryJson('EXPIRING_SOON', 1));
      final gone = ListingExpiry.fromJson(expiryJson('EXPIRED', 0));
      final active = ListingExpiry.fromJson(expiryJson('ACTIVE', 40));
      expect(expiryWarning('PUBLISHED', soon), 'Expires in 6 days');
      expect(expiryWarning('PUBLISHED', tomorrow), 'Expires tomorrow');
      expect(expiryWarning('EXPIRED', gone), isNull);
      expect(expiryWarning('PUBLISHED', active), isNull);
      expect(expiryLine('PUBLISHED', active), 'Expires 4 Dec 2026');
      expect(expiryLine('EXPIRED', gone), 'Expired on 4 Dec 2026');
      expect(expiryLine('ARCHIVED', gone), isNull);
      expect(expiryLine('PUBLISHED', null), isNull);
    });
  });

  group('my listings', () {
    testWidgets('rows show the expiry; the filters ask the API', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings': (r) => {
          'items': switch (r.url.queryParameters['expiry']) {
            'EXPIRED' => [rows[2]],
            _ => rows,
          },
          'total': 6,
        },
      });
      await pumpInApp(tester, test, const MyListingsScreen());
      await settle(tester);

      expect(find.text('Expires in 6 days'), findsOneWidget);
      expect(find.text('Expires tomorrow'), findsOneWidget);
      expect(find.text('Expired on 4 Dec 2026'), findsOneWidget);
      expect(find.text('Expires 4 Dec 2026'), findsNWidgets(3));
      // An expired listing reads Expired, not Published.
      expect(
        find.descendant(
          of: find.byKey(const Key('my-listing-l-3')),
          matching: find.text('Expired'),
        ),
        findsOneWidget,
      );
      // A draft and an archived listing have no expiry line.
      expect(find.byKey(const Key('my-listing-expiry-l-5')), findsNothing);
      expect(find.byKey(const Key('my-listing-expiry-l-6')), findsNothing);
      expect(find.text('Archived'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('^Garden cottage. Published. Expires in 6 days'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('my-listings-filter-expired')));
      await settle(tester);
      expect(test.workRequests.last.url.queryParameters['expiry'], 'EXPIRED');
      expect(find.text('House in Borrowdale'), findsOneWidget);
      expect(find.text('Garden cottage'), findsNothing);
    });

    testWidgets('someone who manages no listings is told so', (tester) async {
      final test = TestServices();
      serve(test, {'GET /v1/me/listings': (_) => failure(403, 'FORBIDDEN')});
      await pumpInApp(tester, test, const MyListingsScreen());
      await settle(tester);
      expect(find.byKey(const Key('my-listings-none')), findsOneWidget);
    });

    testWidgets('an expired listing is relisted for review', (tester) async {
      final test = TestServices();
      var relisted = false;
      serve(test, {
        'GET /v1/me/listings/l-3': (_) => managedJson(
          'l-3',
          status: 'EXPIRED',
          public: false,
          actions: const ['relist'],
          expiry: expiryJson('EXPIRED', 0),
        ),
        'POST /v1/me/listings/l-3/relist': (_) {
          relisted = true;
          return managedJson(
            'l-3',
            status: 'PENDING_REVIEW',
            public: false,
            actions: const [],
            expiry: expiryJson('EXPIRED', 0),
          );
        },
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-3'));
      await settle(tester);

      expect(
        find.text(
          'This listing expired on 4 Dec 2026 and is hidden from search. '
          'Relist it to send it for review; once approved it is live for '
          'another 90 days.',
        ),
        findsOneWidget,
      );
      // Hidden from the public: no public page link.
      expect(find.byKey(const Key('my-listing-public')), findsNothing);
      await tester.tap(find.byKey(const Key('my-listing-relist')));
      await settle(tester);
      expect(relisted, isTrue);
      expect(find.byKey(const Key('my-listing-relist-review')), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsNothing);
      expect(find.text('Relist sent for review.'), findsOneWidget);
    });

    testWidgets('relist is offered only when the API allows it', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-3': (_) => managedJson(
          'l-3',
          status: 'EXPIRED',
          public: false,
          actions: const [],
          expiry: expiryJson('EXPIRED', 0),
        ),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-3'));
      await settle(tester);
      expect(find.byKey(const Key('my-listing-expired')), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsNothing);
    });

    testWidgets('a refused relist shows the API message', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-3': (_) => managedJson(
          'l-3',
          status: 'EXPIRED',
          public: false,
          actions: const ['relist'],
          expiry: expiryJson('EXPIRED', 0),
        ),
        'POST /v1/me/listings/l-3/relist': (_) => failure(409, 'QUOTA_REACHED'),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-3'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-relist')));
      await settle(tester);
      expect(find.text('API says QUOTA_REACHED'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsOneWidget);
    });

    testWidgets('an expiring listing says when, and still opens publicly', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) =>
            managedJson('l-1', expiry: expiryJson('EXPIRING_SOON', 6)),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      expect(find.text('Expires in 6 days'), findsOneWidget);
      expect(find.text('Expires 4 Dec 2026'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-public')), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsNothing);
      await tester.tap(find.byKey(const Key('my-listing-website')));
      await settle(tester);
      expect(
        test.opened.single.toString(),
        'https://rightproperty365.com/agent/listings/l-1',
      );
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings': (_) => {'items': rows, 'total': 5},
        'GET /v1/me/listings/l-3': (_) => managedJson(
          'l-3',
          status: 'EXPIRED',
          public: false,
          actions: const ['relist'],
          expiry: expiryJson('EXPIRED', 0),
        ),
      });
      await pumpInApp(tester, test, const MyListingsScreen(), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const MyListingScreen(id: 'l-3'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('my-listing-relist'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  testWidgets('an expiry notice opens the listing in the app', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/me/notifications': (_) => pageJson([
        itemJson(
          id: 'n-7',
          type: 'LISTING_EXPIRY',
          title: 'Your listing expires in 7 days',
          body: 'RP-ZW-l-1',
          link: '/agent/listings/l-1',
          read: true,
        ),
      ]),
      'GET /v1/me/notifications/unread-count': (_) => {'unread_count': 0},
      'GET /v1/me/listings/l-1': (_) =>
          managedJson('l-1', expiry: expiryJson('EXPIRING_SOON', 7)),
    });
    await test.auth.signIn('tendai@example.test', 'pw');
    tallPhone(tester);
    final router = buildRouter();
    await tester.pumpWidget(appWith(test, router));
    await settle(tester);
    router.push(Routes.notifications);
    await settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-n-7')));
    await settle(tester);
    expect(find.byType(MyListingScreen), findsOneWidget);
    expect(find.text('Expires in 7 days'), findsOneWidget);
    expect(test.opened, isEmpty);
  });
}
