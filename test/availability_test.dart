import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/features/appointments/appointment_repository.dart';
import 'package:rightproperty365/features/appointments/availability.dart';
import 'package:rightproperty365/features/appointments/availability_screen.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';

import 'searchable_select_test.dart' show openField;
import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

/// Two days with free starts, in Harare (UTC+2).
Map<String, dynamic> slotsJson({
  bool configured = true,
  List<Map<String, dynamic>> services = const [],
}) => {
  'configured': configured,
  'timezone': 'Africa/Harare',
  'slot_minutes': 30,
  'services': services,
  'days': configured
      ? [
          {
            'date': '2030-03-04',
            'slots': [
              {
                'start_utc': '2030-03-04T07:00:00Z',
                'end_utc': '2030-03-04T07:30:00Z',
              },
              {
                'start_utc': '2030-03-04T07:30:00Z',
                'end_utc': '2030-03-04T08:00:00Z',
              },
            ],
          },
          {'date': '2030-03-05', 'slots': []},
          {
            'date': '2030-03-06',
            'slots': [
              {
                'start_utc': '2030-03-06T12:00:00Z',
                'end_utc': '2030-03-06T12:30:00Z',
              },
            ],
          },
        ]
      : [],
};

final valuation = {
  'id': 'svc-1',
  'name': 'Valuation chat',
  'duration_minutes': 45,
  'channel': 'VIDEO',
  'location': '',
  'notes': '',
  'active': true,
};

final settingsJson = {
  'enabled': false,
  'timezone': 'Africa/Harare',
  'working_hours': [
    {'weekday': 1, 'opens': '09:00', 'closes': '17:00'},
  ],
  'exceptions': [
    {'date': '2030-12-25', 'closed': true, 'note': 'Christmas'},
  ],
  'slot_minutes': 30,
  'buffer_minutes': 0,
  'lead_time_hours': 24,
  'horizon_days': 30,
  'max_per_day': 0,
  'updated_at': null,
};

Future<void> pumpForm(WidgetTester tester, TestServices test) => pumpInApp(
  tester,
  test,
  Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: PropertyRequestForm(listing: test.listings.listings.first),
    ),
  ),
);

Future<void> chooseType(WidgetTester tester, String label) async {
  await openField(tester, const Key('request-type'));
  await tester.tap(find.text(label).last);
  await settle(tester);
}

Future<void> fillAndSend(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
  await tester.enterText(find.byKey(const Key('email')), 'test@example.com');
  await tester.ensureVisible(find.byKey(const Key('consent')));
  await tester.tap(find.byKey(const Key('consent')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('submit')));
  await tester.tap(find.byKey(const Key('submit')));
  await settle(tester);
}

