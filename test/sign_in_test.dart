import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/presentation/sign_in_screen.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';

import 'support.dart';

const challengeJson = {
  'status': 'CODE_REQUIRED',
  'challenge_id': 'ch-1',
  'sent_to': 'c•••@example.test',
  'expires_at': '2026-11-15T10:10:00Z',
  'code_length': 6,
};

const sessionJson = {
  'user': {
    'id': 'u',
    'name': 'Casey Seeker',
    'email': 'casey@example.test',
    'email_verified': true,
  },
  'session': {'scope': 'customer', 'expires_at': '2026-12-15T10:00:00Z'},
  'access_token': 'token-xyz',
};

http.Response failure(
  int status,
  String code, {
  Map<String, String>? fields,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': 'raw', 'fields': ?fields},
    'trace_id': 't',
  }),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

const wrongCode = ApiFailure(
  status: 400,
  code: 'VALIDATION_FAILED',
  message: 'Some fields need your attention.',
  fields: {'code': 'That code is not right.'},
);

const expired = ApiFailure(
  status: 400,
  code: 'CODE_EXPIRED',
  message: 'That code has expired or was used too many times. Sign in again.',
);

Future<TestServices> toCodeStep(WidgetTester tester) async {
  final test = TestServices();
  test.authRepository.requireCode = true;
  await pumpInApp(tester, test, const SignInScreen());
  await tester.enterText(
    find.byKey(const Key('sign-in-email')),
    'casey@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('sign-in-password')),
    'correct-horse-battery',
  );
  await tester.tap(find.byKey(const Key('sign-in-submit')));
  await tester.pumpAndSettle();
  return test;
}

