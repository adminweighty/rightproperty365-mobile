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
    this.file,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final String? notes;

  /// The API's calendar file (UID and SEQUENCE kept, so a reschedule or a
  /// cancellation updates the same entry), fetched with the session when
  /// needed; never a link with a token in it.
  final Future<({List<int> bytes, String name})> Function()? file;

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

/// How the app adds an event:
/// - Android: the phone's own "new event" screen, filled in (any calendar
///   app; no calendar permission). Google Calendar on Android does not
///   import .ics files, so the native screen stays.
/// - iPhone: the API's .ics in the system preview, which offers "Add to
///   Calendar"; it carries a stable UID and rising SEQUENCE.
/// - Otherwise, or if those fail: Google Calendar's page in the browser. The person always confirms the
/// event in that screen; the app writes nothing to the calendar itself.
class PhoneCalendar {
  PhoneCalendar({required this.openLink, TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final Future<bool> Function(Uri url) openLink;
  final TargetPlatform _platform;

  static const _channel = MethodChannel('rightproperty365/calendar');

  /// Returns false when nothing on the phone could take the event.
  Future<bool> add(CalendarEvent event) async {
    if (_platform == TargetPlatform.iOS && event.file != null) {
      try {
        final file = await event.file!();
        final shown = await _channel.invokeMethod<bool>('openIcs', {
          'bytes': Uint8List.fromList(file.bytes),
          'name': file.name,
        });
        if (shown ?? false) return true;
      } on PlatformException {
        // Not shown: the web page instead.
      } on MissingPluginException {
        // Not wired (tests): the web page instead.
      } on Exception {
        // Could not download (offline): the web page instead.
      }
    }
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
