import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/push/push_messaging.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/notifications/notification_bell.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';
import 'package:rightproperty365/features/notifications/notifications_repository.dart';
import 'package:rightproperty365/features/notifications/notifications_screens.dart';

import 'api_routes.dart';
import 'applications_test.dart' as apps show appJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, dashboard, serve, settle;

/// A phone where push works as far as the app can tell.
class FakePush implements PushMessaging {
  PushState current = PushState.notAsked;
  PushState answer = PushState.allowed;
  String? deviceToken = 'fcm-token-1';
  int asked = 0;
  int deleted = 0;
  final changes = StreamController<String>.broadcast();
  final arriving = StreamController<PushMessage>.broadcast();
  final tapped = StreamController<PushMessage>.broadcast();
  PushMessage? launch;

  @override
  Future<PushState> state() async => current;

  @override
  Future<PushState> requestPermission() async {
    asked++;
    return current = answer;
  }

  @override
  Future<String?> token() async =>
      current == PushState.allowed ? deviceToken : null;

  @override
  Stream<String> get tokenChanges => changes.stream;

  @override
  Future<void> deleteToken() async => deleted++;

  @override
  Stream<PushMessage> get received => arriving.stream;

  @override
  Stream<PushMessage> get opened => tapped.stream;

  @override
  Future<PushMessage?> launchMessage() async => launch;
}

Map<String, dynamic> itemJson({
  String id = 'n-1',
  String type = 'NEW_LEAD',
  String title = 'New property enquiry',
  String body = 'PR-ZW-10001 · Borrowdale',
  String link = '/agent/requests/req-1',
  bool read = false,
}) => {
  'id': id,
  'type': type,
  'title': title,
  'body': body,
  'link': link,
  'reference': 'PR-ZW-10001',
  'created_at': '2026-11-19T08:30:00Z',
  'read_at': read ? '2026-11-19T09:00:00Z' : null,
};

Map<String, dynamic> pageJson(
  List<Map<String, dynamic>> items, {
  int unread = 1,
  int total = 1,
  int page = 1,
}) => {
  'items': items,
  'unread_count': unread,
  'page': page,
  'page_size': 20,
  'total': total,
};

Map<String, dynamic> preferencesJson({bool leadEmail = true}) => {
  'items': [
    {
      'type': 'NEW_LEAD',
      'label': 'New property enquiries',
      'essential': false,
      'essential_reason': null,
      'email': leadEmail,
      'push': true,
      'in_app': true,
      'changed_at': null,
      'source': null,
    },
    {
      'type': 'SECURITY',
      'label': 'Security notices',
      'essential': true,
      'essential_reason':
          'Security notices protect your account and cannot be turned off.',
      'email': true,
      'push': true,
      'in_app': true,
      'changed_at': null,
      'source': null,
    },
  ],
};

