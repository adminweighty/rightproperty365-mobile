import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An appointment or booking to put in the phone's calendar.
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.notes,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final String? notes;

  /// Google Calendar's "add event" page, for phones without the system
  /// sheet (iPhone, for now).
  Uri get googleCalendarUrl {
    String utc(DateTime d) =>
        '${d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${utc(start)}/${utc(end)}',
      'details': ?notes,
      'location': ?location,
    });
  }
}

/// How the app adds an event: the phone's own "new event" screen on
/// Android (any calendar app; no calendar permission is asked for), else
/// Google Calendar's page in the browser. The person always confirms the
/// event in that screen; the app writes nothing to the calendar itself.
class PhoneCalendar {
  PhoneCalendar({required this.openLink, TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final Future<bool> Function(Uri url) openLink;
  final TargetPlatform _platform;

  static const _channel = MethodChannel('rightproperty365/calendar');

  /// Returns false when nothing on the phone could take the event.
  Future<bool> add(CalendarEvent event) async {
    if (_platform == TargetPlatform.android) {
      try {
        final opened = await _channel.invokeMethod<bool>('insert', {
          'title': event.title,
          'begin': event.start.millisecondsSinceEpoch,
          'end': event.end.millisecondsSinceEpoch,
          'location': event.location,
          'notes': event.notes,
        });
        if (opened ?? false) return true;
      } on PlatformException {
        // No calendar app: Google Calendar on the web instead.
      } on MissingPluginException {
        // Not wired (tests): the web page instead.
      }
    }
    return openLink(event.googleCalendarUrl);
  }
}
