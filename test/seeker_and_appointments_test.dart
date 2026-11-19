import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/market_time.dart';
import 'package:rightproperty365/features/appointments/appointment_repository.dart';
import 'package:rightproperty365/features/appointments/appointment_screens.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/presentation/delete_account_screen.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/inbox/lead_screen.dart';
import 'package:rightproperty365/features/leases/lease_repository.dart';
import 'package:rightproperty365/features/markets/data/market.dart';

import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

/// An appointment as the API returns it, with the flags overridden.
Map<String, dynamic> appointmentJson({
  String status = 'REQUESTED',
  String? proposedStart,
  String? proposedBy,
  Map<String, dynamic> flags = const {},
  bool professional = false,
}) => {
  'id': 'ap-1',
  'reference': 'AP-7K3M9QXD',
  'type': 'VIEWING',
  'status': status,
  'status_label': switch (status) {
    'CONFIRMED' => 'Confirmed',
    'RESCHEDULE_REQUESTED' => 'Reschedule Requested',
    'CANCELLED' => 'Cancelled',
    _ => 'Requested',
  },
  'start_utc': '2030-03-02T08:00:00Z',
  'end_utc': '2030-03-02T08:30:00Z',
  'timezone': 'Africa/Harare',
  'duration_minutes': 30,
  'proposed_start_utc': proposedStart,
  'proposed_by': proposedBy,
  'listing': {
    'slug': 'four-bedroom-family-home-borrowdale',
    'title': 'Four-bedroom family home',
    'reference': 'RP-ZW-10001',
  },
  'with': {'kind': 'agents', 'slug': 'tendai', 'name': 'Tendai Moyo'},
  'location_note': null,
  'note': 'Can we see the garden?',
  'property_request_reference': 'RP-8VXWDQJG',
  'business_enquiry_reference': null,
  'cancelled_by': null,
  'cancel_reason': null,
  'created_at': '2030-03-01T08:00:00Z',
  'updated_at': '2030-03-01T08:00:00Z',
  'timeline': [
    {
      'event': 'REQUESTED',
      'from': null,
      'to': 'REQUESTED',
      'to_label': 'Requested',
      'actor': 'CUSTOMER',
      'note': null,
      'start_utc': '2030-03-02T08:00:00Z',
      'at': '2030-03-01T08:00:00Z',
    },
  ],
  if (professional) ...{
    'listing_id': '0195c0de-0000-7000-8000-000000000001',
    'organisation_id': 'org-1',
    'assigned_to': null,
    'contact': {
      'name': 'Tom Tenant',
      'email': 'tom@example.test',
      'phone': '+263771234567',
    },
    'preferred_contact_method': 'PHONE',
  },
  'can_cancel': true,
  'can_reschedule': true,
  'can_accept': false,
  if (professional) ...{
    'can_confirm': true,
    'can_complete': false,
    'can_no_show': false,
    'can_assign': false,
  },
  ...flags,
};

Map<String, dynamic> myRequestJson({
  String reference = 'RP-8VXWDQJG',
  bool timeline = false,
}) => {
  'request_id': 'req-1',
  'reference': reference,
  'listing_id': '0195c0de-0000-7000-8000-000000000001',
  'listing': {
    'slug': 'four-bedroom-family-home-borrowdale',
    'title': 'Four-bedroom family home',
    'reference': 'RP-ZW-10001',
  },
  'request_type': 'VIEWING_REQUEST',
  'status': 'RESPONDED',
  'status_label': 'Responded',
  'message': 'Is it still available?',
  'preferred_contact_method': 'EMAIL',
  'preferred_slot_utc': null,
  'stay': null,
  'created_at': '2030-03-01T08:00:00Z',
  if (timeline)
    'timeline': [
      {
        'event': 'RECEIVED',
        'status': 'RECEIVED',
        'status_label': 'Received',
        'at': '2030-03-01T08:00:00Z',
      },
      {
        'event': 'STATUS_CHANGED',
        'status': 'RESPONDED',
        'status_label': 'Responded',
        'at': '2030-03-01T09:00:00Z',
      },
    ],
};

