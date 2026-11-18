import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/venues/venue_repository.dart';
import 'package:rightproperty365/features/venues/venue_screens.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

/// Times are 2030-12-05 in Harare (UTC+2): open 08:00-18:00 local, a
/// confirmed booking (with its buffer) 10:00-14:30 local.
Map<String, dynamic> range(String start, String end) => {
  'start': start,
  'end': end,
  'local_start': start,
  'local_end': end,
};

Map<String, dynamic> availabilityJson() => {
  'listing_id': 'venue-1',
  'time_zone': 'Africa/Harare',
  'currency': 'USD',
  'rate_per_hour': '50.00',
  'deposit': '100.00',
  'deposit_note': 'payable to the host if confirmed',
  'increment_minutes': 30,
  'min_minutes': 120,
  'max_minutes': 480,
  'cleaning_buffer_minutes': 30,
  'capacity': 1,
  'lead_time_hours': 24,
  'horizon_days': 90,
  'bookable_from': '2030-12-01T06:00:00Z',
  'bookable_until': '2031-03-01T06:00:00Z',
  'cancellation_policy': 'Cancel up to 48 hours before at no cost.',
  'free_cancellation_hours': 48,
  'mode': 'ENQUIRY',
  'notice': venueNoPaymentNotice,
  'days': [
    {
      'date': '2030-12-05',
      'weekday': 4,
      'closed': false,
      'note': null,
      'open_ranges': [range('2030-12-05T06:00:00Z', '2030-12-05T16:00:00Z')],
      'booked': [range('2030-12-05T08:00:00Z', '2030-12-05T12:30:00Z')],
    },
    {
      'date': '2030-12-08',
      'weekday': 7,
      'closed': true,
      'note': null,
      'open_ranges': [],
      'booked': [],
    },
  ],
};

Map<String, dynamic> quoteJson({String start = '2030-12-05T12:30:00Z'}) => {
  'quote_id': 'q-1',
  'listing_id': 'venue-1',
  'expires_at': '2030-12-01T08:30:00Z',
  'currency': 'USD',
  // The API lists the percentage fee last; the app reads the kinds.
  'lines': [
    {
      'code': 'RATE',
      'kind': 'RATE',
      'label': '2 h × USD 50.00',
      'amount': '100.00',
    },
    {'code': 'TAX', 'kind': 'PERCENT', 'label': 'VAT 15%', 'amount': '15.00'},
    {'code': 'CLEAN', 'kind': 'FIXED', 'label': 'Cleaning', 'amount': '20.00'},
  ],
  'subtotal': '120.00',
  'deposit': '100.00',
  'deposit_note': 'payable to the host if confirmed',
  'total_excluding_deposit': '135.00',
  'start': start,
  'end': '2030-12-05T14:30:00Z',
  'duration_minutes': 120,
  'time_zone': 'Africa/Harare',
  'local_start': '2030-12-05T14:30:00+02:00',
  'local_end': '2030-12-05T16:30:00+02:00',
  'mode': 'ENQUIRY',
  'notice': venueNoPaymentNotice,
};

Map<String, dynamic> bookingJson({
  String status = 'REQUESTED',
  List<String> actions = const ['cancel'],
  bool host = false,
}) => {
  'id': 'vb-1',
  'reference': 'VB-7K3M9QXD',
  'service_type': 'VENUE_HOURLY',
  'status': status,
  'status_label': switch (status) {
    'CONFIRMED' => 'Confirmed',
    'DECLINED' => 'Declined',
    'CANCELLED' => 'Cancelled',
    _ => 'Requested',
  },
  'listing': {
    'id': 'venue-1',
    'slug': 'glass-fronted-showroom-eastlea',
    'title': 'Glass-fronted showroom',
    'reference': 'RP-ZW-10021',
  },
  'start': '2030-12-05T12:30:00Z',
  'end': '2030-12-05T14:30:00Z',
  'duration_minutes': 120,
  'time_zone': 'Africa/Harare',
  'local_start': '2030-12-05T14:30:00+02:00',
  'local_end': '2030-12-05T16:30:00+02:00',
  'attendees': 12,
  'message': 'A product launch',
  'quote': {
    'quote_id': 'q-1',
    'currency': 'USD',
    'lines': quoteJson()['lines'],
    'subtotal': '120.00',
    'deposit': '100.00',
    'total_excluding_deposit': '135.00',
  },
  'mode': 'ENQUIRY',
  'notice': venueNoPaymentNotice,
  'deposit_note': 'payable to the host if confirmed',
  'cancellation_policy': {
    'text': 'Cancel up to 48 hours before at no cost.',
    'free_cancellation_hours': 48,
    'free_until': '2030-12-03T12:30:00Z',
  },
  'proposal': null,
  'cancellation': null,
  'decline_reason': null,
  'actions': actions,
  'created_at': '2030-11-20T08:00:00Z',
  'updated_at': '2030-11-20T08:00:00Z',
  if (host) 'customer': {'name': 'Tom Tenant', 'email': 'tenant@example.test'},
  'events': [
    {
      'id': 'e-1',
      'action': 'REQUESTED',
      'from_status': null,
      'to_status': 'REQUESTED',
      'actor': 'CUSTOMER',
      'actor_name': 'Tom Tenant',
      'reason': null,
      'start': null,
      'end': null,
      'at': '2030-11-20T08:00:00Z',
    },
  ],
};

