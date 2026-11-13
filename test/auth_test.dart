import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/auth/auth_controller.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/data/token_store.dart';

import 'support.dart';

const userJson = {
  'id': 'user-1',
  'name': 'Tendai Ncube',
  'email': 'tendai@example.test',
  'email_verified': true,
  'platform_roles': [],
  'memberships': [
    {
      'organisation_id': '0195c0de-0000-7000-8000-00000000b001',
      'organisation_name': 'Sample Estates',
      'organisation_kind': 'AGENCY',
      'market_code': 'ZW',
      'role': 'AGENT',
    },
  ],
  'account_roles': [
    {'role': 'CONSUMER', 'status': 'ACTIVE'},
    {'role': 'AGENT', 'status': 'PENDING_VERIFICATION'},
  ],
};

http.Response error(int status, String code) => jsonResponse(status, {
  'error': {'code': code, 'message': 'raw'},
  'trace_id': 'trace-1',
});

void main() {
  group('ApiAuthRepository', () {
    test(
      'login asks for a bearer token and returns the user with it',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(200, {
            'user': userJson,
            'session': {
              'scope': 'customer',
              'expires_at': '2026-12-13T09:00:00Z',
            },
            'access_token': 'token-abc',
          }),
        );

        final session = await ApiAuthRepository(api)
            .login(' tendai@example.test ', 'pw');

        expect(session.token, 'token-abc');
        expect(session.user.name, 'Tendai Ncube');
        expect(
          session.user.memberships.single.organisationName,
          'Sample Estates',
        );
        expect(session.user.accountRoles.last.pending, isTrue);
        final sent = requests.single;
        expect(sent.url.path, '/v1/auth/login');
        expect(jsonDecode(sent.body), {
          'email': 'tendai@example.test',
          'password': 'pw',
          'token_delivery': 'bearer',
        });
      },
    );

    test('wrong credentials and unverified email get plain messages', () async {
      final (api: wrong, requests: _) = mockApi(
        (_) async => error(401, 'INVALID_CREDENTIALS'),
      );
      await expectLater(
        ApiAuthRepository(wrong).login('a@b.co', 'x'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            'That email and password do not match an account.',
          ),
        ),
      );

      final (api: unverified, requests: _) = mockApi(
        (_) async => error(403, 'EMAIL_NOT_VERIFIED'),
      );
      await expectLater(
        ApiAuthRepository(unverified).login('a@b.co', 'x'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('Confirm your email'),
          ),
        ),
      );
    });

    test(
      'a 200 without a session is refused rather than treated as signed in',
      () async {
        final (:api, requests: _) = mockApi(
          (_) async => jsonResponse(200, {'user': userJson}),
        );
        await expectLater(
          ApiAuthRepository(api).login('admin@example.test', 'x'),
          throwsA(
            isA<ApiFailure>().having((f) => f.code, 'code', 'NO_SESSION'),
          ),
        );
      },
    );

    test('me sends the bearer token', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(200, {'user': userJson}),
      );
      api.bearerToken = 'token-abc';

      final user = await ApiAuthRepository(api).me();

      expect(user.email, 'tendai@example.test');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/me');
      expect(requests.single.headers['Authorization'], 'Bearer token-abc');
    });

    test('register posts the chosen roles and consent', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(202, {'status': 'VERIFICATION_SENT'}),
      );

      await ApiAuthRepository(api).register(
        name: ' New Person ',
        email: 'new@example.test',
        password: 'correct-horse-battery',
        roles: ['CONSUMER', 'LANDLORD'],
        consentAccepted: true,
        privacyVersion: 'v1',
      );

      expect(requests.single.url.path, '/v1/auth/register');
      expect(jsonDecode(requests.single.body), {
        'name': 'New Person',
        'email': 'new@example.test',
        'password': 'correct-horse-battery',
        'roles': ['CONSUMER', 'LANDLORD'],
        'consent': {'privacy_version': 'v1', 'accepted': true},
      });
    });

    test('logout accepts 204 with an empty body', () async {
      final (:api, :requests) = mockApi((_) async => http.Response('', 204));
      await ApiAuthRepository(api).logout();
      expect(requests.single.url.path, '/v1/auth/logout');
    });
  });

  test('no sign-up role is a platform administrator role', () {
    final offered = accountRoleGroups
        .expand((g) => g.roles)
        .map((r) => r.value)
        .toSet();
    const platform = {
      'SUPER_ADMIN',
      'PLATFORM_ADMIN',
      'MARKET_ADMIN',
      'FINANCE_ADMIN',
      'CONTENT_ADMIN',
      'MODERATOR',
      'SUPPORT',
    };
    expect(offered.intersection(platform), isEmpty);
    expect(offered, contains('CONSUMER'));
    expect(roleLabel('AGENCY_OWNER'), 'Agency owner');
    expect(roleLabel('SOMETHING_NEW'), 'Something new');
  });

  group('AuthController', () {
    ({
      AuthController auth,
      FakeAuthRepository repository,
      MemoryTokenStore tokens,
      ApiClient api,
    })
    build({String? savedToken}) {
      final repository = FakeAuthRepository();
      final tokens = MemoryTokenStore(savedToken);
      final api = ApiClient(baseUrl: 'http://api.test');
      return (
        auth: AuthController(repository: repository, tokens: tokens, api: api),
        repository: repository,
        tokens: tokens,
        api: api,
      );
    }

    test(
      'sign-in stores the token securely and sets it on the API client',
      () async {
        final (:auth, repository: _, :tokens, :api) = build();
        var notified = 0;
        auth.addListener(() => notified++);

        await auth.signIn('tendai@example.test', 'pw');

        expect(auth.signedIn, isTrue);
        expect(auth.user?.name, 'Tendai Ncube');
        expect(tokens.token, 'token-abc');
        expect(api.bearerToken, 'token-abc');
        expect(notified, 1);
      },
    );

    test('a failed sign-in stores nothing', () async {
      final (:auth, :repository, :tokens, :api) = build();
      repository.loginFailure = const ApiFailure(
        status: 401,
        code: 'INVALID_CREDENTIALS',
        message: 'no',
      );

      await expectLater(auth.signIn('a@b.co', 'x'), throwsA(isA<ApiFailure>()));

      expect(auth.signedIn, isFalse);
      expect(tokens.token, isNull);
      expect(api.bearerToken, isNull);
    });

    test('restore signs in from a saved token', () async {
      final (:auth, repository: _, tokens: _, :api) = build(
        savedToken: 'saved',
      );
      await auth.restore();
      expect(auth.signedIn, isTrue);
      expect(api.bearerToken, 'saved');
    });

    test('restore forgets a token the API rejects', () async {
      final (:auth, :repository, :tokens, :api) = build(savedToken: 'expired');
      repository.meFailure = const ApiFailure(
        status: 401,
        code: 'UNAUTHENTICATED',
        message: 'no',
      );

      await auth.restore();

      expect(auth.signedIn, isFalse);
      expect(tokens.token, isNull);
      expect(api.bearerToken, isNull);
    });

    test('restore keeps the token when the API cannot be reached', () async {
      final (:auth, :repository, :tokens, api: _) = build(savedToken: 'saved');
      repository.meFailure = const ApiFailure.network();

      await auth.restore();

      expect(auth.signedIn, isFalse);
      expect(tokens.token, 'saved');
    });

    test(
      'sign-out clears the session even if the server cannot be told',
      () async {
        final (:auth, :repository, :tokens, :api) = build();
        await auth.signIn('tendai@example.test', 'pw');
        repository.logoutFailure = const ApiFailure.network();

        await auth.signOut();

        expect(repository.logouts, 1);
        expect(auth.signedIn, isFalse);
        expect(tokens.token, isNull);
        expect(api.bearerToken, isNull);
      },
    );
  });
}