Map<String, dynamic> leadJson({
  String stage = 'NEW_ENQUIRY',
  List notes = const [],
}) => {
  'request_id': 'req-9',
  'reference': 'RP-2BCDFGHJ',
  'listing_id': '0195c0de-0000-7000-8000-000000000001',
  'listing': {
    'slug': 'four-bedroom-family-home-borrowdale',
    'title': 'Four-bedroom family home',
    'reference': 'RP-ZW-10001',
  },
  'request_type': 'ENQUIRY',
  'status': 'RECEIVED',
  'stage': stage,
  'stage_label': stage == 'CONTACTED' ? 'Contacted' : 'New enquiry',
  'stage_changed_at': null,
  'stay': null,
  'message': 'Is the price negotiable?',
  'preferred_contact_method': 'EMAIL',
  'contact': {'name': 'Tom Tenant', 'email': 'tom@example.test', 'phone': null},
  'created_at': '2030-03-01T08:00:00Z',
  'assigned_to': null,
  'preferred_slot_utc': null,
  'updated_at': '2030-03-01T08:00:00Z',
  'allowed_stages': stage == 'CONTACTED'
      ? [
          {'stage': 'CONVERTED', 'label': 'Converted'},
          {'stage': 'CLOSED', 'label': 'Closed'},
        ]
      : [
          {'stage': 'CONTACTED', 'label': 'Contacted'},
          {'stage': 'CLOSED', 'label': 'Closed'},
        ],
  'can_assign': false,
  'timeline': [
    {
      'event': 'REQUEST_RECEIVED',
      'label': 'Request received',
      'from_stage': null,
      'to_stage': null,
      'actor': 'CUSTOMER',
      'actor_name': null,
      'assignee_name': null,
      'at': '2030-03-01T08:00:00Z',
    },
  ],
  'notes': notes,
};