void main() {
  group('availability', () {
    test('offers only starts and durations that fit and are free', () {
      final venue = VenueAvailability.fromJson(availabilityJson());
      final day = venue.days.first;
      expect(venue.days.last.bookable, isFalse);
      final starts = venue.starts(day);
      // 08:00 (2 h until the booking at 10:00), then from 14:30 local.
      expect(starts.first, DateTime.utc(2030, 12, 5, 6));
      expect(starts.contains(DateTime.utc(2030, 12, 5, 6, 30)), isFalse);
      expect(starts.contains(DateTime.utc(2030, 12, 5, 12, 30)), isTrue);
      // The last start leaves the minimum two hours before closing.
      expect(starts.last, DateTime.utc(2030, 12, 5, 14));
      expect(venue.durations(day, DateTime.utc(2030, 12, 5, 6)), [120]);
      expect(venue.durations(day, DateTime.utc(2030, 12, 5, 12, 30)), [
        120,
        150,
        180,
        210,
      ]);
    });

    test('a quote reads in bill order whatever the API order', () {
      final quote = VenueQuote.fromJson(quoteJson());
      expect(quote.beforeSubtotal.map((l) => l.code), ['RATE', 'CLEAN']);
      expect(quote.onSubtotal.single.label, 'VAT 15%');
      expect(quote.total, '135.00');
    });
  });

  group('the venue API', () {
    test('asks for days, quotes and requests as documented', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/venues/venue-1/availability': (_) => availabilityJson(),
        'POST /v1/venues/venue-1/quotes': (request) =>
            jsonBody(request)['start'] == '2030-12-05T08:00:00.000Z'
            ? apiError(409, 'SLOT_UNAVAILABLE')
            : jsonResponse(201, quoteJson()),
        'POST /v1/me/venue-bookings': (_) => jsonResponse(201, bookingJson()),
        'POST /v1/agent/organisations/org-1/venue-bookings/vb-1/no-show': (_) =>
            bookingJson(status: 'NO_SHOW'),
        'POST /v1/me/hosted-venue-bookings/vb-1/confirm': (_) =>
            apiError(409, 'SLOT_TAKEN'),
      });
      final repo = VenueRepository(api);
      await repo.availability('venue-1', from: DateTime(2030, 12, 1));
      expect(requests.last.url.queryParameters, {
        'from': '2030-12-01',
        'to': '2031-01-31',
      });

      final quote = await repo.quote(
        'venue-1',
        DateTime.utc(2030, 12, 5, 12, 30),
        DateTime.utc(2030, 12, 5, 14, 30),
      );
      expect(jsonBody(requests.last), {
        'start': '2030-12-05T12:30:00.000Z',
        'end': '2030-12-05T14:30:00.000Z',
      });
      try {
        await repo.quote(
          'venue-1',
          DateTime.utc(2030, 12, 5, 8),
          DateTime.utc(2030, 12, 5, 10),
        );
        fail('expected a refusal');
      } on ApiFailure catch (failure) {
        expect(slotProblem(failure), contains('not available'));
      }
      expect(
        slotProblem(
          const ApiFailure(
            status: 409,
            code: 'SLOT_UNAVAILABLE',
            message: '',
            details: {'reason': 'BUFFER'},
          ),
        ),
        contains('time to clean'),
      );

      final sent = await repo.request(
        quote.id,
        message: ' A launch ',
        attendees: 12,
        privacyVersion: 'v1',
      );
      expect(jsonBody(requests.last), {
        'quote_id': 'q-1',
        'message': 'A launch',
        'attendees': 12,
        'consent': {'privacy_version': 'v1', 'accepted': true},
      });
      expect(sent.reference, 'VB-7K3M9QXD');

      await repo.hostAction('org-1', 'vb-1', 'no_show');
      expect(requests.last.url.path, endsWith('/vb-1/no-show'));
      await expectLater(
        repo.hostAction('u-1', 'vb-1', 'confirm', personal: true),
        throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'SLOT_TAKEN')),
      );
    });
  });

  group('booking by the hour', () {
    testWidgets('day, start, duration, estimate in order, then send', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/venues/venue-1/availability': (_) => availabilityJson(),
        'POST /v1/venues/venue-1/quotes': (_) => jsonResponse(201, quoteJson()),
        'POST /v1/me/venue-bookings': (_) => jsonResponse(201, bookingJson()),
      });
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const HourlyBookingScreen(
          listingId: 'venue-1',
          title: 'Glass-fronted showroom',
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('venue-day-2030-12-08')), findsNothing);
      await tester.tap(find.byKey(const Key('venue-day-2030-12-05')));
      await settle(tester);
      expect(find.byKey(const Key('venue-start-10:00')), findsNothing);
      await tester.tap(find.byKey(const Key('venue-start-14:30')));
      await settle(tester);
      expect(find.text('2 h · until 16:30'), findsOneWidget);

      expect(find.byKey(const Key('venue-quote')), findsOneWidget);
      final subtotal = tester.getTopLeft(find.text('Subtotal')).dy;
      expect(tester.getTopLeft(find.text('Cleaning')).dy, lessThan(subtotal));
      expect(tester.getTopLeft(find.text('VAT 15%')).dy, greaterThan(subtotal));
      expect(
        find.text('Deposit, payable to the host if confirmed'),
        findsOneWidget,
      );
      expect(find.text(venueNoPaymentNotice), findsOneWidget);

      final send = find.byKey(const Key('venue-send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('venue-attendees')), '12');
      await tester.tap(find.byKey(const Key('venue-consent')));
      await tester.pump();
      await tester.tap(send);
      await settle(tester);
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.textContaining('VB-7K3M9QXD'), findsOneWidget);
      expect(bodyOf(test.workRequests.last)['attendees'], 12);
    });

    testWidgets('the host confirms, and a clash is explained', (tester) async {
      final test = TestServices();
      var clash = true;
      const base = '/v1/agent/organisations/org-1/venue-bookings/vb-1';
      serve(test, {
        'GET $base': (_) => bookingJson(
          host: true,
          actions: ['confirm', 'decline', 'propose', 'cancel'],
        ),
        'POST $base/confirm': (_) => clash
            ? apiError(409, 'SLOT_TAKEN')
            : bookingJson(status: 'CONFIRMED', host: true, actions: ['cancel']),
        'POST $base/decline': (_) =>
            bookingJson(status: 'DECLINED', host: true),
      });
      await pumpInApp(
        tester,
        test,
        const VenueBookingScreen(
          id: 'vb-1',
          book: ContactBook(id: 'org-1', name: 'Sample', canWrite: true),
        ),
      );
      await settle(tester);
      expect(find.text('Tom Tenant'), findsOneWidget);
      await tester.tap(find.byKey(const Key('venue-host-confirm')));
      await settle(tester);
      expect(find.textContaining('already been confirmed'), findsOneWidget);
      clash = false;
      await tester.tap(find.byKey(const Key('venue-host-confirm')));
      await settle(tester);
      expect(find.text('Confirmed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('holds at 200% text size with an estimate', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/venues/venue-1/availability': (_) => availabilityJson(),
        'POST /v1/venues/venue-1/quotes': (_) => jsonResponse(201, quoteJson()),
      });
      await pumpInApp(
        tester,
        test,
        const HourlyBookingScreen(listingId: 'venue-1'),
        textScale: 2,
        size: const Size(390, 2400),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('venue-day-2030-12-05')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('venue-start-14:30')));
      await settle(tester);
      expect(find.byKey(const Key('venue-quote')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a customer cancels, told whether it is free', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/venue-bookings/vb-1': (_) => bookingJson(),
        'POST /v1/me/venue-bookings/vb-1/cancel': (_) =>
            bookingJson(status: 'CANCELLED', actions: []),
      });
      await pumpInApp(tester, test, const VenueBookingScreen(id: 'vb-1'));
      await settle(tester);
      expect(find.textContaining('Free until'), findsOneWidget);
      await tester.tap(find.byKey(const Key('venue-cancel')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await settle(tester);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byKey(const Key('venue-cancel')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
