import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/directory/data/reviews_repository.dart';
import 'package:rightproperty365/features/directory/presentation/reviews_widgets.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const public = '/v1/directory/service-providers/sample-plumbers/reviews';

Map<String, dynamic> reviewJson({
  String id = 'r-1',
  int rating = 4,
  String status = 'PUBLISHED',
  bool reply = true,
  bool mine = false,
  bool received = false,
}) => {
  'id': id,
  'rating': rating,
  'text': 'Came the same day and fixed the geyser properly.',
  'reviewer': {'kind': 'CUSTOMER', 'name': 'Casey C.'},
  if (!mine && !received) 'basis_kind': 'ENQUIRY',
  if (mine || received)
    'profile': {
      'id': 'prof-1',
      'kind': 'service-providers',
      'slug': 'sample-plumbers',
      'name': 'Sample Plumbers',
    },
  if (mine)
    'basis': {'kind': 'ENQUIRY', 'id': 'e-1', 'reference': 'BE-RVW2CSMR'},
  if (received) 'basis': {'kind': 'ENQUIRY', 'reference': 'BE-RVW2CSMR'},
  if (mine) 'status': status,
  if (mine)
    'status_label': switch (status) {
      'PENDING' => 'Awaiting moderation',
      'REJECTED' => 'Not published',
      _ => 'Published',
    },
  if (mine && status == 'REJECTED')
    'moderation': {'reason': 'Personal details', 'at': '2026-11-10T09:00:00Z'},
  'published_at': status == 'PUBLISHED' ? '2026-11-05T09:00:00Z' : null,
  if (mine) 'created_at': '2026-11-04T09:00:00Z',
  'reply': reply
      ? {
          'text': 'Thank you, Casey.',
          'replied_at': '2026-11-06T09:00:00Z',
          'updated_at': '2026-11-06T09:00:00Z',
        }
      : null,
  if (mine) 'can': {'edit': status == 'PENDING', 'delete': true},
  if (received) ...{
    'reply_removed': false,
    'reply_editable_until': null,
    'can': {'reply': !reply, 'edit_reply': false},
  },
};

Map<String, dynamic> eligibilityJson({
  bool eligible = true,
  bool reviewable = true,
  String? upcoming,
}) => {
  'profile': {
    'id': 'prof-1',
    'kind': 'service-providers',
    'slug': 'sample-plumbers',
    'name': 'Sample Plumbers',
  },
  'reviewable': reviewable,
  'eligible': eligible,
  'bases': [
    if (eligible)
      {
        'kind': 'ENQUIRY',
        'id': 'e-4',
        'reference': 'BE-RVW4TNNT',
        'label': 'Enquiry BE-RVW4TNNT',
        'date': '2026-10-30T09:00:00Z',
      },
  ],
  'upcoming': [
    if (upcoming != null)
      {
        'basis': {
          'kind': 'ENQUIRY',
          'id': 'e-5',
          'reference': 'BE-NEW00001',
          'label': 'Enquiry BE-NEW00001',
          'date': null,
        },
        'reason': upcoming,
        'eligible_from': '2026-12-01T09:00:00Z',
      },
  ],
  'reviewed': [],
};

Map<String, dynamic> publishedJson({List<Map<String, dynamic>>? items}) => {
  'profile': {
    'kind': 'service-providers',
    'slug': 'sample-plumbers',
    'name': 'Sample Plumbers',
  },
  'rating': {'average': '4.5', 'count': 2},
  'items':
      items ??
      [
        reviewJson(),
        {
          ...reviewJson(id: 'r-2', rating: 5, reply: false),
          'reviewer': {'kind': 'ORGANISATION', 'name': 'Sample Estates'},
          'basis_kind': 'MAINTENANCE',
          'text':
              'Cleared a blocked courtyard drain the same afternoon and left '
              'the yard clean.',
          'published_at': '2026-10-28T09:00:00Z',
        },
      ],
  'total': 2,
  'page': 1,
  'page_size': 10,
};

Widget section() => const SingleChildScrollView(
  child: ProfileReviewsSection(
    kind: 'service-providers',
    slug: 'sample-plumbers',
    name: 'Sample Plumbers',
  ),
);

