import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/app_scope.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/app/theme/app_theme.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/api/language.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/legal/legal.dart';
import 'package:rightproperty365/features/legal/legal_screens.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

Map<String, dynamic> pendingJson(String kind, String title) => {
  'kind': kind,
  'title': title,
  'version': '2027-01-01',
  'market_code': 'GLOBAL',
  'effective_from': '2027-01-01T00:00:00Z',
  'summary_of_changes': 'Clearer cancellation terms.',
};

Map<String, dynamic> documentJson(
  String kind,
  String title, {
  bool draft = true,
}) => {
  'id': 'v-$kind',
  'kind': kind,
  'title': title,
  'market_code': 'GLOBAL',
  'lang': 'en',
  'version': '2027-01-01',
  'effective_from': '2027-01-01T00:00:00Z',
  'status': 'PUBLISHED',
  'body_markdown':
      '> **DRAFT — awaiting legal review.**\n\n# $title\n\n'
      'You agree to *these* terms.<script>x</script>\n\n'
      '- First point\n- See [the website](https://example.test)\n',
  'summary_of_changes': 'Clearer cancellation terms.',
  'requires_reacceptance': true,
  'draft_notice': draft,
};

/// A fake API with [pending] documents waiting; accepting removes one.
void serveLegal(TestServices app, List<Map<String, dynamic>> pending) {
  serve(app, {
    'GET /v1/me': (_) => {
      'user': {'id': 'u-1'},
      'pending_legal_acceptances': pending,
    },
    'GET /v1/legal/terms': (_) => {
      'document': documentJson('TERMS', 'Terms and Conditions'),
    },
    'GET /v1/legal/privacy': (_) => {
      'document': documentJson('PRIVACY', 'Privacy Policy', draft: false),
    },
    'POST /v1/me/legal-acceptances': (r) {
      final kind = bodyOf(r)['kind'];
      pending.removeWhere((p) => p['kind'] == kind);
      return jsonResponse(201, {
        'acceptance': {...bodyOf(r), 'context': 'REACCEPTANCE'},
      });
    },
  });
}

Widget bannerApp(TestServices app, GoRouter router) => AppScope(
  services: app.services,
  child: MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
    builder: (context, child) =>
        LegalBanner(centre: app.legal, router: router, child: child!),
  ),
);

GoRouter smallRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(body: Text('Home')),
    ),
    GoRoute(
      path: Routes.legalUpdates,
      builder: (context, state) => const LegalUpdatesScreen(),
    ),
  ],
);