void main() {
  group('the notifications API', () {
    test('lists, counts and marks read', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/me/notifications': (_) =>
            pageJson([itemJson()], unread: 3, total: 41),
        'GET /v1/me/notifications/unread-count': (_) => {'unread_count': 3},
        'POST /v1/me/notifications/n-1/read': (_) => {
          'notification': itemJson(read: true),
          'unread_count': 2,
        },
        'POST /v1/me/notifications/read-all': (_) => {
          'marked': 2,
          'unread_count': 0,
        },
      });
      final repo = NotificationsRepository(api);
      final page = await repo.list(page: 2, unreadOnly: true);
      expect(requests.last.url.queryParameters, {
        'page': '2',
        'unread': 'true',
      });
      expect(page.items.single.title, 'New property enquiry');
      expect(page.items.single.unread, isTrue);
      expect(page.hasMore, isTrue);
      expect(await repo.unreadCount(), 3);
      final read = await repo.markRead('n-1');
      expect(read.unreadCount, 2);
      expect(read.notification.unread, isFalse);
      expect(await repo.markAllRead(), 0);
    });

    test('saves one preference, telling the API it is the app', () async {
      final (:api, :requests) = routedApi({
        'PUT /v1/me/notification-preferences': (_) =>
            preferencesJson(leadEmail: false),
      });
      final saved = await NotificationsRepository(api)
          .setPreference('NEW_LEAD', email: false);
      expect(jsonBody(requests.single), {
        'items': [
          {'type': 'NEW_LEAD', 'email': false},
        ],
      });
      expect(requests.single.headers['X-Client'], 'app');
      expect(saved.first.email, isFalse);
      expect(saved.last.essential, isTrue);
    });

    test('registers and removes this phone', () async {
      final (:api, :requests) = routedApi({
        'POST /v1/me/devices': (_) => jsonResponse(201, {'device_id': 'd-1'}),
        'DELETE /v1/me/devices': (_) => apiError(404, 'DEVICE_NOT_FOUND'),
      });
      final repo = NotificationsRepository(api);
      expect(
        await repo.registerDevice(
          token: 'fcm-token-1',
          platform: 'ANDROID',
          appVersion: '1.0.0',
          locale: 'en-ZW',
        ),
        'd-1',
      );
      expect(jsonBody(requests.first), {
        'token': 'fcm-token-1',
        'platform': 'ANDROID',
        'app_version': '1.0.0',
        'locale': 'en-ZW',
        'push_consent': true,
      });
      // A token the API no longer has is already gone.
      await repo.removeDevice('fcm-token-1');
      expect(requests.last.url.queryParameters['token'], 'fcm-token-1');
    });

    test('logout carries the push token only when there is one', () async {
      final (:api, :requests) = routedApi({
        'POST /v1/auth/logout': (_) => http.Response('', 204),
      });
      await ApiAuthRepository(api).logout(deviceToken: 'fcm-token-1');
      await ApiAuthRepository(api).logout();
      expect(jsonBody(requests.first), {'device_token': 'fcm-token-1'});
      expect(jsonBody(requests.last), isEmpty);
    });
  });

  group('push on this phone', () {
    late TestServices app;
    late FakePush push;
    setUp(() {
      app = TestServices();
      push = FakePush();
      app.push = push;
      serve(app, {
        'GET /v1/me/notifications/unread-count': (_) => {'unread_count': 4},
        'POST /v1/me/devices': (_) => jsonResponse(201, {'device_id': 'd-1'}),
        'DELETE /v1/me/devices': (_) => http.Response('', 204),
      });
    });

    List<http.Request> devicePosts() => [
      for (final r in app.workRequests)
        if (r.method == 'POST' && r.url.path == '/v1/me/devices') r,
    ];

    test(
      'is never asked for or registered until the person turns it on',
      () async {
        await app.auth.signIn('tendai@example.test', 'pw');
        await app.notificationCentre.start();
        await pumpEventQueue();
        expect(push.asked, 0);
        expect(devicePosts(), isEmpty);
        expect(app.notificationCentre.unreadCount, 4);

        expect(await app.notificationCentre.turnOnPush(), PushState.allowed);
        expect(push.asked, 1);
        expect(bodyOf(devicePosts().single), {
          'token': 'fcm-token-1',
          'platform': 'ANDROID',
          'app_version': '1.0.0',
          'locale': 'en-ZW',
          'push_consent': true,
        });
        expect(app.notificationCentre.pushOn, isTrue);
      },
    );

    test(
      'a refused prompt registers nothing; the centre still counts',
      () async {
        push.answer = PushState.refused;
        await app.auth.signIn('tendai@example.test', 'pw');
        expect(await app.notificationCentre.turnOnPush(), PushState.refused);
        expect(devicePosts(), isEmpty);
        await app.notificationCentre.refresh();
        expect(app.notificationCentre.unreadCount, 4);
      },
    );

    test('a new token is registered again', () async {
      await app.auth.signIn('tendai@example.test', 'pw');
      await app.notificationCentre.start();
      await app.notificationCentre.turnOnPush();
      push.deviceToken = 'fcm-token-2';
      push.changes.add('fcm-token-2');
      await pumpEventQueue();
      expect(bodyOf(devicePosts().last)['token'], 'fcm-token-2');
    });

    test('sign-out hands the token to logout and forgets push', () async {
      await app.auth.signIn('tendai@example.test', 'pw');
      await app.notificationCentre.turnOnPush();
      await app.auth.signOut();
      await pumpEventQueue();
      expect(app.authRepository.logoutDeviceToken, 'fcm-token-1');
      expect(push.deleted, 1);
      expect(app.notificationCentre.optedIn, isFalse);
      expect(app.notificationCentre.unreadCount, 0);
    });

    test('turning it off removes this phone from the account', () async {
      await app.auth.signIn('tendai@example.test', 'pw');
      await app.notificationCentre.turnOnPush();
      await app.notificationCentre.turnOffPush();
      final delete = app.workRequests.lastWhere((r) => r.method == 'DELETE');
      expect(delete.url.queryParameters['token'], 'fcm-token-1');
      expect(app.notificationCentre.pushOn, isFalse);
    });
  });

  group('notification links', () {
    late TestServices app;
    setUp(() async {
      app = TestServices();
      serve(app, {
        'GET /v1/me/dashboard': (_) => dashboard,
        'GET /v1/agent/organisations/org-1/applications/app-9': (_) => {
          'application': apps.appJson(),
        },
      });
      await app.auth.signIn('tendai@example.test', 'pw');
    });

    Future<String> where(String link) async =>
        switch (await resolveNotificationLink(link, app.services)) {
          InApp(:final location) => location,
          OnWebsite(:final url) => 'web $url',
        };

    test('open the app\'s own screens', () async {
      expect(await where('/agent/requests/req-1'), Routes.lead('req-1'));
      expect(await where('/agent/requests#business-enquiries'), Routes.inbox);
      expect(await where('/agent/appointments'), Routes.receivedAppointments);
      expect(await where('/account/appointments'), '/activity?tab=viewings');
      expect(
        await where('/account/applications/app-1'),
        Routes.myApplication('app-1'),
      );
      expect(
        await where('/agent/applications/app-9'),
        Routes.receivedApplication('org-1', 'app-9'),
      );
      expect(await where('/agent/venue-bookings'), Routes.hostedVenueBookings);
      expect(await where('/account/venue-bookings'), '/activity?tab=bookings');
      expect(await where('/account'), Routes.account);
      expect(await where('/account/notifications'), Routes.notifications);
      // Listing review and expiry notices (API 0.45.0).
      expect(await where('/agent/listings/l-1'), Routes.myListing('l-1'));
      expect(await where('/agent/listings'), Routes.myListings);
    });

    test('pages the app has not got open on the website', () async {
      expect(
        await where('/agent/listings/l-1/availability'),
        'web https://rightproperty365.com/agent/listings/l-1/availability',
      );
      expect(
        await where('/agent/listings/new'),
        'web https://rightproperty365.com/agent/listings/new',
      );
    });

    test('never follow a link off-site', () async {
      expect(await where('https://evil.example/x'), Routes.notifications);
      expect(await where('//evil.example/x'), Routes.notifications);
    });
  });

  group('the notification centre', () {
    testWidgets('lists, marks read on opening and opens the link', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/notifications': (_) => pageJson([
          itemJson(),
          itemJson(
            id: 'n-2',
            type: 'LISTING_REVIEWED',
            title: 'Listing approved',
            body: 'RP-ZW-10001',
            link: '/agent/listings/new',
            read: true,
          ),
        ]),
        'GET /v1/me/notifications/unread-count': (_) => {'unread_count': 1},
        'POST /v1/me/notifications/n-2/read': (_) => {
          'notification': itemJson(id: 'n-2', read: true),
          'unread_count': 1,
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      final router = GoRouter(
        initialLocation: Routes.notifications,
        routes: [
          GoRoute(
            path: Routes.notifications,
            builder: (_, _) => const NotificationsScreen(),
          ),
        ],
      );
      await tester.pumpWidget(appWith(test, router));
      await settle(tester);

      expect(find.text('New property enquiry'), findsOneWidget);
      expect(find.text('PR-ZW-10001 · Borrowdale'), findsOneWidget);
      expect(find.byKey(const Key('notifications-read-all')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Unread. New property enquiry')),
        findsOneWidget,
      );
      // Push is not available in tests: said plainly, nothing breaks.
      expect(find.text('Push is not available on this phone'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification-n-2')));
      await settle(tester);
      // Already read: no read call; the website opens what the app has not.
      expect(
        test.workRequests.where((r) => r.url.path.endsWith('/read')),
        isEmpty,
      );
      expect(
        test.opened.single.toString(),
        'https://rightproperty365.com/agent/listings/new',
      );
    });

    testWidgets('read all clears the count', (tester) async {
      final test = TestServices();
      var read = false;
      serve(test, {
        'GET /v1/me/notifications': (_) =>
            pageJson([itemJson(read: read)], unread: read ? 0 : 1),
        'POST /v1/me/notifications/read-all': (_) {
          read = true;
          return {'marked': 1, 'unread_count': 0};
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const NotificationsScreen());
      await settle(tester);
      expect(test.notificationCentre.unreadCount, 1);
      await tester.tap(find.byKey(const Key('notifications-read-all')));
      await settle(tester);
      expect(test.notificationCentre.unreadCount, 0);
      expect(find.byKey(const Key('notifications-read-all')), findsNothing);
    });

    testWidgets('offers push only when asked, and turns it on', (tester) async {
      final test = TestServices();
      final push = FakePush();
      test.push = push;
      serve(test, {
        'GET /v1/me/notifications': (_) => pageJson([], unread: 0, total: 0),
        'POST /v1/me/devices': (_) => jsonResponse(201, {'device_id': 'd-1'}),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await test.notificationCentre.refreshPushState();
      await pumpInApp(tester, test, const NotificationsScreen());
      await settle(tester);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(push.asked, 0);
      await tester.tap(find.byKey(const Key('push-turn-on')));
      await settle(tester);
      expect(push.asked, 1);
      expect(find.text('Push is on for this phone'), findsOneWidget);
    });

    testWidgets('the bell shows the unread count', (tester) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      test.notificationCentre.setUnread(3);
      await pumpInApp(
        tester,
        test,
        Scaffold(appBar: AppBar(actions: const [NotificationBell()])),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/notifications': (_) => pageJson([itemJson()]),
        'GET /v1/me/notification-preferences': (_) => preferencesJson(),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const NotificationsScreen(), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const NotificationPreferencesScreen(),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('notification settings', () {
    testWidgets('switch email per type; essential types are locked', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/notification-preferences': (_) => preferencesJson(),
        'PUT /v1/me/notification-preferences': (_) =>
            preferencesJson(leadEmail: false),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const NotificationPreferencesScreen());
      await settle(tester);

      expect(find.text('New property enquiries'), findsOneWidget);
      expect(
        find.text(
          'Security notices protect your account and cannot be turned off.',
        ),
        findsOneWidget,
      );
      Switch switchIn(String key) => tester.widget<Switch>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Switch),
        ),
      );
      // Essential: locked on, with no switch to turn off.
      expect(
        find.descendant(
          of: find.byKey(const Key('preference-SECURITY')),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );
      expect(find.text('Email: always on'), findsOneWidget);
      expect(find.text('Push: always on'), findsOneWidget);
      expect(find.text('In the app: always on'), findsNWidgets(2));

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('preference-NEW_LEAD-email')),
          matching: find.byType(Switch),
        ),
      );
      await settle(tester);
      final put = test.workRequests.lastWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.body), {
        'items': [
          {'type': 'NEW_LEAD', 'email': false},
        ],
      });
      expect(switchIn('preference-NEW_LEAD-email').value, isFalse);
    });
  });

  group('a tapped push', () {
    testWidgets('opens the same screen as the in-app item and marks it read', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'POST /v1/me/notifications/n-1/read': (_) => {
          'notification': itemJson(read: true),
          'unread_count': 0,
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(
            path: '/inbox/:id',
            builder: (_, state) => Text('lead ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(appWith(test, router));
      final handler = PushHandler(
        services: test.services,
        router: router,
        messenger: GlobalKey<ScaffoldMessengerState>(),
      );
      await handler.open(
        const PushMessage(
          title: 'New property enquiry',
          type: 'NEW_LEAD',
          link: '/agent/requests/req-1',
          notificationId: 'n-1',
        ),
      );
      await settle(tester);
      expect(find.text('lead req-1'), findsOneWidget);
      expect(
        test.workRequests
            .where((r) => r.url.path.endsWith('/read'))
            .single
            .url
            .path,
        '/v1/me/notifications/n-1/read',
      );
    });
  });
}
