import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/activity/activity_screen.dart';
import 'package:rightproperty365/features/activity/activity_store.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/presentation/recovery_screens.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/directory/presentation/profile_screen.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';

import 'support.dart';

const link = 'http://localhost:3000/verify-email?token=abc_DEF-1';

void main() {
  group('extractEmailToken', () {
    test('reads the token from a pasted link or a bare token', () {
      expect(extractEmailToken(link), 'abc_DEF-1');
      expect(
        extractEmailToken(
          '  https://rightproperty365.com/reset-password?token=xyz%2B1  ',
        ),
        'xyz+1',
      );
      expect(
        extractEmailToken('rightproperty365://app/verify-email?token=t0k'),
        't0k',
      );
      expect(extractEmailToken('abc_DEF-1'), 'abc_DEF-1');
    });

    test('rejects text with no token', () {
      expect(extractEmailToken(''), isNull);
      expect(extractEmailToken('   '), isNull);
      expect(
        extractEmailToken('https://rightproperty365.com/verify-email'),
        isNull,
      );
      expect(
        extractEmailToken('https://rightproperty365.com/verify-email?token='),
        isNull,
      );
      expect(extractEmailToken('please confirm my email'), isNull);
    });
  });

  group('ApiAuthRepository links', () {
    test('verify-email asks for a bearer session', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(200, {
          'user': {
            'id': 'u',
            'name': 'New Person',
            'email': 'new@example.test',
            'email_verified': true,
          },
          'session': {
            'scope': 'customer',
            'expires_at': '2026-12-13T09:00:00Z',
          },
          'access_token': 'token-new',
        }),
      );

      final session = await ApiAuthRepository(api).verifyEmail('abc');

      expect(session.token, 'token-new');
      expect(requests.single.url.path, '/v1/auth/verify-email');
      expect(jsonDecode(requests.single.body), {
        'token': 'abc',
        'token_delivery': 'bearer',
      });
    });

    test('an expired or used link is explained plainly', () async {
      final (:api, requests: _) = mockApi(
        (_) async => jsonResponse(400, {
          'error': {'code': 'INVALID_TOKEN', 'message': 'raw'},
          'trace_id': 't',
        }),
      );
      final repository = ApiAuthRepository(api);
      final expired = isA<ApiFailure>()
          .having((f) => f.code, 'code', 'INVALID_TOKEN')
          .having((f) => f.message, 'message', contains('not valid any more'));

      await expectLater(repository.verifyEmail('old'), throwsA(expired));
      await expectLater(
        repository.confirmPasswordReset('old', 'correct-horse-battery'),
        throwsA(expired),
      );
    });

    test(
      'resend, reset request and reset confirm post the documented bodies',
      () async {
        final (:api, :requests) = mockApi(
          (request) async => request.url.path.endsWith('confirm')
              ? jsonResponse(204, const {})
              : jsonResponse(202, {'status': 'ok'}),
        );
        final repository = ApiAuthRepository(api);

        await repository.resendVerification(' a@b.co ');
        await repository.requestPasswordReset(' a@b.co ');
        await repository.confirmPasswordReset('tok', 'correct-horse-battery');

        expect(requests.map((r) => r.url.path), [
          '/v1/auth/resend-verification',
          '/v1/auth/password-reset/request',
          '/v1/auth/password-reset/confirm',
        ]);
        expect(jsonDecode(requests[0].body), {'email': 'a@b.co'});
        expect(jsonDecode(requests[1].body), {'email': 'a@b.co'});
        expect(jsonDecode(requests[2].body), {
          'token': 'tok',
          'password': 'correct-horse-battery',
        });
      },
    );
  });

  group('AuthController links', () {
    test('confirming an email signs in and stores the token', () async {
      final test = TestServices();
      await test.auth.confirmEmail('abc');
      expect(test.auth.signedIn, isTrue);
      expect(test.tokens.token, 'token-verified');
      expect(test.api.bearerToken, 'token-verified');
    });

    test('a password reset signs this device out, because every session is revoked', () async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');

      await test.auth.resetPassword('tok', 'correct-horse-battery');

      expect(test.authRepository.passwordReset?.token, 'tok');
      expect(test.auth.signedIn, isFalse);
      expect(test.tokens.token, isNull);
      expect(test.api.bearerToken, isNull);
    });
  });

  group('routes', () {
    test('email link paths carry the token', () {
      expect(Routes.verifyEmail(), '/verify-email');
      expect(Routes.verifyEmail('a b'), '/verify-email?token=a+b');
      expect(Routes.resetPassword('abc'), '/reset-password?token=abc');
    });

    testWidgets('an email link opened on the phone confirms the address', (
      tester,
    ) async {
      final test = TestServices();
      final router = buildRouter();
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(appWith(test, router));
      await tester.pumpAndSettle();

      // What Android or iOS hands the app for
      // https://rightproperty365.com/verify-email?token=abc_DEF-1
      router.go('/verify-email?token=abc_DEF-1');
      await tester.pumpAndSettle();

      expect(test.authRepository.verifiedToken, 'abc_DEF-1');
      expect(find.text('Email confirmed'), findsOneWidget);
      expect(test.auth.signedIn, isTrue);
    });
  });

  group('confirm email screen', () {
    testWidgets('a pasted link confirms the address', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const VerifyEmailScreen());

      await tester.enterText(find.byKey(const Key('verify-link')), link);
      await tester.tap(find.byKey(const Key('verify-submit')));
      await tester.pumpAndSettle();

      expect(test.authRepository.verifiedToken, 'abc_DEF-1');
      expect(find.text('Email confirmed'), findsOneWidget);
    });

    testWidgets('text that is not a link is rejected before calling the API', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(tester, test, const VerifyEmailScreen());

      await tester.enterText(
        find.byKey(const Key('verify-link')),
        'not a link',
      );
      await tester.tap(find.byKey(const Key('verify-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Paste the whole link from the email'), findsOneWidget);
      expect(test.authRepository.verifiedToken, isNull);
    });

    testWidgets('an expired link shows why and offers to send a new one', (
      tester,
    ) async {
      final test = TestServices();
      test.authRepository.linkFailure = const ApiFailure(
        status: 400,
        code: 'INVALID_TOKEN',
        message: 'That link is not valid any more.',
      );
      await pumpInApp(tester, test, const VerifyEmailScreen(token: 'old'));
      await tester.pumpAndSettle();

      expect(find.text('That link is not valid any more.'), findsOneWidget);
      expect(find.text('Email confirmed'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('resend-email')),
        'new@example.test',
      );
      await tester.tap(find.byKey(const Key('resend-submit')));
      await tester.pumpAndSettle();

      expect(test.authRepository.resentTo, 'new@example.test');
      // Must not reveal whether the address has an account.
      expect(
        find.textContaining('If new@example.test has an account'),
        findsOneWidget,
      );
    });
  });

  group('password reset screens', () {
    testWidgets(
      'forgot password asks for the email without revealing if it exists',
      (tester) async {
        final test = TestServices();
        await pumpInApp(tester, test, const ForgotPasswordScreen());

        await tester.enterText(
          find.byKey(const Key('forgot-email')),
          'someone@example.test',
        );
        await tester.tap(find.byKey(const Key('forgot-submit')));
        await tester.pumpAndSettle();

        expect(test.authRepository.resetRequestedFor, 'someone@example.test');
        expect(find.text('Check your email'), findsOneWidget);
        expect(
          find.textContaining('If someone@example.test has an account'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a reset link sets the new password', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const ResetPasswordScreen(token: 'tok-1'));

      expect(find.byKey(const Key('reset-link')), findsNothing);
      await tester.enterText(find.byKey(const Key('reset-password')), 'short');
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 10 characters'), findsOneWidget);
      expect(test.authRepository.passwordReset, isNull);

      await tester.enterText(
        find.byKey(const Key('reset-password')),
        'correct-horse-battery',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      expect(test.authRepository.passwordReset, (
        token: 'tok-1',
        password: 'correct-horse-battery',
      ));
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('without a token the link is pasted', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const ResetPasswordScreen());

      await tester.enterText(
        find.byKey(const Key('reset-link')),
        'http://localhost:3000/reset-password?token=pasted',
      );
      await tester.enterText(
        find.byKey(const Key('reset-password')),
        'correct-horse-battery',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      expect(test.authRepository.passwordReset?.token, 'pasted');
    });
  });

  group('ActivityStore', () {
    test(
      'saves and unsaves listings, newest first, and persists them',
      () async {
        final storage = MemoryStore();
        final store = ActivityStore(storage);

        await store.toggleSaved('a');
        await store.toggleSaved('b');
        expect(store.savedSlugs, ['b', 'a']);
        await store.toggleSaved('a');
        expect(store.isSaved('a'), isFalse);

        expect(ActivityStore(storage).savedSlugs, ['b']);
      },
    );

    test('records requests newest first, once per reference, without contact details', () async {
      final storage = MemoryStore();
      final store = ActivityStore(storage);

      await store.recordRequest(
        receipt: testReceipt,
        title: 'Home',
        recipient: 'Sample Estates',
        route: '/listings/x',
      );
      await store.recordRequest(
        receipt: testReceipt,
        title: 'Home',
        recipient: 'Sample Estates',
        route: '/listings/x',
      );

      final reloaded = ActivityStore(storage);
      expect(reloaded.requests, hasLength(1));
      expect(reloaded.requests.single.reference, 'RP-8VXWDQJG');
      expect(reloaded.requests.single.status, 'RECEIVED');
      expect(reloaded.requests.single.sentAt, testReceipt.createdAt);
      expect(storage.values.values.join(), isNot(contains('@')));

      await reloaded.clearRequests();
      expect(ActivityStore(storage).requests, isEmpty);
    });

    test('unreadable stored data is treated as empty', () {
      final storage = MemoryStore()
        ..values['activity.sent_requests'] = '{not json';
      expect(ActivityStore(storage).requests, isEmpty);
    });
  });

  group('Activity screen', () {
    testWidgets('explains itself when empty', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const ActivityScreen());
      await tester.pumpAndSettle();

      expect(find.text('No enquiries yet'), findsOneWidget);
    });

    testWidgets(
      'a sent listing request appears with its reference and "Received"',
      (tester) async {
        final test = TestServices();
        final listing = sampleListings().listings.first;
        await pumpInApp(
          tester,
          test,
          Scaffold(
            body: SingleChildScrollView(
              child: PropertyRequestForm(listing: listing),
            ),
          ),
        );
        await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
        await tester.enterText(
          find.byKey(const Key('email')),
          'test@example.com',
        );
        await tester.tap(find.byKey(const Key('consent')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();

        final request = test.activity.requests.single;
        expect(request.title, listing.title);
        expect(request.recipient, 'Sample Estates');
        expect(request.route, contains(listing.slug));

        await pumpInApp(tester, test, const ActivityScreen());
        await tester.pumpAndSettle();

        expect(find.text(listing.title), findsOneWidget);
        expect(find.text('RP-8VXWDQJG'), findsOneWidget);
        expect(find.text('New Enquiry'), findsOneWidget);
        expect(find.textContaining('Delivered'), findsNothing);
        expect(find.textContaining('test@example.com'), findsNothing);
      },
    );

    testWidgets('a directory enquiry is recorded too', (tester) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const ProfileEnquiryScreen(
          kind: DirectoryKind.serviceProviders,
          slug: 'sample-plumbers',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
      await tester.enterText(
        find.byKey(const Key('email')),
        'test@example.com',
      );
      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      final request = test.activity.requests.single;
      expect(request.recipient, 'Sample Plumbers');
      expect(request.route, '/profiles/service-providers/sample-plumbers');
    });

    testWidgets('a failed request is not recorded', (tester) async {
      final test = TestServices();
      test.propertyRequests.failure = const ApiFailure.network();
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: SingleChildScrollView(
            child: PropertyRequestForm(
              listing: sampleListings().listings.first,
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
      await tester.enterText(
        find.byKey(const Key('email')),
        'test@example.com',
      );
      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(test.activity.requests, isEmpty);
    });
  });
}