void main() {
  group('market time', () {
    test('knows the zone of every market, whatever the phone is set to', () {
      // Africa/Harare and Africa/Gaborone are tzdata links, which the
      // bundled data leaves out; they must still resolve.
      for (final market in markets) {
        expect(MarketTime.knows(market.timezone), isTrue, reason: market.code);
      }
      for (final zone in MarketTime.aliasTargets) {
        expect(MarketTime.knows(zone), isTrue, reason: zone);
      }
      expect(
        MarketTime.inZone(DateTime.utc(2030, 3, 2, 8), 'Africa/Gaborone').hour,
        10,
      );
    });

    test('shows times in the market and names it', () {
      final utc = DateTime.utc(2030, 3, 2, 8);
      expect(MarketTime.inZone(utc, 'Africa/Harare').hour, 10);
      expect(
        MarketTime.format(utc, 'Africa/Harare'),
        'Sat 2 Mar 2030, 10:00 (Harare time)',
      );
      // London keeps summer time: 12:00 in July is 11:00 UTC.
      expect(
        MarketTime.toUtc(DateTime(2030, 7, 1, 12), 'Europe/London'),
        DateTime.utc(2030, 7, 1, 11),
      );
      expect(MarketTime.toUtc(DateTime(2030, 3, 2, 10), 'Africa/Harare'), utc);
    });
  });

  group('appointments API', () {
    test('reads both sides and words the conflicts', () async {
      final a = Appointment.fromJson(appointmentJson(professional: true));
      expect(a.contactPhone, '+263771234567');
      expect(a.canConfirm, isTrue);
      expect(a.title, 'Four-bedroom family home');
      expect(
        a.timeline.single.describe(professional: true),
        'The customer asked for this time',
      );

      final (:api, :requests) = mockApi(
        (request) async => request.url.path.endsWith('/confirm')
            ? failure(409, 'SLOT_TAKEN')
            : jsonResponse(200, {'appointment': appointmentJson()}),
      );
      final received = ApiReceivedAppointmentsRepository(api);
      await expectLater(
        received.confirm('ap-1'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('overlaps another confirmed appointment'),
          ),
        ),
      );
      expect(requests.last.url.path, '/v1/inbox/appointments/ap-1/confirm');

      await ApiMyAppointmentsRepository(api)
          .reschedule('ap-1', DateTime.utc(2030, 3, 3, 9), note: ' Later? ');
      expect(requests.last.url.path, '/v1/me/appointments/ap-1/reschedule');
      expect(bodyOf(requests.last), {
        'start_utc': '2030-03-03T09:00:00.000Z',
        'note': 'Later?',
      });

      await received.list(from: DateTime.utc(2030, 3, 1));
      expect(
        requests.last.url.queryParameters['from'],
        '2030-03-01T00:00:00.000Z',
      );
    });
  });

  group('a signed-in Property Seeker', () {
    testWidgets('follows enquiries and viewings on the Activity tab', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/property-requests': (_) => {
          'items': [myRequestJson()],
          'page': 1,
          'page_size': 50,
          'total': 1,
          'total_pages': 1,
          'status_counts': [],
        },
        'GET /v1/me/property-requests/req-1': (_) => {
          'request': myRequestJson(timeline: true),
        },
        'GET /v1/me/appointments': (_) => {
          'items': [
            appointmentJson(
              status: 'RESCHEDULE_REQUESTED',
              proposedStart: '2030-03-03T09:00:00Z',
              proposedBy: 'PROFESSIONAL',
            ),
          ],
          'page': 1,
          'page_size': 50,
          'total': 1,
          'total_pages': 1,
        },
      });
      // A guest enquiry from this phone, which the account does not hold.
      await test.activity.recordRequest(
        receipt: EnquiryReceipt(
          id: 'guest',
          reference: 'RP-GUESTXYZ',
          status: 'RECEIVED',
          createdAt: DateTime.utc(2030),
        ),
        title: 'Garden cottage',
        recipient: 'Sample Estates',
        route: '/',
      );
      await test.auth.signIn('tom@example.test', 'pw');

      final router = buildRouter();
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(appWith(test, router));
      router.go(Routes.activity);
      await settle(tester);

      expect(find.text('My Viewings'), findsOneWidget);
      expect(find.text('Responded'), findsOneWidget);
      expect(find.text('Sent from this phone'), findsOneWidget);
      expect(find.text('Garden cottage'), findsOneWidget);

      await tester.tap(find.byKey(const Key('my-request-RP-8VXWDQJG')));
      await settle(tester);
      expect(find.text('Your enquiry'), findsOneWidget);
      expect(find.textContaining('Now responded'), findsOneWidget);
      router.pop();
      await settle(tester);

      await tester.tap(find.text('My Viewings'));
      await settle(tester);
      expect(find.text('New time proposed to you'), findsOneWidget);
    });

    testWidgets('accepts a new time and cancels with a reason', (tester) async {
      final test = TestServices();
      var current = appointmentJson(
        status: 'RESCHEDULE_REQUESTED',
        proposedStart: '2030-03-03T09:00:00Z',
        proposedBy: 'PROFESSIONAL',
        flags: {'can_accept': true},
      );
      serve(test, {
        'GET /v1/me/appointments/ap-1': (_) => {'appointment': current},
        'POST /v1/me/appointments/ap-1/accept': (_) {
          current = appointmentJson(status: 'CONFIRMED');
          return {'appointment': current};
        },
        'POST /v1/me/appointments/ap-1/cancel': (_) => {
          'appointment': appointmentJson(
            status: 'CANCELLED',
            flags: {'can_cancel': false, 'can_reschedule': false},
          ),
        },
      });
      await pumpInApp(
        tester,
        test,
        const AppointmentScreen(id: 'ap-1', professional: false),
      );
      await settle(tester);
      expect(
        find.textContaining(
          'They proposed Sun 3 Mar 2030, 11:00 (Harare time)',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('appointment-accept')));
      await settle(tester);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byKey(const Key('appointment-accept')), findsNothing);

      await tester.tap(find.byKey(const Key('appointment-cancel')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('dialog-text')),
        'Found a place',
      );
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await settle(tester);
      final cancel = test.workRequests.last;
      expect(cancel.url.path, '/v1/me/appointments/ap-1/cancel');
      expect(bodyOf(cancel), {'reason': 'Found a place'});
      expect(find.text('Cancelled'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a professional', () {
    testWidgets('confirms an appointment and is told about a clash', (
      tester,
    ) async {
      final test = TestServices();
      var clash = true;
      serve(test, {
        'GET /v1/inbox/appointments/ap-1': (_) => {
          'appointment': appointmentJson(professional: true),
        },
        'POST /v1/inbox/appointments/ap-1/confirm': (_) => clash
            ? failure(409, 'SLOT_TAKEN')
            : {
                'appointment': appointmentJson(
                  status: 'CONFIRMED',
                  professional: true,
                  flags: {'can_confirm': false},
                ),
              },
      });
      await pumpInApp(
        tester,
        test,
        const AppointmentScreen(id: 'ap-1', professional: true),
      );
      await settle(tester);
      expect(find.text('+263771234567'), findsOneWidget);
      expect(find.textContaining('prefers a phone call'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointment-confirm')));
      await settle(tester);
      expect(
        find.textContaining('overlaps another confirmed appointment'),
        findsOneWidget,
      );

      clash = false;
      await tester.tap(find.byKey(const Key('appointment-confirm')));
      await settle(tester);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(bodyOf(test.workRequests.last), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('lists appointments by day, or says the account takes none', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/inbox/appointments': (_) => failure(403, 'FORBIDDEN'),
      });
      await pumpInApp(tester, test, const ReceivedAppointmentsScreen());
      await settle(tester);
      expect(find.text('This account takes no appointments'), findsOneWidget);

      final second = TestServices();
      serve(second, {
        'GET /v1/inbox/appointments': (_) => {
          'items': [appointmentJson(professional: true)],
          'page': 1,
          'page_size': 50,
          'total': 1,
          'total_pages': 1,
        },
      });
      // A fresh screen, not the first one's state.
      await tester.pumpWidget(const SizedBox());
      await pumpInApp(tester, second, const ReceivedAppointmentsScreen());
      await settle(tester);
      expect(find.text('Saturday 2 March'), findsOneWidget);
      expect(find.text('Viewing with Tom Tenant'), findsOneWidget);
    });

    testWidgets('moves a lead on and adds an internal note', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) => {'request': leadJson()},
        'PATCH /v1/agent/property-requests/req-9': (_) => {
          'request': leadJson(stage: 'CONTACTED'),
        },
        'POST /v1/agent/property-requests/req-9/notes': (request) =>
            jsonResponse(201, {
              'request': leadJson(
                stage: 'CONTACTED',
                notes: [
                  {
                    'id': 'n-1',
                    'body': bodyOf(request)['body'],
                    'author_name': 'Tendai Ncube',
                    'mine': true,
                    'created_at': '2030-03-01T10:00:00Z',
                  },
                ],
              ),
            }),
      });
      await pumpInApp(tester, test, const LeadScreen(requestId: 'req-9'));
      await settle(tester);
      expect(find.text('New enquiry'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stage-CONTACTED')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {'stage': 'CONTACTED'});
      expect(find.text('Contacted'), findsOneWidget);
      expect(find.byKey(const Key('stage-CONVERTED')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('lead-note')),
        '  Called, viewing on Friday  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lead-add-note')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {
        'body': 'Called, viewing on Friday',
      });
      expect(find.text('Called, viewing on Friday'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('deleting the account', () {
    testWidgets('is under Account, Settings, Account Management', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      final router = buildRouter();
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(appWith(test, router));
      router.go(Routes.account);
      await settle(tester);
      await tester.tap(find.byKey(const Key('open-account-management')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('open-delete-account')));
      await settle(tester);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });

    testWidgets('needs the password and a confirmation, then signs out', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      await test.activity.toggleSaved('some-listing');
      test.authRepository.deleteFailure = const ApiFailure(
        status: 401,
        code: 'INVALID_PASSWORD',
        message: 'That password is not right.',
        fields: {'password': 'That password is not right.'},
      );
      await pumpInApp(tester, test, const DeleteAccountScreen());

      final button = find.byKey(const Key('delete-account'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('delete-password')), 'wrong');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byKey(const Key('delete-understood')));
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
      expect(find.text('That password is not right.'), findsOneWidget);
      expect(test.auth.signedIn, isTrue);

      test.authRepository.deleteFailure = null;
      await tester.enterText(find.byKey(const Key('delete-password')), 'right');
      await tester.tap(button);
      await settle(tester);
      expect(test.authRepository.deletedWith, 'right');
      expect(find.text('Your account is deleted'), findsOneWidget);
      expect(test.auth.signedIn, isFalse);
      expect(await test.tokens.read(), isNull);
      expect(test.activity.savedSlugs, isEmpty);
    });

    test('words what the API refuses', () async {
      final (:api, requests: _) = mockApi(
        (request) async => failure(409, 'SOLE_OWNER'),
      );
      final repository = ApiAuthRepository(api);
      await expectLater(
        repository.deleteAccount('pw'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('only owner of an organisation'),
          ),
        ),
      );
    });
  });

  test("a lease is offered only the listings the agent may edit", () async {
    final (:api, requests: _) = mockApi(
      (request) async => jsonResponse(200, {
        'items': [
          {'id': 'l-1', 'title': 'Mine', 'can_edit': true},
          {
            'id': 'l-2',
            'title':
                'A colleague'
                's',
            'can_edit': false,
          },
          {'id': 'l-3', 'title': 'From API 0.26.0'},
        ],
      }),
    );
    final listings = await ApiLeaseRepository(api).listings();
    expect(listings.map((l) => l.id), ['l-1', 'l-3']);
  });
}
