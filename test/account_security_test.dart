import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/auth/presentation/account_security_screen.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';

import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

Map<String, dynamic> session(
  String id,
  String client, {
  bool current = false,
}) => {
  'id': id,
  'created_at': '2026-11-01T08:00:00Z',
  'last_seen_at': '2026-11-21T09:30:00Z',
  'expires_at': '2026-12-21T09:30:00Z',
  'client': client,
  'current': current,
};

void main() {
  group('the password', () {
    testWidgets('is changed with the current one; others are signed out', (
      tester,
    ) async {
      final test = TestServices();
      var sessionsAsked = 0;
      serve(test, {
        'GET /v1/me/sessions': (_) {
          sessionsAsked++;
          return {
            'items': [
              session('s-1', 'RightProperty365 app on Android', current: true),
              if (sessionsAsked == 1) session('s-2', 'Chrome on Windows'),
            ],
          };
        },
        'POST /v1/me/password': (_) => http.Response('', 204),
      });
      await pumpInApp(tester, test, const AccountSecurityScreen());
      await settle(tester);
      expect(find.text('Chrome on Windows'), findsOneWidget);

      // Too short a new password is refused here.
      await tester.enterText(
        find.byKey(const Key('security-current-password')),
        'old-password-1',
      );
      await tester.enterText(
        find.byKey(const Key('security-new-password')),
        'short',
      );
      await tester.tap(find.byKey(const Key('security-change-password')));
      await settle(tester);
      expect(find.text('Use at least 10 characters'), findsOneWidget);
      expect(test.workRequests.where((r) => r.method == 'POST'), isEmpty);

      await tester.enterText(
        find.byKey(const Key('security-new-password')),
        'a-much-longer-one',
      );
      await tester.tap(find.byKey(const Key('security-change-password')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {
        'current_password': 'old-password-1',
        'new_password': 'a-much-longer-one',
      });
      expect(
        find.text('Password changed. Your other devices are signed out.'),
        findsOneWidget,
      );
      // The list is asked again: only this phone is left.
      expect(find.text('Chrome on Windows'), findsNothing);
      expect(find.byKey(const Key('security-no-others')), findsOneWidget);
      // Still signed in here: nothing was signed out locally.
      expect(test.authRepository.logouts, 0);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a wrong current password shows under the field', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/sessions': (_) => {'items': []},
        'POST /v1/me/password': (_) => failure(
          400,
          'VALIDATION_FAILED',
          fields: {'current_password': 'is not correct'},
        ),
      });
      await pumpInApp(tester, test, const AccountSecurityScreen());
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('security-current-password')),
        'wrong-one',
      );
      await tester.enterText(
        find.byKey(const Key('security-new-password')),
        'a-much-longer-one',
      );
      await tester.tap(find.byKey(const Key('security-change-password')));
      await settle(tester);
      expect(find.text('Current password is not correct'), findsOneWidget);
    });
  });

  group('signed-in devices', () {
    testWidgets('sign out one, then everywhere else', (tester) async {
      final test = TestServices();
      var items = [
        session('s-1', 'RightProperty365 app on Android', current: true),
        session('s-2', 'Chrome on Windows'),
        session('s-3', 'Safari on macOS'),
      ];
      serve(test, {
        'GET /v1/me/sessions': (_) => {'items': items},
        'DELETE /v1/me/sessions/s-2': (_) {
          items = items.where((s) => s['id'] != 's-2').toList();
          return http.Response('', 204);
        },
        'POST /v1/me/sessions/revoke-others': (_) {
          items = items.where((s) => s['current'] == true).toList();
          return {'revoked': 1};
        },
      });
      await pumpInApp(tester, test, const AccountSecurityScreen());
      await settle(tester);
      expect(find.text('This phone'), findsOneWidget);
      expect(find.textContaining('Last active 21 Nov 2026'), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('security-sign-out-s-2')));
      await settle(tester);
      expect(find.text('Sign out Chrome on Windows?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('security-confirm')));
      await settle(tester);
      expect(find.text('Chrome on Windows is signed out.'), findsOneWidget);
      expect(find.byKey(const Key('security-session-s-2')), findsNothing);

      await tester.tap(find.byKey(const Key('security-sign-out-others')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('security-confirm')));
      await settle(tester);
      expect(
        test.workRequests.last.url.path,
        '/v1/me/sessions',
        reason: 'the list is reloaded',
      );
      expect(find.text('Safari on macOS'), findsNothing);
      expect(find.byKey(const Key('security-no-others')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('this phone signs out through the normal sign-out', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      serve(test, {
        'GET /v1/me/sessions': (_) => {
          'items': [session('s-1', 'Unknown device', current: true)],
        },
      });
      final router = buildRouter();
      await tester.pumpWidget(appWith(test, router));
      await settle(tester);
      router.push(Routes.accountSecurity);
      await settle(tester);
      await tester.tap(find.byKey(const Key('security-sign-out-s-1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('security-confirm')));
      await settle(tester);
      expect(test.authRepository.logouts, 1);
      expect(test.auth.signedIn, isFalse);
      expect(find.byType(AccountSecurityScreen), findsNothing);
      // No DELETE for its own session: logout ends it.
      expect(test.workRequests.where((r) => r.method == 'DELETE'), isEmpty);
    });
  });

  group('the email address', () {
    testWidgets('a link goes to the new address', (tester) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      serve(test, {
        'GET /v1/me/sessions': (_) => {'items': []},
        'POST /v1/me/email': (_) => http.Response('', 202),
      });
      await pumpInApp(tester, test, const AccountSecurityScreen());
      await settle(tester);
      expect(find.text('Now: tendai@example.test'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('security-new-email')),
        ' new@example.test ',
      );
      await tester.enterText(
        find.byKey(const Key('security-email-password')),
        'pw-for-email',
      );
      await tester.ensureVisible(
        find.byKey(const Key('security-change-email')),
      );
      await tester.tap(find.byKey(const Key('security-change-email')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {
        'new_email': 'new@example.test',
        'current_password': 'pw-for-email',
      });
      expect(
        find.text(
          'We sent a link to new@example.test. Open it within 24 hours to '
          'finish the change.',
        ),
        findsOneWidget,
      );
      // Unchanged until the link is opened.
      expect(test.auth.user!.email, 'tendai@example.test');
    });

    testWidgets('the emailed link confirms it and updates the account', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      serve(test, {
        'POST /v1/auth/email-change/confirm': (r) {
          expect(bodyOf(r), {'token': 'tok-1'});
          return {
            'user': {
              'id': testUser.id,
              'name': testUser.name,
              'email': 'new@example.test',
              'email_verified': true,
            },
          };
        },
      });
      await pumpInApp(
        tester,
        test,
        const ConfirmEmailChangeScreen(token: 'tok-1'),
      );
      await settle(tester);
      expect(find.byKey(const Key('email-change-confirmed')), findsOneWidget);
      expect(find.textContaining('new@example.test'), findsOneWidget);
      expect(test.auth.user!.email, 'new@example.test');
    });

    testWidgets('a used link says so', (tester) async {
      final test = TestServices();
      serve(test, {
        'POST /v1/auth/email-change/confirm': (_) =>
            failure(400, 'INVALID_TOKEN'),
      });
      await pumpInApp(
        tester,
        test,
        const ConfirmEmailChangeScreen(token: 'tok-1'),
      );
      await settle(tester);
      expect(
        find.textContaining('expired or was already used'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('email-change-link')), findsOneWidget);
    });
  });

  testWidgets('holds at 200% text', (tester) async {
    final test = TestServices();
    await test.auth.signIn('tendai@example.test', 'pw');
    serve(test, {
      'GET /v1/me/sessions': (_) => {
        'items': [
          session('s-1', 'RightProperty365 app on Android', current: true),
          session('s-2', 'Chrome on Windows'),
        ],
      },
    });
    await pumpInApp(tester, test, const AccountSecurityScreen(), textScale: 2);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('security-sign-out-s-2'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  test('links open the screens', () async {
    final app = TestServices();
    final where = await resolveNotificationLink(
      '/account/security',
      app.services,
    );
    expect((where as InApp).location, Routes.accountSecurity);
    expect(Routes.confirmEmailChange('a b'), '/confirm-email-change?token=a+b');
  });

  test('the app names itself in User-Agent', () async {
    String? agent;
    final api = ApiClient(
      baseUrl: 'http://api',
      httpClient: MockClient((request) async {
        agent = request.headers['User-Agent'];
        return http.Response('{}', 200);
      }),
    )..userAgent = 'RightProperty365/1.0.0 (Android)';
    await api.get('/v1/me/sessions');
    expect(agent, 'RightProperty365/1.0.0 (Android)');
  });
}