void main() {
  group('the reviews API', () {
    test('published reviews with the rating, never anonymous ids', () async {
      final (:api, requests: _) = routedApi({
        'GET $public': (_) => publishedJson(),
      });
      final p = await ReviewsRepository(api)
          .published('service-providers', 'sample-plumbers');
      expect(p.rating.average, '4.5');
      expect(p.rating.count, 2);
      expect(p.items.first.reviewerName, 'Casey C.');
      expect(p.items.first.reply!.text, 'Thank you, Casey.');
      expect(p.items.last.basisKind, 'MAINTENANCE');
    });

    test('eligibility for the person and for a book', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/me/reviews/eligibility': (_) => eligibilityJson(),
        'GET /v1/agent/organisations/org-1/reviews/eligibility': (_) =>
            eligibilityJson(eligible: false, upcoming: 'NOT_COMPLETED'),
      });
      final repo = ReviewsRepository(api);
      final mine = await repo.eligibility(
        'service-providers',
        'sample-plumbers',
      );
      expect(requests.last.url.queryParameters, {
        'kind': 'service-providers',
        'slug': 'sample-plumbers',
      });
      expect(mine.eligible, isTrue);
      expect(mine.bases.single.book, isNull);
      final book = await repo.eligibility(
        'service-providers',
        'sample-plumbers',
        book: 'org-1',
      );
      expect(book.eligible, isFalse);
      expect(book.upcoming.single.reason, 'NOT_COMPLETED');
      expect(book.upcoming.single.basis.book, 'org-1');
    });

    test('writes on the right route for the basis', () async {
      final (:api, :requests) = routedApi({
        'POST /v1/me/reviews': (_) => jsonResponse(201, {
          'review': reviewJson(mine: true, status: 'PENDING', reply: false),
        }),
        'POST /v1/agent/organisations/org-1/reviews': (_) =>
            apiError(409, 'REVIEW_EXISTS'),
      });
      final repo = ReviewsRepository(api);
      final review = await repo.write(
        profileId: 'prof-1',
        basis: const ReviewBasis(kind: 'ENQUIRY', id: 'e-4', label: 'x'),
        rating: 4,
        text: '  Came the same day and fixed it.  ',
      );
      expect(jsonBody(requests.first), {
        'directory_profile_id': 'prof-1',
        'basis': {'kind': 'ENQUIRY', 'id': 'e-4'},
        'rating': 4,
        'text': 'Came the same day and fixed it.',
      });
      expect(review.statusLabel, 'Awaiting moderation');
      await expectLater(
        repo.write(
          profileId: 'prof-1',
          basis: const ReviewBasis(
            kind: 'MAINTENANCE',
            id: 'm-5',
            label: 'x',
            book: 'org-1',
          ),
          rating: 5,
          text: 'A second review of the same job.',
        ),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('already been written'),
          ),
        ),
      );
    });

    test(
      'one reply, one open report, and marking an enquiry replied',
      () async {
        final (:api, :requests) = routedApi({
          'POST /v1/agent/organisations/org-9/reviews/r-1/reply': (_) =>
              apiError(409, 'REVIEW_REPLY_EXISTS'),
          'POST /v1/reviews/r-1/report': (_) =>
              apiError(409, 'REVIEW_ALREADY_REPORTED'),
          'POST /v1/inbox/business-enquiries/e-1/replied': (_) => {'item': {}},
        });
        final repo = ReviewsRepository(api);
        await expectLater(
          repo.reply('org-9', 'r-1', 'Thanks'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('already has your reply'),
            ),
          ),
        );
        await expectLater(
          repo.report('r-1', 'Spam'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('already reported'),
            ),
          ),
        );
        await repo.markReplied('e-1');
        expect(
          requests.last.url.path,
          '/v1/inbox/business-enquiries/e-1/replied',
        );
      },
    );
  });

  group('reviews on a profile', () {
    testWidgets('rating, reviews and replies; guests cannot write', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET $public': (_) => publishedJson()});
      await pumpInApp(tester, test, Scaffold(body: section()));
      await settle(tester);
      expect(find.text('4.5 out of 5 from 2 reviews'), findsOneWidget);
      expect(find.text('Casey C.'), findsOneWidget);
      expect(find.text('Sample Estates'), findsOneWidget);
      expect(find.text('Thank you, Casey.'), findsOneWidget);
      expect(find.bySemanticsLabel('4 out of 5 stars'), findsOneWidget);
      expect(find.byKey(const Key('write-review')), findsNothing);
      expect(find.text('Report'), findsNothing);
    });

    testWidgets('a profile the API does not have shows no section', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET $public': (_) => apiError(404, 'PROFILE_NOT_FOUND')});
      await pumpInApp(tester, test, Scaffold(body: section()));
      await settle(tester);
      expect(find.byKey(const Key('profile-reviews')), findsNothing);
    });

    testWidgets('writes a review: stars, text, awaiting moderation', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET $public': (_) => publishedJson(),
        'GET /v1/me/dashboard': (_) => jsonResponse(403, {
          'error': {'code': 'FORBIDDEN', 'message': 'x'},
        }),
        'GET /v1/me/reviews/eligibility': (_) => eligibilityJson(),
        'POST /v1/me/reviews': (_) => jsonResponse(201, {
          'review': reviewJson(mine: true, status: 'PENDING', reply: false),
        }),
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, Scaffold(body: section()));
      await settle(tester);
      await tester.tap(find.byKey(const Key('write-review')));
      await settle(tester);
      expect(find.text('Your Enquiry BE-RVW4TNNT'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('review-text')), 'Too short');
      await tester.tap(find.byKey(const Key('review-send')));
      await settle(tester);
      expect(find.text('Choose 1 to 5 stars.'), findsOneWidget);
      expect(find.text('Write at least 20 characters.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-star-4')));
      await tester.enterText(
        find.byKey(const Key('review-text')),
        'Came the same day and fixed the geyser.',
      );
      await tester.tap(find.byKey(const Key('review-send')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post)['rating'], 4);
      expect(bodyOf(post)['basis'], {'kind': 'ENQUIRY', 'id': 'e-4'});
      expect(
        find.text('Thank you. Your review is awaiting moderation.'),
        findsOneWidget,
      );
    });

    testWidgets('says why a review cannot be written yet', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $public': (_) => publishedJson(),
        'GET /v1/me/dashboard': (_) => jsonResponse(403, {
          'error': {'code': 'FORBIDDEN', 'message': 'x'},
        }),
        'GET /v1/me/reviews/eligibility': (_) =>
            eligibilityJson(eligible: false, upcoming: 'TOO_RECENT'),
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, Scaffold(body: section()));
      await settle(tester);
      await tester.tap(find.byKey(const Key('write-review')));
      await settle(tester);
      expect(
        find.textContaining('you can review it from 1 Dec 2026'),
        findsOneWidget,
      );
    });

    testWidgets('reports a review once', (tester) async {
      final test = TestServices();
      var reported = false;
      serve(test, {
        'GET $public': (_) => publishedJson(),
        'POST /v1/reviews/r-1/report': (_) {
          if (reported) return apiError(409, 'REVIEW_ALREADY_REPORTED');
          reported = true;
          return jsonResponse(201, {
            'report': {'id': 'rep-1', 'status': 'OPEN'},
          });
        },
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, Scaffold(body: section()));
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('report-review-r-1')));
        await settle(tester);
        await tester.enterText(
          find.byType(TextField).last,
          'Not a real customer',
        );
        await tester.tap(find.text('Report').last);
        await settle(tester);
      }
      expect(find.textContaining('already reported'), findsOneWidget);
    });
  });

  group('reviews screens', () {
    testWidgets('written: status, moderation reason, delete', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/dashboard': (_) => jsonResponse(403, {
          'error': {'code': 'FORBIDDEN', 'message': 'x'},
        }),
        'GET /v1/me/reviews': (_) => {
          'items': [
            reviewJson(mine: true, status: 'PENDING', reply: false),
            reviewJson(id: 'r-3', mine: true, status: 'REJECTED', reply: false),
          ],
        },
        'DELETE /v1/me/reviews/r-1': (_) => jsonResponse(204, {}),
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, const ReviewsScreen());
      await settle(tester);
      expect(find.text('Awaiting moderation'), findsOneWidget);
      expect(find.text('Not published'), findsOneWidget);
      expect(find.text('Moderator: Personal details'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-delete-r-1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('review-delete-confirm')));
      await settle(tester);
      expect(
        test.workRequests.where((r) => r.method == 'DELETE').single.url.path,
        '/v1/me/reviews/r-1',
      );
    });

    testWidgets('received: reply once', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/dashboard': (_) => {
          'organisations': [
            {
              'id': 'org-9',
              'name': 'Sample Plumbers',
              'kind': 'SERVICE_PROVIDER',
              'market_code': 'ZW',
              'role': 'OWNER',
              'role_label': 'Owner',
            },
          ],
        },
        'GET /v1/me/reviews': (_) => {'items': []},
        'GET /v1/agent/organisations/org-9/reviews': (_) => {'items': []},
        'GET /v1/agent/organisations/org-9/reviews/received': (_) => {
          'items': [reviewJson(received: true, reply: false)],
          'total': 1,
          'page': 1,
          'page_size': 25,
          'permissions': {'reply': true},
        },
        'POST /v1/agent/organisations/org-9/reviews/r-1/reply': (_) =>
            jsonResponse(201, {'review': reviewJson(received: true)}),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const ReviewsScreen(tab: 'received'));
      await settle(tester);
      expect(find.text('Of your business'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-reply-r-1')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Thank you, Casey.');
      await tester.tap(find.text('Publish the reply'));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {'text': 'Thank you, Casey.'});
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $public': (_) => publishedJson(),
        'GET /v1/me/reviews/eligibility': (_) => eligibilityJson(),
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, Scaffold(body: section()), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const WriteReviewScreen(
          profileId: 'prof-1',
          providerName: 'Sample Plumbers',
          bases: [
            ReviewBasis(
              kind: 'ENQUIRY',
              id: 'e-4',
              label: 'Enquiry BE-RVW4TNNT',
            ),
          ],
        ),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
