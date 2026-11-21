import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';
import 'package:rightproperty365/features/listings/presentation/widgets/listing_card.dart';

import 'map_search_test.dart' show apiListing;
import 'support.dart';
import 'work_test.dart' show serve, settle;

Listing read(Map<String, dynamic>? placement, {bool featured = false}) =>
    Listing.fromApi({
      ...apiListing('01'),
      'featured': featured,
      'placement': placement,
    }, apiBase: 'http://api');

const sponsored = {'kind': 'SPONSORED', 'label': 'Sponsored'};

void main() {
  group('the model', () {
    test('the label comes from the API', () {
      final s = read(sponsored);
      expect(s.featured, isTrue);
      expect(s.placementLabel, 'Sponsored');
      expect(
        s.placementDisclosure,
        'Sponsored: the advertiser paid for this placement.',
      );
      expect(s.spokenSummary, startsWith('Sponsored, '));
      // The API's own wording wins.
      expect(
        read({'kind': 'FEATURED', 'label': 'Top spot'}).placementLabel,
        'Top spot',
      );
      expect(
        read({'kind': 'FEATURED', 'label': 'Featured'}).placementDisclosure,
        'Featured: the advertiser paid to show this listing first.',
      );
    });

    test('featured without a placement keeps the badge, no disclosure', () {
      final legacy = read(null, featured: true);
      expect(legacy.placementLabel, 'Featured');
      expect(legacy.placementDisclosure, isNull);
      final plain = read(null);
      expect(plain.placementLabel, isNull);
      expect(plain.spokenSummary, startsWith('To rent, '));
    });

    test('the label survives being placed on the map', () {
      final moved = read(
        sponsored,
      ).withLocation(const ListingLocation(latitude: -17.8, longitude: 31.0));
      expect(moved.placementLabel, 'Sponsored');
      expect(moved.placementKind, 'SPONSORED');
    });
  });

  testWidgets('cards show the label', (tester) async {
    final test = TestServices();
    final listing = read(sponsored);
    await pumpInApp(
      tester,
      test,
      Scaffold(
        body: ListView(
          children: [ListingCard(listing: listing, onTap: () {})],
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(Key('placement-${listing.id}')), findsOneWidget);
    expect(find.text('Sponsored'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Sponsored, To rent')),
      findsOneWidget,
    );
  });

  testWidgets('the listing page adds the disclosure', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {
        'listing': {...apiListing('01'), 'placement': sponsored},
      },
    });
    await pumpInApp(
      tester,
      test,
      const ListingDetailScreen(slug: 'listing-01'),
    );
    await settle(tester);
    expect(find.byKey(const Key('listing-placement')), findsOneWidget);
    expect(
      find.text('Sponsored: the advertiser paid for this placement.'),
      findsOneWidget,
    );
  });

  testWidgets('no placement, no label', (tester) async {
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
    expect(find.byKey(const Key('listing-placement')), findsNothing);
    expect(find.byKey(const Key('listing-placement-disclosure')), findsNothing);
  });

  testWidgets('holds at 200% text', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {
        'listing': {...apiListing('01'), 'placement': sponsored},
      },
    });
    await pumpInApp(
      tester,
      test,
      const ListingDetailScreen(slug: 'listing-01'),
      textScale: 2,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
