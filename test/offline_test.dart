import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/api/offline.dart';
import 'package:rightproperty365/core/widgets/offline_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';
import 'work_test.dart' show serve, settle;

/// An API that answers until [down] is set, then cannot be reached.
({ApiClient api, Connectivity connectivity, MemoryResponseCache cache})
offlineApi({required bool Function() down, Object? error}) {
  final connectivity = Connectivity();
  final cache = MemoryResponseCache();
  final api = ApiClient(
    baseUrl: 'http://api.test',
    cache: cache,
    connectivity: connectivity,
    httpClient: MockClient((request) async {
      if (down()) throw error ?? SocketLikeError();
      return http.Response(
        jsonEncode({'path': request.url.path, 'items': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (api: api, connectivity: connectivity, cache: cache);
}

class SocketLikeError extends http.ClientException {
  SocketLikeError() : super('Failed host lookup');
}

void main() {
  group('offline answers', () {
    test('own activity and listings are shown from this phone', () async {
      var down = false;
      final (:api, :connectivity, :cache) = offlineApi(down: () => down);
      await api.get('/v1/me/applications');
      await pumpEventQueue();
      expect(connectivity.online, isTrue);

      down = true;
      final copy = await api.get('/v1/me/applications');
      expect(copy.body['path'], '/v1/me/applications');
      expect(copy.savedAt, isNotNull);
      expect(connectivity.online, isFalse);
      expect(connectivity.showingFrom, copy.savedAt);

      // Never seen before: nothing to show.
      await expectLater(
        api.get('/v1/me/tenancies'),
        throwsA(isA<ApiFailure>().having((f) => f.isNetwork, 'network', true)),
      );
      down = false;
      await api.get('/v1/listings?page=1');
      expect(connectivity.online, isTrue);
      expect(connectivity.showingFrom, isNull);
      expect(cache.entries.keys, contains('/v1/listings?page=1'));
    });

    test('other people\'s details are never kept', () async {
      final (:api, connectivity: _, :cache) = offlineApi(down: () => false);
      await api.get('/v1/agent/organisations/org-1/contacts');
      await api.get('/v1/inbox/business-enquiries');
      await api.get('/v1/me/dashboard');
      await pumpEventQueue();
      expect(cache.entries, isEmpty);
      expect(keptOffline('/v1/me'), isTrue);
      expect(keptOffline('/v1/me/tenancies/t-1/dues'), isTrue);
      expect(keptOffline('/v1/meeting'), isFalse);
      expect(keptOffline('/v1/me/applications/app-1'), isTrue);
      expect(keptOffline('/v1/me/applications/app-1/files/f-1'), isFalse);
    });

    test(
      'a change that cannot leave the phone says nothing was sent',
      () async {
        final (:api, :connectivity, cache: _) = offlineApi(down: () => true);
        await expectLater(
          api.postJson('/v1/property-requests', {'x': 1}),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('Nothing was sent'),
            ),
          ),
        );
        expect(connectivity.online, isFalse);
        final (api: slow, connectivity: _, cache: _) = offlineApi(
          down: () => true,
          error: TimeoutException('slow'),
        );
        await expectLater(
          slow.postJson('/v1/me/applications/a-1/submit', {}),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('Check whether it went through'),
            ),
          ),
        );
      },
    );

    test('the copy is kept to a limit and emptied at sign-out', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = PreferencesResponseCache(
        await SharedPreferences.getInstance(),
        limit: 2,
      );
      await cache.write('/v1/me', '{"a":1}');
      await cache.write('/v1/me/applications', '{"b":2}');
      await cache.write('/v1/listings', '{"c":3}');
      expect(cache.read('/v1/me'), isNull);
      expect(cache.read('/v1/listings')!.body, '{"c":3}');

      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      forgetAtSignOut(test.auth, () => test.auth.signedIn, cache);
      await test.auth.signOut();
      await pumpEventQueue();
      expect(cache.read('/v1/listings'), isNull);
      expect(cache.read('/v1/me/applications'), isNull);
    });
  });

  group('saving a property offline', () {
    late TestServices app;
    var down = false;
    final sent = <String>[];

    setUp(() async {
      down = false;
      sent.clear();
      app = TestServices();
      app.workHandler = (request) async {
        if (down) throw SocketLikeError();
        sent.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return jsonResponse(200, {'items': [], 'total': 0});
        }
        return jsonResponse(200, {});
      };
      await app.auth.signIn('tendai@example.test', 'pw');
      await pumpEventQueue();
    });

    test('waits on the phone and is sent when back online', () async {
      down = true;
      expect(await app.saved.toggle('l-1'), isTrue);
      expect(app.saved.isSaved('l-1'), isTrue);
      expect(app.saved.isPending('l-1'), isTrue);
      expect(app.connectivity.online, isFalse);

      down = false;
      sent.clear();
      app.connectivity.reachable();
      await pumpEventQueue();
      expect(sent, contains('PUT /v1/me/saved-listings/l-1'));
      expect(app.saved.isPending('l-1'), isFalse);
      expect(app.saved.isSaved('l-1'), isTrue);
    });

    test('changed back before it was sent: nothing is sent', () async {
      down = true;
      await app.saved.toggle('l-2');
      await app.saved.toggle('l-2');
      expect(app.saved.pendingCount, 0);
      expect(app.saved.isSaved('l-2'), isFalse);
    });

    test('sign-out forgets what was waiting', () async {
      down = true;
      await app.saved.toggle('l-3');
      expect(app.saved.pendingCount, 1);
      down = false;
      await app.auth.signOut();
      await pumpEventQueue();
      expect(app.saved.pendingCount, 0);
    });
  });

  group('the banner', () {
    testWidgets('says the phone is offline and how old the copy is', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {});
      var pings = 0;
      test.connectivity.probe = () async {
        pings++;
        return true;
      };
      await pumpInApp(
        tester,
        test,
        OfflineBanner(
          connectivity: test.connectivity,
          child: const Scaffold(body: Text('screen')),
        ),
      );
      expect(find.byKey(const Key('offline-banner')), findsNothing);

      test.connectivity.unreachable();
      await tester.pump();
      expect(find.textContaining('nothing is sent until then'), findsOneWidget);
      test.connectivity.servedFromCopy(DateTime(2026, 11, 19, 8, 30));
      await tester.pump();
      expect(find.textContaining('saved on 19 Nov, 08:30'), findsOneWidget);
      expect(find.text('screen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('offline-retry')));
      await settle(tester);
      expect(pings, 1);
      expect(find.byKey(const Key('offline-banner')), findsNothing);
    });
  });
}
