import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/features/notifications/link_opener.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';

import 'support.dart';
import 'work_test.dart' show dashboard, serve, settle;

String? go(String link) => webLinkRedirect(Uri.parse(link));

void main() {
  group('website links', () {
    test('paths the app has as such stay as they are', () {
      for (final link in [
        '/listings/borrowdale-house',
        '/apply/borrowdale-house',
        '/sign/abc123',
        '/invitations/tok',
        '/verify-email?token=x',
        '/reset-password?token=x',
        '/account',
        '/',
      ]) {
        expect(go(link), isNull, reason: link);
      }
    });

    test('directory and search paths map to the app\'s', () {
      expect(
        go('/directory/service-providers/sample-plumbers'),
        '/profiles/service-providers/sample-plumbers',
      );
      expect(go('/directory/agencies'), '/profiles/agencies');
      expect(go('/listings'), Routes.search());
      expect(go('/dashboard'), Routes.account);
    });

    test('account and work paths go through the opener', () {
      expect(
        go('/account/applications/app-1'),
        '/open?to=%2Faccount%2Fapplications%2Fapp-1',
      );
      expect(
        go('/agent/requests#business-enquiries'),
        '/open?to=%2Fagent%2Frequests%23business-enquiries',
      );
    });

    test('the manifest claims what the app opens', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final prefix in [
        '/listings/',
        '/directory/',
        '/apply/',
        '/sign/',
        '/invitations/',
        '/account/',
        '/agent/',
      ]) {
        expect(manifest, contains('android:pathPrefix="$prefix"'));
      }
      expect(manifest, contains('android:autoVerify="true"'));
      final entitlements = File('ios/Runner/Runner.entitlements')
          .readAsStringSync();
      expect(entitlements, contains('applinks:rightproperty365.com'));
    });
  });

  group('the resolver', () {
    late TestServices app;
    setUp(() async {
      app = TestServices();
      serve(app, {
        'GET /v1/me/dashboard': (_) => dashboard,
        'GET /v1/agent/organisations/org-1/inspections/i-1': (_) => {
          'inspection': {
            'id': 'i-1',
            'scheduled_for': '2026-11-26T09:00:00Z',
            'progress': {},
          },
        },
      });
      await app.auth.signIn('tendai@example.test', 'pw');
    });

    Future<String> where(String link) async =>
        switch (await resolveNotificationLink(link, app.services)) {
          InApp(:final location) => location,
          OnWebsite(:final url) => 'web $url',
        };

    test('more account and work pages', () async {
      expect(await where('/account/saved'), '/activity?tab=saved');
      expect(await where('/account/requests/r-1'), Routes.myRequest('r-1'));
      expect(await where('/account/signing'), Routes.documentsToSign);
      expect(
        await where('/account/notification-preferences'),
        Routes.notificationPreferences,
      );
      expect(await where('/agent/leases/l-1'), Routes.lease('l-1'));
      expect(
        await where('/agent/inspections/i-1'),
        Routes.inspection('org-1', 'i-1'),
      );
      expect(await where('/agent/properties'), Routes.properties);
    });

    test('hourly bookings, from emails and calendar entries', () async {
      // The website path goes through the opener, then to the bookings tab.
      expect(
        go('/account/venue-bookings'),
        '/open?to=%2Faccount%2Fvenue-bookings',
      );
      expect(await where('/account/venue-bookings'), '/activity?tab=bookings');
      // The path older booking emails used.
      expect(await where('/account/hourly-bookings'), '/activity?tab=bookings');
      // A host's calendar entry links the hosted bookings.
      expect(await where('/agent/venue-bookings'), Routes.hostedVenueBookings);
    });

    test('pages the app has not got open the website', () async {
      expect(
        await where('/agent/forms/f-1'),
        'web https://rightproperty365.com/agent/forms/f-1',
      );
    });
  });

  group('the opener', () {
    testWidgets('a guest is asked to sign in, then it opens', (tester) async {
      final test = TestServices();
      serve(test, {'GET /v1/me/dashboard': (_) => dashboard});
      final router = buildRouter();
      await tester.pumpWidget(appWith(test, router));
      await settle(tester);
      router.go(go('/account/notification-preferences')!);
      await settle(tester);
      expect(find.byType(LinkOpenerScreen), findsOneWidget);
      expect(find.text('Sign in to open this'), findsOneWidget);
      await test.auth.signIn('tendai@example.test', 'pw');
      await settle(tester);
      expect(find.text('Notification settings'), findsWidgets);
      expect(find.byType(LinkOpenerScreen), findsNothing);
    });

    testWidgets('a page the app has not got opens in a browser tab', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET /v1/me/dashboard': (_) => dashboard});
      await test.auth.signIn('tendai@example.test', 'pw');
      final router = buildRouter();
      await tester.pumpWidget(appWith(test, router));
      await settle(tester);
      router.go(go('/agent/forms/f-1')!);
      await settle(tester);
      expect(
        test.opened.single.toString(),
        'https://rightproperty365.com/agent/forms/f-1',
      );
      expect(router.routerDelegate.currentConfiguration.uri.path, Routes.home);
    });
  });
}
