import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

  group('Add to calendar', () {
    testWidgets('on a confirmed appointment only', (tester) async {
      final test = TestServices();
      var status = 'REQUESTED';
      serve(test, {
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
      expect(e.start, DateTime.utc(2030, 3, 2, 8));
      expect(e.end, DateTime.utc(2030, 3, 2, 8, 30));
      expect(e.title, startsWith('Viewing: '));
      expect(e.notes, contains('AP-7K3M9QXD'));
    });

    testWidgets('on a confirmed hourly booking', (tester) async {
      final test = TestServices();
      serve(test, {
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
      expect(e.title, 'Booking: Glass-fronted showroom');
      expect(e.start, DateTime.parse('2030-12-05T12:30:00Z'));
      expect(e.end, DateTime.parse('2030-12-05T14:30:00Z'));
      expect(e.notes, contains('VB-7K3M9QXD'));
    });
  });
}
