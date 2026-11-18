import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/activity/activity_screen.dart';
import 'package:rightproperty365/features/saved/saved_listings_repository.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show serve, settle;

Map<String, dynamic> savedJson(
  String id, {
  bool available = true,
  String title = 'Garden cottage',
}) => {
  'listing_id': id,
  'saved_at': '2030-03-01T08:00:00Z',
  'available': available,
  'unavailable_reason': available ? null : 'LET',
  'unavailable_label': available ? null : 'Let',
  'listing': {
    // The API sends no slug for an unavailable listing; the app must not
    // link it even if one came.
    'slug': available ? 'garden-cottage' : 'old-slug',
    'reference': 'RP-ZW-10009',
    'title': title,
    'category': {'code': 'houses', 'label': 'Houses'},
    'price': {'amount': '850.00', 'currency': 'USD'},
    'price_period': 'month',
    'city': {'code': 'harare', 'label': 'Harare'},
    'country': {'code': 'ZW', 'name': 'Zimbabwe'},
    'photo': null,
  },
};

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
  'items': items,
  'page': 1,
  'page_size': 100,
  'total': items.length,
  'total_pages': 1,
};

void main() {
  group('saved listings API', () {
    test('reads ids and pages, saves and removes', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/me/saved-listings/ids': (_) => {
          'ids': ['a', 'b'],
        },
        'GET /v1/me/saved-listings': (_) => page([
          savedJson('a'),
          savedJson('b', available: false, title: 'Old flat'),
        ]),
        'PUT /v1/me/saved-listings/a': (_) => {
          'saved': true,
          'saved_at': '2030-03-01T08:00:00Z',
          'created': true,
        },
        'PUT /v1/me/saved-listings/gone': (_) =>
            apiError(404, 'LISTING_NOT_FOUND'),
        'DELETE /v1/me/saved-listings/b': (_) => http.Response('', 204),
      });
      final repository = ApiSavedListingsRepository(api);
      expect(await repository.ids(), {'a', 'b'});

      final list = await repository.list(pageSize: 100);
      expect(requests.last.url.queryParameters, {
        'page': '1',
        'page_size': '100',
      });
      expect(list.items.first.slug, 'garden-cottage');
      expect(list.items.first.priceText, 'USD 850 / month');
      final gone = list.items.last;
      expect(gone.available, isFalse);
      expect(gone.slug, isNull);
      expect(gone.unavailableLabel, 'Let');
      expect(gone.place, 'Harare, Zimbabwe');

      await repository.save('a');
      expect(requests.last.method, 'PUT');
      await expectLater(
        repository.save('gone'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('no longer listed'),
          ),
        ),
      );
      await repository.remove('b');
      expect(requests.last.method, 'DELETE');
    });
  });

  group('the hearts', () {
    test('follow the account and undo a refused save', () async {
      final test = TestServices();
      final listing = test.listings.listings[1];
      final local = test.listings.listings[2];
      final saves = <String>[];
      var refuse = false;
      serve(test, {
        'GET /v1/me/saved-listings/ids': (_) => {'ids': saves},
        'PUT /v1/me/saved-listings/${listing.id}': (_) {
          if (refuse) return apiError(500, 'INTERNAL');
          saves.add(listing.id);
          return {'saved': true, 'saved_at': '2030-01-01T00:00:00Z'};
        },
        'PUT /v1/me/saved-listings/${local.id}': (_) {
          saves.add(local.id);
          return {'saved': true, 'saved_at': '2030-01-01T00:00:00Z'};
        },
      });
      // Saved on this phone before saving needed an account.
      await test.activity.toggleSaved(local.slug);

      await test.auth.signIn('tom@example.test', 'pw');
      await pumpEventQueue();
      expect(test.saved.isSaved(local.id), isTrue);
      expect(test.activity.savedSlugs, isEmpty);

      expect(await test.saved.toggle(listing.id), isTrue);
      expect(test.saved.isSaved(listing.id), isTrue);

      refuse = true;
      final other = test.listings.listings[3].id;
      await expectLater(test.saved.toggle(other), throwsA(isA<ApiFailure>()));
      expect(test.saved.isSaved(other), isFalse);

      await test.auth.signOut();
      expect(test.saved.isSaved(listing.id), isFalse);
    });

    testWidgets('a guest signs in from the heart and comes back saved', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings[1];
      serve(test, {
        'GET /v1/me/saved-listings/ids': (_) => {'ids': <String>[]},
        'PUT /v1/me/saved-listings/${listing.id}': (_) => {
          'saved': true,
          'saved_at': '2030-01-01T00:00:00Z',
        },
      });
      final router = buildRouter();
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(appWith(test, router));
      router.push(Routes.listing(listing.slug));
      await settle(tester);

      await tester.tap(find.byKey(Key('save-${listing.id}')).first);
      await settle(tester);
      expect(find.text('Sign in to save properties'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-sign-in')));
      await settle(tester);
      expect(router.state.uri.path, Routes.signIn);

      // Signing in itself is covered by the sign-in tests.
      await test.auth.signIn('tom@example.test', 'pw');
      router.pop();
      await settle(tester);
      expect(router.state.uri.path, startsWith('/listings/'));
      expect(
        test.workRequests.where((r) => r.method == 'PUT').single.url.path,
        '/v1/me/saved-listings/${listing.id}',
      );
      expect(
        find.byTooltip('Saved. Remove ${listing.title} from saved'),
        findsWidgets,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the Saved tab greys out a let property and removes it', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings[1];
      var items = [
        savedJson(listing.id),
        savedJson('gone-1', available: false, title: 'Old flat'),
      ];
      serve(test, {
        'GET /v1/me/saved-listings/ids': (_) => {
          'ids': [listing.id],
        },
        'GET /v1/me/saved-listings': (_) => page(items),
        'GET /v1/me/property-requests': (_) => {
          'items': [],
          'total': 0,
          'page': 1,
          'page_size': 50,
          'total_pages': 0,
          'status_counts': [],
        },
        'DELETE /v1/me/saved-listings/gone-1': (_) {
          items = [savedJson(listing.id)];
          return http.Response('', 204);
        },
      });
      await test.auth.signIn('tom@example.test', 'pw');
      await pumpInApp(tester, test, const ActivityScreen());
      await settle(tester);
      await tester.ensureVisible(find.text('Saved Properties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved Properties'));
      await settle(tester);

      // The available one is the full listing card; the let one is greyed
      // and labelled, with no link to it.
      expect(find.text(listing.title), findsOneWidget);
      expect(find.text('Old flat'), findsOneWidget);
      expect(find.text('Let'), findsOneWidget);
      expect(find.text('View property'), findsNothing);

      await tester.tap(find.byKey(const Key('remove-saved-gone-1')));
      await settle(tester);
      expect(find.text('Old flat'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('signed out, the Saved tab asks to sign in', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const ActivityScreen());
      await settle(tester);
      await tester.ensureVisible(find.text('Saved Properties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved Properties'));
      await settle(tester);
      expect(find.text('Save properties to your account'), findsOneWidget);
    });
  });
}
