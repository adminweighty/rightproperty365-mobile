import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/notifications/marketing_card.dart';
import 'package:rightproperty365/features/notifications/marketing_repository.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const path = '/v1/me/marketing-preferences';
const wording =
    'Send me news, tips and offers from RightProperty365 by email. I can '
    'stop them at any time.';

/// The contract's shape (contract-0.37-marketing-preferences.md); not yet
/// checked against a running API.
Map<String, dynamic> prefsJson({
  bool optIn = false,
  String current = 'marketing-2026-01',
  bool chosen = true,
  bool withText = true,
}) => {
  'marketing_opt_in': optIn,
  'changed_at': chosen ? '2026-11-19T06:10:00Z' : null,
  'source': chosen ? 'app' : null,
  'context': chosen ? 'PREFERENCES' : null,
  'consent_text_version': optIn ? 'marketing-2026-01' : null,
  'current_consent_text_version': current,
  'consent_text': withText
      ? {'version': current, 'text': wording, 'status': 'DRAFT'}
      : null,
  'history': [
    if (chosen)
      {
        'marketing_opt_in': optIn,
        'changed_at': '2026-11-19T06:10:00Z',
        'source': 'app',
        'context': 'PREFERENCES',
        'consent_text_version': optIn ? 'marketing-2026-01' : null,
      },
    if (chosen)
      {
        'marketing_opt_in': !optIn,
        'changed_at': '2026-10-01T09:00:00Z',
        'source': 'web',
        'context': 'REGISTRATION',
        'consent_text_version': 'marketing-2026-01',
      },
  ],
};

void main() {
  group('the marketing preferences API', () {
    test('opting in records the wording shown, from the app', () async {
      final (:api, :requests) = routedApi({
        'GET $path': (_) => prefsJson(chosen: false),
        'PUT $path': (_) => prefsJson(optIn: true),
      });
      final repo = MarketingRepository(api);
      final before = await repo.get();
      expect(before.optIn, isFalse);
      expect(before.last, isNull);
      expect(before.consentText, contains('news, tips and offers'));
      final after = await repo.set(true, version: before.currentVersion);
      expect(jsonBody(requests.last), {
        'marketing_opt_in': true,
        'consent_text_version': 'marketing-2026-01',
      });
      expect(requests.last.headers['X-Client'], 'app');
      expect(after.optIn, isTrue);
      expect(after.history.last.where, 'when you registered');
    });

    test('opting out sends no wording version', () async {
      final (:api, :requests) = routedApi({'PUT $path': (_) => prefsJson()});
      await MarketingRepository(api).set(false, version: 'marketing-2026-01');
      expect(jsonBody(requests.single), {'marketing_opt_in': false});
    });

    test('a changed wording is explained', () async {
      final (:api, requests: _) = routedApi({
        'PUT $path': (_) => apiError(
          400,
          'VALIDATION_FAILED',
          fields: {'consent_text_version': 'The consent wording has changed'},
        ),
      });
      await expectLater(
        MarketingRepository(api).set(true, version: 'marketing-2025-01'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('wording has changed'),
          ),
        ),
      );
    });
  });

  group('News and offers', () {
    testWidgets('off by default; turning it on shows the wording', (
      tester,
    ) async {
      final test = TestServices();
      var on = false;
      serve(test, {
        'GET $path': (_) => prefsJson(optIn: on, chosen: false),
        'PUT $path': (request) {
          on = bodyOf(request)['marketing_opt_in'] as bool;
          return prefsJson(optIn: on);
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const Scaffold(body: SingleChildScrollView(child: MarketingCard())),
      );
      await settle(tester);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('marketing-switch')),
      );
      expect(toggle.value, isFalse);
      expect(find.text(wording), findsOneWidget);
      expect(find.byKey(const Key('marketing-last')), findsNothing);

      await tester.tap(find.byKey(const Key('marketing-switch')));
      await settle(tester);
      final put = test.workRequests.lastWhere((r) => r.method == 'PUT');
      expect(bodyOf(put), {
        'marketing_opt_in': true,
        'consent_text_version': 'marketing-2026-01',
      });
      expect(
        find.textContaining('Turned on 19 Nov 2026 in the app'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('marketing-history')), findsOneWidget);
    });

    testWidgets('no wording from the API: off stays off, on can stop', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET $path': (_) => prefsJson(
          current: 'marketing-2027-01',
          chosen: false,
          withText: false,
        ),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const Scaffold(body: SingleChildScrollView(child: MarketingCard())),
      );
      await settle(tester);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('marketing-switch')),
      );
      expect(toggle.onChanged, isNull);
      expect(find.textContaining('could not be loaded'), findsOneWidget);

      serve(test, {
        'GET $path': (_) => prefsJson(
          optIn: true,
          current: 'marketing-2027-01',
          withText: false,
        ),
      });
      await pumpInApp(
        tester,
        test,
        const Scaffold(
          body: SingleChildScrollView(
            child: MarketingCard(key: ValueKey('again')),
          ),
        ),
      );
      await settle(tester);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('marketing-switch')))
            .onChanged,
        isNotNull,
      );
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {'GET $path': (_) => prefsJson(optIn: true)});
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const Scaffold(body: SingleChildScrollView(child: MarketingCard())),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
