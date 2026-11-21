import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/listings/data/listing_reports.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';

import 'map_search_test.dart' show apiListing;
import 'searchable_select_test.dart' show openField;
import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

Future<void> openReport(WidgetTester tester, TestServices test) async {
  await pumpInApp(tester, test, const ListingDetailScreen(slug: 'listing-01'));
  await settle(tester);
  await tester.scrollUntilVisible(
    find.byKey(const Key('report-listing')),
    400,
    scrollable: find
        .ancestor(
          of: find.byKey(const Key('report-listing')),
          matching: find.byType(Scrollable),
        )
        .last,
  );
  await tester.tap(find.byKey(const Key('report-listing')));
  await settle(tester);
}

Future<void> choose(WidgetTester tester, String label) async {
  await openField(tester, const Key('report-reason'));
  await tester.tap(find.text(label).last);
  await settle(tester);
}

void main() {
  test('seven reasons, as the API names them', () {
    expect(ReportReason.values.map((r) => r.wire), [
      'FRAUD',
      'MISLEADING',
      'ALREADY_SOLD_OR_LET',
      'WRONG_PRICE',
      'DUPLICATE',
      'OFFENSIVE',
      'OTHER',
    ]);
    expect(ReportReason.values.where((r) => r.needsNote), [ReportReason.other]);
  });

  testWidgets('a reason is sent; the note is optional', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {'listing': apiListing('01')},
      'POST /v1/listings/listing-01/reports': (_) =>
          http.Response('{"received":true}', 202),
    });
    await openReport(tester, test);
    // Nothing chosen yet.
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester);
    expect(find.text('Choose what is wrong'), findsOneWidget);
    expect(test.workRequests.where((r) => r.method == 'POST'), isEmpty);

    await choose(tester, 'Fraud or a scam');
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester);
    final post = test.workRequests.lastWhere((r) => r.method == 'POST');
    expect(bodyOf(post), {'reason': 'FRAUD'});
    expect(
      find.text('Thank you. Our moderators will look at this listing.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('"Something else" needs a note', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {'listing': apiListing('01')},
      'POST /v1/listings/listing-01/reports': (_) =>
          http.Response('{"received":true}', 202),
    });
    await openReport(tester, test);
    await choose(tester, 'Something else');
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester);
    expect(find.text('Say what is wrong'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('report-note')),
      '  The photos are of another house.  ',
    );
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester);
    expect(bodyOf(test.workRequests.last), {
      'reason': 'OTHER',
      'note': 'The photos are of another house.',
    });
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a refusal keeps the dialog open with the reason', (
    tester,
  ) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {'listing': apiListing('01')},
      'POST /v1/listings/listing-01/reports': (_) =>
          failure(429, 'RATE_LIMITED'),
    });
    await openReport(tester, test);
    await choose(tester, 'Wrong price');
    await tester.tap(find.byKey(const Key('report-send')));
    await settle(tester);
    expect(find.byKey(const Key('report-failure')), findsOneWidget);
    expect(find.text('API says RATE_LIMITED'), findsOneWidget);
  });

  test('a listing no longer public says so', () async {
    final test = TestServices();
    serve(test, {
      'POST /v1/listings/gone/reports': (_) => failure(404, 'NOT_FOUND'),
    });
    await expectLater(
      test.services.listingReports.report('gone', ReportReason.duplicate),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          contains('no longer public'),
        ),
      ),
    );
  });

  testWidgets('holds at 200% text', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/listings/listing-01': (_) => {'listing': apiListing('01')},
    });
    await pumpInApp(
      tester,
      test,
      const ListingDetailScreen(slug: 'listing-01'),
      textScale: 2,
      // Tall enough to show the whole page at this size.
      size: const Size(390, 6000),
    );
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-listing')),
      400,
      scrollable: find
          .ancestor(
            of: find.byKey(const Key('report-listing')),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(find.byKey(const Key('report-listing')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('report-send'))).height,
      greaterThanOrEqualTo(48),
    );
  });
}
