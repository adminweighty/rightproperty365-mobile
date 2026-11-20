import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/manage/my_listings.dart';
import 'package:rightproperty365/features/listings/manage/my_listings_screens.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';

import 'listing_expiry_test.dart' show expiryJson, managedJson, rowJson;
import 'map_search_test.dart' show apiListing;
import 'support.dart';
import 'work_test.dart' show failure, serve, settle;

const live = ['pause', 'mark_sold', 'close', 'archive'];

void main() {
  group('the model', () {
    test('offers the allowed actions in order, ignoring the others', () {
      final m = ManagedListing.fromJson(
        managedJson(
          'l-1',
          actions: const ['close', 'archive', 'pause'],
        )['listing'],
      );
      expect(m.lifecycleActions, [ListingAction.pause, ListingAction.close]);
      expect(ListingAction.markSold.path, 'mark-sold');
      expect(ListingAction.markLet.wire, 'mark_let');
    });

    test('a paused listing keeps its expiry; final states show none', () {
      final soon = ListingExpiry.fromJson(expiryJson('EXPIRING_SOON', 6));
      expect(expiryWarning('PAUSED', soon), 'Expires in 6 days');
      expect(expiryLine('PAUSED', soon), 'Expires 4 Dec 2026');
      final gone = ListingExpiry.fromJson(expiryJson('EXPIRED', 0));
      for (final s in ['SOLD', 'LET', 'CLOSED']) {
        expect(expiryLine(s, gone), isNull);
        expect(expiryWarning(s, gone), isNull);
      }
    });

    test('the public listing reads closed_state', () {
      Listing read(Object? state) => Listing.fromApi({
        ...apiListing('01'),
        'closed_state': state,
      }, apiBase: 'http://api');
      expect(read('SOLD').closedState, 'SOLD');
      expect(read('LET').closedState, 'LET');
      expect(read(null).closedState, isNull);
      // Only SOLD and LET are shown.
      expect(read('CLOSED').closedState, isNull);
    });
  });

  group('managing', () {
    testWidgets('pause, after confirming, then resume', (tester) async {
      final test = TestServices();
      var status = 'PUBLISHED';
      serve(test, {
        'GET /v1/me/listings/l-1': (_) => managedJson(
          'l-1',
          status: status,
          actions: status == 'PAUSED' ? const ['resume', 'close'] : live,
          expiry: expiryJson('ACTIVE', 40),
        ),
        'POST /v1/me/listings/l-1/pause': (_) {
          status = 'PAUSED';
          return managedJson(
            'l-1',
            status: status,
            public: false,
            actions: const ['resume', 'close'],
            expiry: expiryJson('ACTIVE', 40),
          );
        },
        'POST /v1/me/listings/l-1/resume': (_) {
          status = 'PUBLISHED';
          return managedJson(
            'l-1',
            actions: live,
            expiry: expiryJson('ACTIVE', 40),
          );
        },
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      expect(find.byKey(const Key('my-listing-action-pause')), findsOneWidget);
      expect(
        find.byKey(const Key('my-listing-action-mark_sold')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('my-listing-action-mark_let')), findsNothing);
      expect(find.byKey(const Key('my-listing-action-resume')), findsNothing);

      // Cancelling sends nothing.
      await tester.tap(find.byKey(const Key('my-listing-action-pause')));
      await settle(tester);
      expect(find.textContaining('the 90 days keep running'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(test.workRequests.where((r) => r.method == 'POST'), isEmpty);

      await tester.tap(find.byKey(const Key('my-listing-action-pause')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-confirm')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/v1/me/listings/l-1/pause');
      expect(find.text('Listing paused.'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-state')), findsOneWidget);
      // The period keeps running while paused.
      expect(find.text('Expires 4 Dec 2026'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-public')), findsNothing);

      await tester.tap(find.byKey(const Key('my-listing-action-resume')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-confirm')));
      await settle(tester);
      expect(find.text('Listing resumed.'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a resume after the period ended says to relist', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) => managedJson(
          'l-1',
          status: 'PAUSED',
          actions: const ['resume'],
          expiry: expiryJson('EXPIRING_SOON', 1),
        ),
        'POST /v1/me/listings/l-1/resume': (_) => managedJson(
          'l-1',
          status: 'EXPIRED',
          public: false,
          actions: const ['relist'],
          expiry: expiryJson('EXPIRED', 0),
        ),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-action-resume')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-confirm')));
      await settle(tester);
      expect(find.textContaining('ended while it was paused'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a sold listing can be relisted', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) => managedJson(
          'l-1',
          status: 'SOLD',
          public: false,
          actions: const ['relist'],
          expiry: expiryJson('EXPIRED', 0),
        ),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.textContaining('says Sold for 30 days'), findsOneWidget);
      expect(find.byKey(const Key('my-listing-relist')), findsOneWidget);
      // Not the expired callout: the listing did not run out.
      expect(find.byKey(const Key('my-listing-expired')), findsNothing);
    });

    testWidgets('a refused move shows why', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) =>
            managedJson('l-1', actions: live, expiry: expiryJson('ACTIVE', 40)),
        'POST /v1/me/listings/l-1/close': (_) =>
            failure(409, 'LISTING_STATE_CONFLICT'),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-action-close')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-confirm')));
      await settle(tester);
      expect(
        find.textContaining('changed since you opened it'),
        findsOneWidget,
      );
    });

    testWidgets('the list filters by the new statuses', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings': (r) => {
          'items': [
            if (r.url.queryParameters['status'] == 'PAUSED')
              rowJson(
                'l-1',
                'Garden cottage',
                status: 'PAUSED',
                expiry: expiryJson('ACTIVE', 40),
              ),
          ],
          'total': 1,
        },
      });
      await pumpInApp(tester, test, const MyListingsScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listings-filter-paused')));
      await settle(tester);
      final get = test.workRequests.last;
      expect(get.url.queryParameters['status'], 'PAUSED');
      expect(get.url.queryParameters.containsKey('expiry'), isFalse);
      expect(find.text('Paused'), findsWidgets);
      expect(find.text('Expires 4 Dec 2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('my-listings-filter-sold')));
      await settle(tester);
      expect(find.text('No sold listings.'), findsOneWidget);
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) => managedJson(
          'l-1',
          status: 'PAUSED',
          actions: const ['resume', 'mark_let', 'close'],
          expiry: expiryJson('EXPIRING_SOON', 6),
        ),
      });
      await pumpInApp(
        tester,
        test,
        const MyListingScreen(id: 'l-1'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.byKey(const Key('my-listing-action-mark_let')))
            .height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('the public page', () {
    testWidgets('a sold listing says so and offers no contact', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/listings/listing-01': (_) => {
          'listing': {...apiListing('01'), 'closed_state': 'LET'},
        },
      });
      await pumpInApp(
        tester,
        test,
        const ListingDetailScreen(slug: 'listing-01'),
      );
      await settle(tester);
      expect(find.byKey(const Key('listing-closed-banner')), findsOneWidget);
      expect(
        find.textContaining('no longer available to rent'),
        findsOneWidget,
      );
      expect(find.textContaining('Contact the'), findsNothing);
    });

    testWidgets('a live listing still offers contact', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/listings/listing-01': (_) => {'listing': apiListing('01')},
      });
      await pumpInApp(
        tester,
        test,
        const ListingDetailScreen(slug: 'listing-01'),
      );
      await settle(tester);
      expect(find.byKey(const Key('listing-closed-banner')), findsNothing);
      expect(find.textContaining('Contact the'), findsOneWidget);
    });
  });
}
