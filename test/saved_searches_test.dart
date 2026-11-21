import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/presentation/search_screen.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';
import 'package:rightproperty365/features/saved/saved_searches.dart';
import 'package:rightproperty365/features/saved/saved_searches_screen.dart';

import 'searchable_select_test.dart' show openField;
import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

Map<String, dynamic> savedJson(
  String id,
  String name, {
  String query = 'deal=rent&category=residential&q=Avondale',
  String frequency = 'DAILY',
}) => {
  'id': id,
  'name': name,
  'query': query,
  'frequency': frequency,
  'last_alert_at': '2030-03-01T08:00:00Z',
  'created_at': '2030-02-01T08:00:00Z',
  'updated_at': '2030-02-01T08:00:00Z',
};

void main() {
  group('the model', () {
    test('the query string is the API search query', () {
      expect(
        searchQueryOf(
          const ListingFilters(
            deal: DealType.rent,
            category: ListingCategory.shortStay,
            query: ' Victoria Falls ',
          ),
        ),
        'q=Victoria+Falls&deal=rent&category=short-stay',
      );
      expect(searchQueryOf(const ListingFilters()), '');
    });

    test('a saved query opens with the filters the app has', () {
      final s = SavedSearch.fromJson(
        savedJson('s-1', 'x', query: 'category=short-stay&deal=sale&q=Kariba'),
      );
      expect(s.filters.category, ListingCategory.shortStay);
      expect(s.filters.deal, DealType.sale);
      expect(s.filters.query, 'Kariba');
      expect(s.hasWebOnlyFilters, isFalse);
      expect(
        SavedSearch.fromJson(
          savedJson('s-2', 'x', query: 'deal=rent&min_price=300'),
        ).hasWebOnlyFilters,
        isTrue,
      );
      expect(
        savedSearchRoute(s),
        Routes.search(
          query: 'Kariba',
          deal: DealType.sale,
          category: ListingCategory.shortStay,
        ),
      );
    });

    test('a default name from the filters', () {
      expect(
        searchSummary(
          const ListingFilters(
            deal: DealType.rent,
            category: ListingCategory.residential,
            query: 'Avondale',
          ),
        ),
        'Homes to rent: Avondale',
      );
      expect(searchSummary(const ListingFilters()), 'Property');
    });
  });

  group('saving a search', () {
    testWidgets('from Search, with a name and how often', (tester) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      serve(test, {
        'POST /v1/me/saved-searches': (r) => http.Response(
          '{"saved_search":{"id":"s-9","name":"${bodyOf(r)['name']}",'
          '"query":"${bodyOf(r)['query']}","frequency":'
          '"${bodyOf(r)['frequency']}"}}',
          201,
        ),
      });
      await pumpInApp(
        tester,
        test,
        const SearchScreen(
          initial: ListingFilters(deal: DealType.rent, query: 'Avondale'),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-search')));
      await settle(tester);
      expect(find.text('Property to rent: Avondale'), findsOneWidget);
      await openField(tester, const Key('save-search-frequency'));
      await tester.tap(find.text('Once a week').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-search-confirm')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {
        'name': 'Property to rent: Avondale',
        'query': 'q=Avondale&deal=rent',
        'frequency': 'WEEKLY',
      });
      expect(find.textContaining('Search saved.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('signed out, it asks to sign in first', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const SearchScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-search')));
      await settle(tester);
      expect(find.text('Sign in to save searches'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(test.workRequests, isEmpty);
    });

    testWidgets('the limit says what to do', (tester) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      serve(test, {
        'POST /v1/me/saved-searches': (_) => failure(409, 'SAVED_SEARCH_LIMIT'),
      });
      await pumpInApp(tester, test, const SearchScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-search')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-search-confirm')));
      await settle(tester);
      expect(
        find.textContaining('Delete one to save this search'),
        findsOneWidget,
      );
    });
  });

  group('the list', () {
    testWidgets('rename, change alerts, delete', (tester) async {
      final test = TestServices();
      var item = savedJson('s-1', 'Avondale rentals');
      serve(test, {
        'GET /v1/me/saved-searches': (_) => {
          'items': [
            item,
            savedJson('s-2', 'Plots', query: 'category=land&min_price=5000'),
          ],
        },
        'PATCH /v1/me/saved-searches/s-1': (r) {
          item = {...item, ...bodyOf(r)};
          return {'saved_search': item};
        },
        'DELETE /v1/me/saved-searches/s-2': (_) => http.Response('', 204),
      });
      await pumpInApp(tester, test, const SavedSearchesScreen());
      await settle(tester);
      expect(find.text('Avondale rentals'), findsOneWidget);
      expect(find.textContaining('only on the website'), findsOneWidget);

      await openField(tester, const Key('saved-search-frequency-s-1'));
      await tester.tap(find.text('As soon as they appear').last);
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {'frequency': 'INSTANT'});

      await tester.tap(find.byKey(const Key('saved-search-rename-s-1')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('rename-search-name')),
        'Avondale homes',
      );
      await tester.tap(find.byKey(const Key('rename-search-confirm')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {'name': 'Avondale homes'});
      expect(find.text('Avondale homes'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('saved-search-delete-s-2')),
      );
      await tester.tap(find.byKey(const Key('saved-search-delete-s-2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('delete-search-confirm')));
      await settle(tester);
      expect(find.text('Plots'), findsNothing);
    });

    testWidgets('none yet', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/saved-searches': (_) => {'items': []},
      });
      await pumpInApp(tester, test, const SavedSearchesScreen());
      await settle(tester);
      expect(find.byKey(const Key('saved-searches-empty')), findsOneWidget);
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/saved-searches': (_) => {
          'items': [savedJson('s-1', 'Avondale rentals')],
        },
      });
      await pumpInApp(tester, test, const SavedSearchesScreen(), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  test('an alert opens its search; the list without an id', () async {
    final app = TestServices();
    serve(app, {
      'GET /v1/me/saved-searches': (_) => {
        'items': [savedJson('s-1', 'Avondale rentals')],
      },
    });
    Future<String> where(String link) async =>
        switch (await resolveNotificationLink(link, app.services)) {
          InApp(:final location) => location,
          OnWebsite(:final url) => 'web $url',
        };
    expect(await where('/account/saved-searches'), Routes.savedSearches);
    expect(
      await where('/account/saved-searches/s-1'),
      Routes.search(
        query: 'Avondale',
        deal: DealType.rent,
        category: ListingCategory.residential,
      ),
    );
    expect(await where('/account/saved-searches/gone'), Routes.savedSearches);
  });
}
