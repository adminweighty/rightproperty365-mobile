import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/terminology.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/presentation/register_screen.dart';

import 'support.dart';

Future<TestServices> pumpRegister(
  WidgetTester tester, [
  TestServices? services,
]) async {
  final test = services ?? TestServices();
  await pumpInApp(
    tester,
    test,
    const RegisterScreen(),
    size: const Size(390, 6000),
  );
  await tester.pumpAndSettle();
  return test;
}

Future<void> fillDetails(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('register-name')), 'New Person');
  await tester.enterText(
    find.byKey(const Key('register-email')),
    'new@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('register-password')),
    'correct-horse-battery',
  );
}

Future<void> choose(WidgetTester tester, String side) async {
  await tester.tap(find.byKey(Key('side-$side')));
  await tester.pumpAndSettle();
}

Future<void> answerAndSubmit(
  WidgetTester tester, {
  String answer = '12',
}) async {
  await tester.enterText(find.byKey(const Key('register-captcha')), answer);
  await tester.tap(find.byKey(const Key('register-consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('register-submit')));
  await tester.pumpAndSettle();
}

bool ticked(WidgetTester tester, String code) =>
    tester.widget<CheckboxListTile>(find.byKey(Key('role-$code'))).value ??
    false;

void main() {
  group('ApiAuthRepository', () {
    test('asks for a captcha question', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(200, {
          'captcha_id': 'abc',
          'question': 'What is 7 + 5?',
          'expires_at': '2026-11-14T10:10:00Z',
        }),
      );

      final captcha = await ApiAuthRepository(api).captcha();

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/auth/captcha');
      expect(captcha.id, 'abc');
      expect(captcha.question, 'What is 7 + 5?');
      expect(captcha.expiresAt, DateTime.utc(2026, 11, 14, 10, 10));
    });

    test(
      'register posts roles, consent and the captcha answer as a string',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(202, {'status': 'VERIFICATION_SENT'}),
        );

        await ApiAuthRepository(api).register(
          name: ' New Person ',
          email: 'new@example.test',
          password: 'correct-horse-battery',
          roles: ['CONSUMER', 'TENANT'],
          consentAccepted: true,
          privacyVersion: 'v1',
          captchaId: 'abc',
          captchaAnswer: ' 12 ',
        );

        expect(requests.single.url.path, '/v1/auth/register');
        expect(jsonDecode(requests.single.body), {
          'name': 'New Person',
          'email': 'new@example.test',
          'password': 'correct-horse-battery',
          'roles': ['CONSUMER', 'TENANT'],
          'captcha': {'captcha_id': 'abc', 'answer': '12'},
          'consent': {'privacy_version': 'v1', 'accepted': true},
        });
      },
    );

    test(
      'a role is a seeker role when the API says it needs no verification',
      () {
        expect(const SelectableRole('CONSUMER', 'x').seeker, isTrue);
        expect(const SelectableRole('AGENT', 'x').seeker, isFalse);
        expect(
          const SelectableRole('NEW_SEEKER', 'x', null, false).seeker,
          isTrue,
        );
        expect(
          const SelectableRole('CONSUMER', 'x', null, true).seeker,
          isFalse,
        );
      },
    );
  });

  group('seeker or professional', () {
    testWidgets('no roles are shown until one side is chosen', (tester) async {
      await pumpRegister(tester);

      expect(find.text('I am looking for a property'), findsOneWidget);
      expect(
        find.text('I work in property, or I own property to sell or let'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('role-CONSUMER')), findsNothing);
      expect(find.byKey(const Key('role-AGENT')), findsNothing);
    });

    testWidgets('the seeker side offers only Property Seeker roles', (
      tester,
    ) async {
      await pumpRegister(tester);
      await choose(tester, 'seeker');

      expect(find.text('Prospective Buyer'), findsOneWidget);
      expect(find.text('Prospective Tenant'), findsOneWidget);
      expect(ticked(tester, 'CONSUMER'), isTrue);
      expect(find.byKey(const Key('role-AGENT')), findsNothing);
      expect(find.byKey(const Key('role-LANDLORD')), findsNothing);
      expect(find.byKey(const Key('role-search')), findsNothing);
    });

    testWidgets('the professional side offers every other role, grouped', (
      tester,
    ) async {
      await pumpRegister(tester);
      await choose(tester, 'professional');

      for (final label in [
        'Real Estate Professionals',
        'Estate Agent',
        'Sales Agent',
        'Lettings Agent',
        'Property Manager',
        'Solicitor',
        'Real Estate Businesses',
        'Agency Principal',
        'Agency Administrator',
        'Property Owners',
        'Landlord',
        'Property Seller (Vendor)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byKey(const Key('role-CONSUMER')), findsNothing);
      expect(find.byKey(const Key('role-TENANT')), findsNothing);
      expect(find.text('Property Seekers'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching sides drops the roles already ticked', (
      tester,
    ) async {
      final test = await pumpRegister(tester);
      await fillDetails(tester);
      await choose(tester, 'professional');
      await tester.tap(find.byKey(const Key('role-LANDLORD')));
      await tester.tap(find.byKey(const Key('role-SOLICITOR')));
      await tester.pump();

      await choose(tester, 'seeker');
      await tester.tap(find.byKey(const Key('role-TENANT')));
      await tester.pump();
      await answerAndSubmit(tester);

      expect(test.authRepository.registered?['roles'], ['CONSUMER', 'TENANT']);
    });

    testWidgets('a professional registration sends only professional roles', (
      tester,
    ) async {
      final test = await pumpRegister(tester);
      await fillDetails(tester);
      await choose(tester, 'professional');
      await tester.tap(find.byKey(const Key('role-SOLICITOR')));
      await tester.tap(find.byKey(const Key('role-LANDLORD')));
      await tester.pump();
      await answerAndSubmit(tester);

      expect(test.authRepository.registered?['roles'], [
        'SOLICITOR',
        'LANDLORD',
      ]);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('account has been created'), findsNothing);
    });

    testWidgets('nothing is sent until a side and a role are chosen', (
      tester,
    ) async {
      final test = await pumpRegister(tester);
      await fillDetails(tester);
      await answerAndSubmit(tester);
      expect(find.text('Choose one to continue'), findsOneWidget);

      await choose(tester, 'professional');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose at least one'), findsOneWidget);
      expect(test.authRepository.registrations, 0);
    });

    testWidgets('the role list filters as you type and keeps ticks', (
      tester,
    ) async {
      await pumpRegister(tester);
      await choose(tester, 'professional');
      await tester.tap(find.byKey(const Key('role-LANDLORD')));
      await tester.pump();

      await tester.enterText(find.byKey(const Key('role-search')), 'solic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role-SOLICITOR')), findsOneWidget);
      expect(find.byKey(const Key('role-LANDLORD')), findsNothing);
      expect(find.text('Real Estate Professionals'), findsOneWidget);
      expect(find.text('Property Owners'), findsNothing);

      await tester.enterText(find.byKey(const Key('role-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('role-search')), '');
      await tester.pumpAndSettle();
      expect(ticked(tester, 'LANDLORD'), isTrue);
    });

    testWidgets('a role the API has switched off is not offered', (
      tester,
    ) async {
      final test = TestServices();
      test.authRepository.selectable = builtInRoles
          .where((r) => r.code != 'SOLICITOR')
          .toList();
      await pumpRegister(tester, test);
      await choose(tester, 'professional');

      expect(find.text('Solicitor'), findsNothing);
      expect(find.text('Estate Agent'), findsOneWidget);
    });

    testWidgets(
      'the built-in roles are used when the role list cannot be loaded',
      (tester) async {
        final test = TestServices();
        test.authRepository.selectable = null;
        await pumpRegister(tester, test);
        await choose(tester, 'professional');

        expect(find.text('Property Manager'), findsOneWidget);
      },
    );
  });

  group('captcha', () {
    testWidgets('the question is shown and its answer is sent with its id', (
      tester,
    ) async {
      final test = await pumpRegister(tester);
      expect(find.text('What is 7 + 5?'), findsOneWidget);

      await fillDetails(tester);
      await choose(tester, 'seeker');
      await answerAndSubmit(tester, answer: '12');

      expect(test.authRepository.registered?['captcha_id'], 'captcha-1');
      expect(test.authRepository.registered?['captcha_answer'], '12');
    });

    testWidgets('only digits can be typed', (tester) async {
      await pumpRegister(tester);
      await tester.enterText(find.byKey(const Key('register-captcha')), '1a2 ');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('register-captcha')))
            .controller!
            .text,
        '12',
      );
    });

    testWidgets('an unanswered question blocks the registration', (
      tester,
    ) async {
      final test = await pumpRegister(tester);
      await fillDetails(tester);
      await choose(tester, 'seeker');
      await answerAndSubmit(tester, answer: '');

      expect(find.text('Answer the question'), findsOneWidget);
      expect(test.authRepository.registrations, 0);
    });

    testWidgets(
      'a wrong answer shows the API message, a new question and an empty field',
      (tester) async {
        final test = TestServices();
        test.authRepository.registerFailure = const ApiFailure(
          status: 400,
          code: 'VALIDATION_FAILED',
          message: 'Some fields need your attention.',
          fields: {
            'captcha': 'That answer is not right. Try the new question.',
          },
        );
        await pumpRegister(tester, test);
        await fillDetails(tester);
        await choose(tester, 'seeker');
        test.authRepository.captchaQuestion = 'What is 9 - 4?';
        await answerAndSubmit(tester, answer: '99');

        expect(
          find.text('That answer is not right. Try the new question.'),
          findsOneWidget,
        );
        expect(find.text('What is 9 - 4?'), findsOneWidget);
        expect(find.text('What is 7 + 5?'), findsNothing);
        expect(test.authRepository.captchasAsked, 2);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('register-captcha')))
              .controller!
              .text,
          isEmpty,
        );
        // What was typed elsewhere is kept.
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('register-name')))
              .controller!
              .text,
          'New Person',
        );

        // The second attempt uses the new question's id.
        test.authRepository.registerFailure = null;
        await tester.enterText(find.byKey(const Key('register-captcha')), '5');
        await tester.tap(find.byKey(const Key('register-submit')));
        await tester.pumpAndSettle();
        expect(test.authRepository.registered?['captcha_id'], 'captcha-2');
      },
    );

    testWidgets('any refused registration gets a new question', (tester) async {
      final test = TestServices();
      test.authRepository.registerFailure = const ApiFailure(
        status: 400,
        code: 'VALIDATION_FAILED',
        message: 'Some fields need your attention.',
        fields: {
          'roles': 'Choose Property Seeker roles or other roles, not both.',
        },
      );
      await pumpRegister(tester, test);
      await fillDetails(tester);
      await choose(tester, 'seeker');
      await answerAndSubmit(tester);

      expect(
        find.text('Choose Property Seeker roles or other roles, not both.'),
        findsOneWidget,
      );
      expect(test.authRepository.captchasAsked, 2);
    });

    testWidgets('the refresh button asks a different question', (tester) async {
      final test = await pumpRegister(tester);
      test.authRepository.captchaQuestion = 'What is 3 + 4?';

      await tester.tap(find.byKey(const Key('register-captcha-new')));
      await tester.pumpAndSettle();

      expect(find.text('What is 3 + 4?'), findsOneWidget);
      expect(test.authRepository.captchasAsked, 2);
    });

    testWidgets('an expired question is replaced', (tester) async {
      final test = await pumpRegister(tester);
      test.authRepository.captchaQuestion = 'What is 2 + 2?';

      await tester.pump(const Duration(minutes: 10, seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('What is 2 + 2?'), findsOneWidget);
      expect(test.authRepository.captchasAsked, 2);
    });

    testWidgets(
      'if the question cannot be loaded, it says why and offers a retry',
      (tester) async {
        final test = TestServices();
        test.authRepository.captchaQuestion = null;
        await pumpRegister(tester, test);

        expect(
          find.textContaining('the account cannot be created yet'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('register-submit')))
              .onPressed,
          isNull,
        );

        test.authRepository.captchaQuestion = 'What is 1 + 1?';
        await tester.tap(find.byKey(const Key('register-captcha-retry')));
        await tester.pumpAndSettle();

        expect(find.text('What is 1 + 1?'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('register-submit')))
              .onPressed,
          isNotNull,
        );
      },
    );
  });

  testWidgets('holds at 200% text size', (tester) async {
    final test = TestServices();
    await pumpInApp(
      tester,
      test,
      const RegisterScreen(),
      textScale: 2,
      size: const Size(390, 12000),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'professional');
    expect(tester.takeException(), isNull);
  });
}