void main() {
  group('the model', () {
    test('reads slots and services', () {
      final s = AppointmentSlots.fromJson(slotsJson(services: [valuation]));
      expect(s.configured, isTrue);
      expect(s.days, hasLength(3));
      expect(s.days.first.slots.first.startUtc, DateTime.utc(2030, 3, 4, 7));
      expect(s.services.single.summary, '45 minutes · Video call');
      expect(
        AppointmentSlots.fromJson(slotsJson(configured: false)).anyFree,
        isFalse,
      );
    });

    test('settings go back as they came', () {
      final s = AvailabilitySettings.fromJson(settingsJson);
      final json = s.copyWith(enabled: true, maxPerDay: 4).toJson();
      expect(json['enabled'], isTrue);
      expect(json['max_per_day'], 4);
      expect(json['working_hours'], [
        {'weekday': 1, 'opens': '09:00', 'closes': '17:00'},
      ]);
      expect(json['exceptions'], [
        {'date': '2030-12-25', 'closed': true, 'note': 'Christmas'},
      ]);
    });

    test('a service is sent only with a consultation request', () {
      PropertyRequestDraft draft(RequestType type) => PropertyRequestDraft(
        listingId: 'l-1',
        requestType: type,
        message: 'Hi',
        contactMethod: ContactMethod.email,
        contact: const EnquiryContact(),
        consentAccepted: true,
        privacyVersion: 'v1',
        serviceId: 'svc-1',
      );
      expect(
        draft(RequestType.consultationRequest).toJson('k')['service_id'],
        'svc-1',
      );
      expect(
        draft(RequestType.viewingRequest).toJson('k').containsKey('service_id'),
        isFalse,
      );
    });

    test('an appointment shows its service', () {
      final a = Appointment.fromJson({
        'id': 'a-1',
        'reference': 'AP-1',
        'type': 'CONSULTATION',
        'status': 'REQUESTED',
        'start_utc': '2030-03-04T07:00:00Z',
        'service': {
          'id': 'svc-1',
          'name': 'Valuation chat',
          'channel': 'VIDEO',
        },
      });
      expect(a.serviceLabel, 'Valuation chat (Video call)');
      expect(
        Appointment.fromJson({
          'id': 'a-1',
          'reference': 'AP-1',
          'type': 'VIEWING',
          'status': 'REQUESTED',
          'start_utc': '2030-03-04T07:00:00Z',
          'service': null,
        }).serviceLabel,
        isNull,
      );
    });
  });

  group('booking a time', () {
    testWidgets('a viewing offers the free times in the market zone', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      serve(test, {'GET /v1/appointments/slots': (_) => slotsJson()});
      await pumpForm(tester, test);
      await chooseType(tester, 'Book a viewing');
      final ask = test.workRequests.last.url;
      expect(ask.queryParameters['type'], 'VIEWING');
      expect(ask.queryParameters['listing_id'], listing.id);
      expect(find.byKey(const Key('slot-picker')), findsOneWidget);
      expect(find.text('Times are in Harare time.'), findsOneWidget);
      // The free picker is not offered; the empty day is not shown.
      expect(find.byKey(const Key('free-time')), findsNothing);
      expect(find.byKey(const Key('slot-day-2030-03-05')), findsNothing);
      // 07:00 UTC is 09:00 in Harare.
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('slot-day-2030-03-06')));
      await settle(tester);
      expect(find.text('14:00'), findsOneWidget);
      await tester.tap(find.text('14:00'));
      await settle(tester);

      await fillAndSend(tester);
      final draft = test.propertyRequests.drafts.single;
      expect(draft.requestType, RequestType.viewingRequest);
      expect(draft.preferredSlot, DateTime.utc(2030, 3, 6, 12));
      expect(draft.serviceId, isNull);
    });

    testWidgets('a consultation may choose a service, which asks again', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/appointments/slots': (_) => slotsJson(services: [valuation]),
      });
      await pumpForm(tester, test);
      await chooseType(tester, 'Request a consultation');
      await openField(tester, const Key('consultation-service'));
      await tester.tap(find.textContaining('Valuation chat').last);
      await settle(tester);
      final ask = test.workRequests.last.url;
      expect(ask.queryParameters['type'], 'CONSULTATION');
      expect(ask.queryParameters['service_id'], 'svc-1');
      await tester.tap(find.text('09:00'));
      await settle(tester);
      await fillAndSend(tester);
      final draft = test.propertyRequests.drafts.single;
      expect(draft.serviceId, 'svc-1');
      expect(draft.preferredSlot, DateTime.utc(2030, 3, 4, 7));
    });

    testWidgets('no calendar: any time may be asked for, as before', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/appointments/slots': (_) => slotsJson(configured: false),
      });
      await pumpForm(tester, test);
      await chooseType(tester, 'Book a viewing');
      expect(find.byKey(const Key('slot-picker')), findsNothing);
      expect(find.byKey(const Key('free-time')), findsOneWidget);
    });

    testWidgets('slots that cannot be loaded fall back to any time', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/appointments/slots': (_) => failure(500, 'INTERNAL'),
      });
      await pumpForm(tester, test);
      await chooseType(tester, 'Book a viewing');
      expect(find.byKey(const Key('free-time')), findsOneWidget);
    });
  });

  group('the professional', () {
    testWidgets('sets hours and rules, and saves', (tester) async {
      final test = TestServices();
      Map<String, dynamic>? saved;
      serve(test, {
        'GET /v1/me/appointment-settings': (_) => settingsJson,
        'GET /v1/me/consultation-services': (_) => {
          'items': [valuation],
        },
        'PUT /v1/me/appointment-settings': (r) {
          saved = bodyOf(r);
          return {...saved!, 'updated_at': '2030-03-01T10:00:00Z'};
        },
      });
      await pumpInApp(tester, test, const AvailabilityScreen());
      await settle(tester);
      expect(find.text('09:00–17:00'), findsOneWidget);
      expect(find.text('Closed · Christmas'), findsOneWidget);
      expect(find.text('Valuation chat'), findsOneWidget);
      expect(
        find.textContaining('paid consultations are not offered'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('availability-enabled')));
      await settle(tester);
      await openField(tester, const Key('availability-max'));
      await tester.tap(find.text('4').last);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('availability-save')));
      await tester.tap(find.byKey(const Key('availability-save')));
      await settle(tester);
      expect(saved!['enabled'], isTrue);
      expect(saved!['max_per_day'], 4);
      expect(saved!['working_hours'], [
        {'weekday': 1, 'opens': '09:00', 'closes': '17:00'},
      ]);
      expect(find.text('Availability saved.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused save shows the API reason per field', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/appointment-settings': (_) => {
          ...settingsJson,
          'working_hours': [],
        },
        'GET /v1/me/consultation-services': (_) => {'items': []},
        'PUT /v1/me/appointment-settings': (_) => failure(
          400,
          'VALIDATION_FAILED',
          fields: {'working_hours': 'needs at least one range to enable'},
        ),
      });
      await pumpInApp(tester, test, const AvailabilityScreen());
      await settle(tester);
      expect(find.byKey(const Key('services-empty')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('availability-save')));
      await tester.tap(find.byKey(const Key('availability-save')));
      await settle(tester);
      expect(
        find.text('working hours: needs at least one range to enable'),
        findsOneWidget,
      );
    });

    testWidgets('adds and removes a consultation', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/appointment-settings': (_) => settingsJson,
        'GET /v1/me/consultation-services': (_) => {'items': []},
        'POST /v1/me/consultation-services': (r) => http.Response(
          '{"id":"svc-2","name":"${bodyOf(r)['name']}","duration_minutes":'
          '${bodyOf(r)['duration_minutes']},"channel":"${bodyOf(r)['channel']}",'
          '"active":true}',
          201,
        ),
        'DELETE /v1/me/consultation-services/svc-2': (_) =>
            http.Response('', 204),
      });
      await pumpInApp(tester, test, const AvailabilityScreen());
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('service-add')));
      await tester.tap(find.byKey(const Key('service-add')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('service-name')),
        'Rental advice',
      );
      await openField(tester, const Key('service-channel'));
      await tester.tap(find.text('Phone call').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('service-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post)['channel'], 'PHONE');
      expect(bodyOf(post)['duration_minutes'], 30);
      expect(bodyOf(post).containsKey('price'), isFalse);
      expect(find.text('Rental advice'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('service-archive-svc-2')),
      );
      await tester.tap(find.byKey(const Key('service-archive-svc-2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('service-archive-confirm')));
      await settle(tester);
      expect(find.text('Rental advice'), findsNothing);
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/appointment-settings': (_) => settingsJson,
        'GET /v1/me/consultation-services': (_) => {
          'items': [valuation],
        },
        'GET /v1/appointments/slots': (_) => slotsJson(services: [valuation]),
      });
      await pumpInApp(tester, test, const AvailabilityScreen(), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: SingleChildScrollView(
            child: PropertyRequestForm(listing: test.listings.listings.first),
          ),
        ),
        textScale: 2,
      );
      await settle(tester);
      await chooseType(tester, 'Book a viewing');
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('slot-day-2030-03-04'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
