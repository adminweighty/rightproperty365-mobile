import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/calendar.dart';
import 'package:rightproperty365/features/appointments/appointment_screens.dart';
import 'package:rightproperty365/features/venues/venue_screens.dart';

import 'seeker_and_appointments_test.dart' show appointmentJson;
import 'support.dart';
import 'venues_test.dart' show bookingJson;
import 'work_test.dart' show serve, settle;

void main() {
  final event = CalendarEvent(
    title: 'Viewing: Borrowdale house',
    start: DateTime.utc(2030, 3, 2, 8),
    end: DateTime.utc(2030, 3, 2, 8, 30),
    location: 'Borrowdale house',
    notes: 'RightProperty365 appointment AP-7K3M9QXD',
  );

  group('the phone calendar', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('rightproperty365/calendar');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('Android: the system new-event screen, filled in', () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            call = c;
            return true;
          });
      final opened = <Uri>[];
      final added = await PhoneCalendar(
        openLink: (url) async {
          opened.add(url);
          return true;
        },
        platform: TargetPlatform.android,
      ).add(event);
      expect(added, isTrue);
      expect(call!.method, 'insert');
      expect(call!.arguments, {
        'title': 'Viewing: Borrowdale house',
        'begin': DateTime.utc(2030, 3, 2, 8).millisecondsSinceEpoch,
        'end': DateTime.utc(2030, 3, 2, 8, 30).millisecondsSinceEpoch,
        'location': 'Borrowdale house',
        'notes': 'RightProperty365 appointment AP-7K3M9QXD',
      });
      expect(opened, isEmpty);
    });

    test('no calendar app, or an iPhone: Google Calendar on the web', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async => false);
      final opened = <Uri>[];
      Future<bool> open(Uri url) async {
        opened.add(url);
        return true;
      }

      await PhoneCalendar(
        openLink: open,
        platform: TargetPlatform.android,
      ).add(event);
      await PhoneCalendar(
        openLink: open,
        platform: TargetPlatform.iOS,
      ).add(event);
      expect(opened, hasLength(2));
      final url = opened.first;
      expect(url.host, 'calendar.google.com');
      expect(url.queryParameters['action'], 'TEMPLATE');
      expect(url.queryParameters['dates'], '20300302T080000Z/20300302T083000Z');
      expect(url.queryParameters['text'], 'Viewing: Borrowdale house');
    });
  });

  group('the .ics file from the API, on iPhone', () {
    const channel = MethodChannel('rightproperty365/calendar');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('downloaded with the session and shown by the system', () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            call = c;
            return true;
          });
      final opened = <Uri>[];
      final withFile = CalendarEvent(
        title: event.title,
        start: event.start,
        end: event.end,
        file: () async => (bytes: [66, 69, 71], name: 'appointment-AP-1.ics'),
      );
      final added = await PhoneCalendar(
        openLink: (url) async {
          opened.add(url);
          return true;
        },
        platform: TargetPlatform.iOS,
      ).add(withFile);
      expect(added, isTrue);
      expect(call!.method, 'openIcs');
      expect((call!.arguments as Map)['name'], 'appointment-AP-1.ics');
      expect((call!.arguments as Map)['bytes'], [66, 69, 71]);
      expect(opened, isEmpty);
    });

    test('a failed download falls back to the web page', () async {
      final opened = <Uri>[];
      await PhoneCalendar(
        openLink: (url) async {
          opened.add(url);
          return true;
        },
        platform: TargetPlatform.iOS,
      ).add(
        CalendarEvent(
          title: event.title,
          start: event.start,
          end: event.end,
          file: () async => throw const ApiFailure.network(),
        ),
      );
      expect(opened.single.host, 'calendar.google.com');
    });

    test('Android keeps its own new-event screen, no download', () async {
      var downloads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async => c.method == 'insert');
      await PhoneCalendar(
        openLink: (url) async => true,
        platform: TargetPlatform.android,
      ).add(
        CalendarEvent(
          title: event.title,
          start: event.start,
          end: event.end,
          file: () async {
            downloads++;
            return (bytes: <int>[], name: 'x.ics');
          },
        ),
      );
      expect(downloads, 0);
    });
  });

  group('Add to calendar', () {
    testWidgets('on a confirmed appointment only', (tester) async {
      final test = TestServices();
      var status = 'REQUESTED';
      serve(test, {
        'GET /v1/me/appointments/ap-1/calendar.ics': (_) =>
            http.Response('BEGIN:VCALENDAR', 200),
        'GET /v1/me/appointments/ap-1': (_) => {
          'appointment': appointmentJson(status: status),
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const AppointmentScreen(id: 'ap-1', professional: false),
      );
      await settle(tester);
      expect(find.byKey(const Key('appointment-calendar')), findsNothing);

      status = 'CONFIRMED';
      await pumpInApp(
        tester,
        test,
        const AppointmentScreen(
          key: ValueKey('again'),
          id: 'ap-1',
          professional: false,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('appointment-calendar')));
      await settle(tester);
      final e = test.calendar.single;
      final file = await e.file!();
      expect(file.name, 'appointment-AP-7K3M9QXD.ics');
      expect(
        test.workRequests.last.url.path,
        '/v1/me/appointments/ap-1/calendar.ics',
      );
      expect(e.start, DateTime.utc(2030, 3, 2, 8));
      expect(e.end, DateTime.utc(2030, 3, 2, 8, 30));
      expect(e.title, startsWith('Viewing: '));
      expect(e.notes, contains('AP-7K3M9QXD'));
    });

    testWidgets('on a confirmed hourly booking', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/venue-bookings/vb-1/calendar.ics': (_) =>
            http.Response('BEGIN:VCALENDAR', 200),
        'GET /v1/me/venue-bookings/vb-1': (_) =>
            bookingJson(status: 'CONFIRMED'),
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const VenueBookingScreen(id: 'vb-1'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('venue-calendar')));
      await tester.tap(find.byKey(const Key('venue-calendar')));
      await settle(tester);
      final e = test.calendar.single;
      await e.file!();
      expect(
        test.workRequests.last.url.path,
        '/v1/me/venue-bookings/vb-1/calendar.ics',
      );
      expect(e.title, 'Booking: Glass-fronted showroom');
      expect(e.start, DateTime.parse('2030-12-05T12:30:00Z'));
      expect(e.end, DateTime.parse('2030-12-05T14:30:00Z'));
      expect(e.notes, contains('VB-7K3M9QXD'));
    });

    testWidgets('not once it has ended', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/appointments/ap-1': (_) => {
          'appointment': {
            ...appointmentJson(status: 'CONFIRMED'),
            'start_utc': '2020-03-02T08:00:00Z',
          },
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(
        tester,
        test,
        const AppointmentScreen(id: 'ap-1', professional: false),
      );
      await settle(tester);
      expect(find.byKey(const Key('appointment-calendar')), findsNothing);
    });
  });
}