void main() {
  group('ApiAuthRepository', () {
    test('the password step returns the challenge, with no session', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(200, challengeJson),
      );

      final step = await ApiAuthRepository(api)
          .login('casey@example.test', 'pw');

      expect(step, isA<CodeRequired>());
      final challenge = (step as CodeRequired).challenge;
      expect(challenge.id, 'ch-1');
      expect(challenge.sentTo, 'c•••@example.test');
      expect(challenge.codeLength, 6);
      expect(challenge.expiresAt, DateTime.utc(2026, 11, 15, 10, 10));
      expect(jsonDecode(requests.single.body)['token_delivery'], 'bearer');
    });

    test(
      'the code step posts the challenge and code and returns the session',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(200, sessionJson),
        );

        final session = await ApiAuthRepository(api)
            .verifySignInCode('ch-1', ' 123456 ');

        expect(session.token, 'token-xyz');
        expect(session.user.name, 'Casey Seeker');
        expect(requests.single.url.path, '/v1/auth/login/verify');
        expect(jsonDecode(requests.single.body), {
          'challenge_id': 'ch-1',
          'code': '123456',
        });
      },
    );

    test(
      'a wrong code keeps the field message; an expired one keeps its code',
      () async {
        final (api: wrong, requests: _) = mockApi(
          (_) async => failure(
            400,
            'VALIDATION_FAILED',
            fields: {'code': 'That code is not right.'},
          ),
        );
        await expectLater(
          ApiAuthRepository(wrong).verifySignInCode('ch-1', '000000'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.fields['code'],
              'code',
              'That code is not right.',
            ),
          ),
        );

        final (api: gone, requests: _) = mockApi(
          (_) async => failure(400, 'CODE_EXPIRED'),
        );
        await expectLater(
          ApiAuthRepository(gone).verifySignInCode('ch-1', '000000'),
          throwsA(
            isA<ApiFailure>().having((f) => f.code, 'code', 'CODE_EXPIRED'),
          ),
        );
      },
    );

    test(
      'resend returns the challenge, and a 429 carries Retry-After',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(200, challengeJson),
        );
        final challenge = await ApiAuthRepository(api).resendSignInCode('ch-1');
        expect(challenge.id, 'ch-1');
        expect(requests.single.url.path, '/v1/auth/login/resend');
        expect(jsonDecode(requests.single.body), {'challenge_id': 'ch-1'});

        final (api: soon, requests: _) = mockApi(
          (_) async =>
              failure(429, 'RATE_LIMITED', headers: {'retry-after': '17'}),
        );
        await expectLater(
          ApiAuthRepository(soon).resendSignInCode('ch-1'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.retryAfter,
              'retryAfter',
              const Duration(seconds: 17),
            ),
          ),
        );
      },
    );
  });

  group('AuthController', () {
    test('the password alone does not sign in or store a token', () async {
      final test = TestServices();
      test.authRepository.requireCode = true;

      final challenge = await test.auth.signIn('casey@example.test', 'pw');

      expect(challenge?.id, 'challenge-1');
      expect(test.auth.signedIn, isFalse);
      expect(test.tokens.token, isNull);
      expect(test.api.bearerToken, isNull);
    });

    test('the code signs in and stores the token', () async {
      final test = TestServices();
      await test.auth.verifyCode('challenge-1', '123456');

      expect(test.auth.signedIn, isTrue);
      expect(test.tokens.token, 'token-from-code');
      expect(test.api.bearerToken, 'token-from-code');
    });
  });

  group('sign-in screen', () {
    testWidgets(
      'after the password it asks for the code sent to the masked address',
      (tester) async {
        final test = await toCodeStep(tester);

        expect(find.text('Check your email'), findsOneWidget);
        expect(find.textContaining('t•••@example.test'), findsOneWidget);
        expect(find.byKey(const Key('sign-in-code')), findsOneWidget);
        expect(test.auth.signedIn, isFalse);
      },
    );

    testWidgets('a full code signs in without tapping the button', (
      tester,
    ) async {
      final test = await toCodeStep(tester);

      await tester.enterText(find.byKey(const Key('sign-in-code')), '123456');
      await tester.pumpAndSettle();

      expect(test.authRepository.verifiedCode, '123456');
      expect(test.auth.signedIn, isTrue);
    });

    testWidgets('a shorter demo code is accepted from the button', (
      tester,
    ) async {
      final test = await toCodeStep(tester);

      await tester.enterText(find.byKey(const Key('sign-in-code')), '1234');
      await tester.pump();
      expect(test.authRepository.verifiedCode, isNull); // not auto-sent
      await tester.tap(find.byKey(const Key('sign-in-verify')));
      await tester.pumpAndSettle();

      expect(test.authRepository.verifiedCode, '1234');
      expect(test.auth.signedIn, isTrue);
    });

    testWidgets('fewer than 4 digits is not sent', (tester) async {
      final test = await toCodeStep(tester);

      await tester.enterText(find.byKey(const Key('sign-in-code')), '12');
      await tester.tap(find.byKey(const Key('sign-in-verify')));
      await tester.pumpAndSettle();

      expect(find.text('Enter the code we sent you.'), findsOneWidget);
      expect(test.authRepository.verifiedCode, isNull);
    });

    testWidgets('only digits can be typed', (tester) async {
      await toCodeStep(tester);
      await tester.enterText(find.byKey(const Key('sign-in-code')), '1a2b');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sign-in-code')))
            .controller!
            .text,
        '12',
      );
    });

    testWidgets('a wrong code shows the API message and clears the field', (
      tester,
    ) async {
      final test = await toCodeStep(tester);
      test.authRepository.verifyFailure = wrongCode;

      await tester.enterText(find.byKey(const Key('sign-in-code')), '000000');
      await tester.pumpAndSettle();

      expect(find.text('That code is not right.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sign-in-code')))
            .controller!
            .text,
        isEmpty,
      );
      expect(test.auth.signedIn, isFalse);
    });

    testWidgets('an expired code goes back to the password with the reason', (
      tester,
    ) async {
      final test = await toCodeStep(tester);
      test.authRepository.verifyFailure = expired;

      await tester.enterText(find.byKey(const Key('sign-in-code')), '123456');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sign-in-password')), findsOneWidget);
      expect(find.textContaining('Sign in again.'), findsOneWidget);
      // The email is kept; the password is not.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sign-in-email')))
            .controller!
            .text,
        'casey@example.test',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sign-in-password')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('a new code can be asked for after 30 seconds', (tester) async {
      final test = await toCodeStep(tester);
      TextButton resend() =>
          tester.widget<TextButton>(find.byKey(const Key('sign-in-resend')));

      expect(resend().onPressed, isNull);
      expect(find.textContaining('Send a new code in'), findsOneWidget);

      await tester.pump(const Duration(seconds: 31));
      expect(resend().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('sign-in-resend')));
      await tester.pumpAndSettle();

      expect(test.authRepository.resends, 1);
      expect(find.textContaining('We sent a new code'), findsOneWidget);
      expect(resend().onPressed, isNull); // waiting again
    });

    testWidgets('a resend that comes too soon waits as long as the API says', (
      tester,
    ) async {
      final test = await toCodeStep(tester);
      test.authRepository.resendFailure = const ApiFailure(
        status: 429,
        code: 'RATE_LIMITED',
        message: 'raw',
        retryAfter: Duration(seconds: 45),
      );
      await tester.pump(const Duration(seconds: 31));

      await tester.tap(find.byKey(const Key('sign-in-resend')));
      await tester.pump();

      expect(
        find.textContaining('You can ask for a new code in 45 seconds'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('sign-in-resend')))
            .onPressed,
        isNull,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a different account can be used', (tester) async {
      await toCodeStep(tester);

      await tester.tap(find.byKey(const Key('sign-in-restart')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sign-in-password')), findsOneWidget);
      expect(find.byKey(const Key('sign-in-code')), findsNothing);
    });

    testWidgets('a server that signs in without a code still works', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(tester, test, const SignInScreen());
      await tester.enterText(
        find.byKey(const Key('sign-in-email')),
        'casey@example.test',
      );
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'pw');
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pumpAndSettle();

      expect(test.auth.signedIn, isTrue);
      expect(find.byKey(const Key('sign-in-code')), findsNothing);
    });

    testWidgets('the code step holds at 200% text size', (tester) async {
      final test = TestServices();
      test.authRepository.requireCode = true;
      await pumpInApp(
        tester,
        test,
        const SignInScreen(),
        textScale: 2,
        size: const Size(390, 3000),
      );
      await tester.enterText(
        find.byKey(const Key('sign-in-email')),
        'casey@example.test',
      );
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'pw');
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  test(
    'the inbox asks for the largest page and shows the lead stage',
    () async {
      final (:api, :requests) = mockApi(
        (request) async => request.url.path.contains('agent')
            ? jsonResponse(200, {
                'items': [
                  {
                    'request_id': 'r',
                    'reference': 'RP-8VXWDQJG',
                    'listing_id': 'l',
                    'listing': null,
                    'request_type': 'ENQUIRY',
                    'status': 'RECEIVED',
                    'stage': 'FOLLOW_UP_REQUIRED',
                    'stage_label': 'Follow-up required',
                    'stage_changed_at': null,
                    'message': 'Hi',
                    'preferred_contact_method': 'EMAIL',
                    'contact': {
                      'name': 'A',
                      'email': 'a@example.test',
                      'phone': null,
                    },
                    'created_at': '2026-11-15T09:00:00Z',
                  },
                ],
                'page': 1,
                'page_size': 100,
                'total': 1,
                'total_pages': 1,
                'stage_counts': [],
              })
            : jsonResponse(200, {'items': []}),
      );

      final enquiries = await ApiInboxRepository(api).received();

      final listingCall = requests.firstWhere(
        (r) => r.url.path == '/v1/agent/property-requests',
      );
      expect(listingCall.url.queryParameters['page_size'], '100');
      expect(enquiries.single.statusLabel, 'Follow-up required');
    },
  );
}
