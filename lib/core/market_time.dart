import 'package:flutter/foundation.dart' show visibleForTesting;
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
    for (final name in [zone, ?_aliases[zone]]) {
      try {
        return tz.getLocation(name);
      } on tz.LocationNotFoundException {
        continue;
      }
    }
    return null;
  }

  /// Whether [zone] (or what it links to) is in the bundled data.
  static bool knows(String zone) => _location(zone) != null;

  /// The link names resolved to another zone, for tests.
  @visibleForTesting
  static Iterable<String> get aliasTargets => _aliases.values;

  /// tzdata keeps many zones only as links to another (Africa/Harare is
  /// Africa/Maputo), and the bundled data leaves links out. Without this a
  /// Zimbabwe or Botswana time would silently show in the phone's own zone.
  static const _aliases = {
    'Africa/Harare': 'Africa/Maputo',
    'Africa/Gaborone': 'Africa/Maputo',
    'Africa/Lusaka': 'Africa/Maputo',
    'Africa/Blantyre': 'Africa/Maputo',
    'Africa/Bujumbura': 'Africa/Maputo',
    'Africa/Kigali': 'Africa/Maputo',
    'Africa/Lubumbashi': 'Africa/Maputo',
    'Africa/Maseru': 'Africa/Johannesburg',
    'Africa/Mbabane': 'Africa/Johannesburg',
    'Africa/Addis_Ababa': 'Africa/Nairobi',
    'Africa/Asmara': 'Africa/Nairobi',
    'Africa/Dar_es_Salaam': 'Africa/Nairobi',
    'Africa/Djibouti': 'Africa/Nairobi',
    'Africa/Kampala': 'Africa/Nairobi',
    'Africa/Mogadishu': 'Africa/Nairobi',
    'Africa/Accra': 'Africa/Abidjan',
    'Africa/Bamako': 'Africa/Abidjan',
    'Africa/Banjul': 'Africa/Abidjan',
    'Africa/Conakry': 'Africa/Abidjan',
    'Africa/Dakar': 'Africa/Abidjan',
    'Africa/Freetown': 'Africa/Abidjan',
    'Africa/Lome': 'Africa/Abidjan',
    'Africa/Nouakchott': 'Africa/Abidjan',
    'Africa/Ouagadougou': 'Africa/Abidjan',
    'Africa/Bangui': 'Africa/Lagos',
    'Africa/Brazzaville': 'Africa/Lagos',
    'Africa/Douala': 'Africa/Lagos',
    'Africa/Kinshasa': 'Africa/Lagos',
    'Africa/Libreville': 'Africa/Lagos',
    'Africa/Luanda': 'Africa/Lagos',
    'Africa/Malabo': 'Africa/Lagos',
    'Africa/Niamey': 'Africa/Lagos',
    'Africa/Porto-Novo': 'Africa/Lagos',
    'Asia/Muscat': 'Asia/Dubai',
    'Asia/Bahrain': 'Asia/Qatar',
    'Asia/Kuwait': 'Asia/Riyadh',
    'Asia/Aden': 'Asia/Riyadh',
  };

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