void main() {
  group('Accept-Language', () {
    test('the phone\'s languages in order, English last', () {
      expect(
        acceptLanguageHeader(const [Locale('en', 'ZW'), Locale('sn', 'ZW')]),
        'en-ZW, sn-ZW;q=0.9',
      );
      expect(
        acceptLanguageHeader(const [Locale('fr', 'FR')]),
        'fr-FR, en;q=0.9',
      );
      expect(acceptLanguageHeader(const []), 'en');
    });

    test('is sent with every request when set', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(200, {'ok': true}),
      );
      await api.get('/v1/legal');
      expect(requests.last.headers['Accept-Language'], isNull);
      api.acceptLanguage = () => 'sn-ZW, en;q=0.9';
      await api.get('/v1/legal');
      await api.postJson('/v1/me/legal-acceptances', {});
      await api.postFile('/v1/x', field: 'file', bytes: [1], fileName: 'a.png');
      expect(
        requests.skip(1).map((r) => r.headers['Accept-Language']),
        everyElement('sn-ZW, en;q=0.9'),
      );
    });
  });

  group('the repository', () {
    test('reads what waits, and nothing from an older API', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/me': (_) => {
          'user': {'id': 'u-1'},
          'pending_legal_acceptances': [pendingJson('TERMS', 'Terms')],
        },
      });
      final pending = await LegalRepository(api).pending();
      expect(pending.single.kind, 'TERMS');
      expect(pending.single.version, '2027-01-01');
      expect(pending.single.effectiveFrom, DateTime.utc(2027));

      final (api: older, requests: _) = routedApi({
        'GET /v1/me': (_) => {
          'user': {'id': 'u-1'},
        },
      });
      expect(await LegalRepository(older).pending(), isEmpty);
    });

    test('asks for that version and market, and accepts it', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/legal/terms': (_) => {
          'document': documentJson('TERMS', 'Terms and Conditions'),
        },
        'POST /v1/me/legal-acceptances': (_) => jsonResponse(200, {
          'acceptance': {'kind': 'TERMS'},
        }),
      });
      final repo = LegalRepository(api);
      final item = PendingLegal.fromJson(pendingJson('TERMS', 'Terms'));
      final doc = await repo.document(item);
      expect(requests.last.url.queryParameters, {
        'version': '2027-01-01',
        'market': 'GLOBAL',
      });
      expect(doc.draftNotice, isTrue);
      await repo.accept(item);
      expect(jsonDecode(requests.last.body), {
        'kind': 'TERMS',
        'version': '2027-01-01',
        'market_code': 'GLOBAL',
      });
    });

    test('a version that cannot be accepted is said plainly', () async {
      final (:api, requests: _) = routedApi({
        'POST /v1/me/legal-acceptances': (_) =>
            apiError(409, 'LEGAL_VERSION_NOT_ACCEPTABLE'),
      });
      await expectLater(
        LegalRepository(api)
            .accept(PendingLegal.fromJson(pendingJson('TERMS', 'Terms'))),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('cannot be accepted now'),
          ),
        ),
      );
    });
  });

  group('the centre', () {
    test('fills on sign-in and empties on sign-out', () async {
      final app = TestServices();
      serveLegal(app, [pendingJson('TERMS', 'Terms and Conditions')]);
      expect(app.legal.pending, isEmpty);
      await app.auth.signIn('tendai@example.test', 'pw');
      await pumpEventQueue();
      expect(app.legal.showBanner, isTrue);
      app.legal.later();
      expect(app.legal.showBanner, isFalse);
      await app.auth.signOut();
      expect(app.legal.pending, isEmpty);
    });

    test('an API without the field, or offline, shows nothing', () async {
      final app = TestServices();
      serve(app, {
        'GET /v1/me': (_) => {
          'user': {'id': 'u-1'},
        },
      });
      await app.auth.signIn('tendai@example.test', 'pw');
      await pumpEventQueue();
      expect(app.legal.showBanner, isFalse);
    });
  });

  group('the banner and the screen', () {
    testWidgets('review, read the draft, accept; the banner goes', (
      tester,
    ) async {
      final app = TestServices();
      serveLegal(app, [
        pendingJson('TERMS', 'Terms and Conditions'),
        pendingJson('PRIVACY', 'Privacy Policy'),
      ]);
      await app.auth.signIn('tendai@example.test', 'pw');
      final router = smallRouter();
      await tester.pumpWidget(bannerApp(app, router));
      await settle(tester);
      // Nothing is blocked: the app is there under the banner.
      expect(find.text('Home'), findsOneWidget);
      expect(
        find.textContaining('updated 2 documents: Terms and Conditions, '),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('legal-review')));
      await settle(tester);
      expect(find.byType(LegalUpdatesScreen), findsOneWidget);
      expect(find.byKey(const Key('legal-banner')), findsNothing);
      // The draft notice only where the API asks for it.
      expect(find.byKey(const Key('legal-draft-TERMS')), findsOneWidget);
      expect(find.byKey(const Key('legal-draft-PRIVACY')), findsNothing);
      expect(
        find.textContaining('Clearer cancellation terms'),
        findsNWidgets(2),
      );
      // The Markdown as text: no tags, links show their words only.
      expect(find.textContaining('<script>', findRichText: true), findsNothing);
      expect(
        find.textContaining('See the website', findRichText: true),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('https://example.test', findRichText: true),
        findsNothing,
      );

      await tester.ensureVisible(find.byKey(const Key('legal-accept-TERMS')));
      await tester.tap(find.byKey(const Key('legal-accept-TERMS')));
      await settle(tester);
      expect(find.byKey(const Key('legal-accept-TERMS')), findsNothing);
      expect(find.byKey(const Key('legal-accept-PRIVACY')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('legal-accept-PRIVACY')));
      await tester.tap(find.byKey(const Key('legal-accept-PRIVACY')));
      await settle(tester);
      expect(find.byKey(const Key('legal-none')), findsOneWidget);
      expect(app.legal.pending, isEmpty);
      expect(
        app.workRequests
            .where((r) => r.url.path == '/v1/me/legal-acceptances')
            .map((r) => bodyOf(r)['kind']),
        ['TERMS', 'PRIVACY'],
      );
    });

    testWidgets('Later hides it; nothing waiting shows nothing', (
      tester,
    ) async {
      final app = TestServices();
      serveLegal(app, [pendingJson('TERMS', 'Terms and Conditions')]);
      await app.auth.signIn('tendai@example.test', 'pw');
      await tester.pumpWidget(bannerApp(app, smallRouter()));
      await settle(tester);
      expect(
        find.text(
          'We have updated our Terms and Conditions. Please review it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('legal-later')));
      await settle(tester);
      expect(find.byKey(const Key('legal-banner')), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final app = TestServices();
      serveLegal(app, [pendingJson('TERMS', 'Terms and Conditions')]);
      await app.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        app,
        const LegalUpdatesScreen(),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      expect(find.byKey(const Key('legal-draft-TERMS')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('sign-up sends no terms_version: the app shows only the privacy '
      'notice', () async {
    final (:api, :requests) = mockApi((_) async => http.Response('{}', 201));
    await ApiAuthRepository(api).register(
      name: 'Tendai',
      email: 't@example.test',
      password: 'pw',
      roles: const ['SEEKER'],
      consentAccepted: true,
      privacyVersion: '2026-11-draft',
      captchaId: 'c',
      captchaAnswer: '1',
    );
    final consent = jsonDecode(requests.single.body)['consent'] as Map;
    expect(consent.keys, unorderedEquals(['privacy_version', 'accepted']));
  });
}
