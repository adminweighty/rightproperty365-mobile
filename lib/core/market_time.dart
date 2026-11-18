import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Times shown in the market's own time zone, as the API asks
/// (`Appointment.timezone`, an IANA name such as `Africa/Harare`), and named.
abstract final class MarketTime {
  static bool _loaded = false;

  static tz.Location? _location(String zone) {
    if (!_loaded) {
      tzdata.initializeTimeZones();
      _loaded = true;
    }
    try {
      return tz.getLocation(zone);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  /// [utc] as a wall-clock time in [zone]; the phone's own time when the
  /// zone is unknown.
  static DateTime inZone(DateTime utc, String zone) {
    final location = _location(zone);
    return location == null
        ? utc.toLocal()
        : tz.TZDateTime.from(utc.toUtc(), location);
  }

  /// The instant at which the clocks in [zone] show [wallClock] (only its
  /// date and time of day are read).
  static DateTime toUtc(DateTime wallClock, String zone) {
    final location = _location(zone);
    if (location == null) {
      return DateTime(
        wallClock.year,
        wallClock.month,
        wallClock.day,
        wallClock.hour,
        wallClock.minute,
      ).toUtc();
    }
    return tz.TZDateTime(
      location,
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
    ).toUtc();
  }

  /// For example "Tue 18 Nov 2026, 14:30 (Harare time)".
  static String format(DateTime utc, String zone) =>
      '${DateFormat('EEE d MMM y, HH:mm').format(inZone(utc, zone))} '
      '(${zoneName(zone)} time)';

  /// The city part of an IANA name: `Africa/Harare` is "Harare".
  static String zoneName(String zone) {
    final city = zone.split('/').last.replaceAll('_', ' ');
    return city.isEmpty ? zone : city;
  }
}
