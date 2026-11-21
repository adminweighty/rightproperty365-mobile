/// Appointment availability, consultation services and bookable slots
/// (API 0.51.0). Consultations are free: the API refuses a price, and the
/// app never offers one.
library;

import '../../core/api/api_client.dart';

enum ConsultationChannel {
  inPerson('IN_PERSON', 'In person'),
  video('VIDEO', 'Video call'),
  phone('PHONE', 'Phone call');

  const ConsultationChannel(this.wire, this.label);
  final String wire;
  final String label;

  static ConsultationChannel from(Object? wire) => values.firstWhere(
    (c) => c.wire == wire,
    orElse: () => ConsultationChannel.inPerson,
  );
}

/// A consultation a professional offers (`/v1/me/consultation-services`).
class ConsultationService {
  const ConsultationService({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.channel,
    this.location,
    this.notes,
    this.active = true,
  });

  factory ConsultationService.fromJson(Map<String, dynamic> json) =>
      ConsultationService(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
        channel: ConsultationChannel.from(json['channel']),
        location: json['location'] as String?,
        notes: json['notes'] as String?,
        active: json['active'] != false,
      );

  final String id;
  final String name;
  final int durationMinutes;
  final ConsultationChannel channel;
  final String? location;
  final String? notes;
  final bool active;

  /// "45 minutes · Video call".
  String get summary => '$durationMinutes minutes · ${channel.label}';
}

/// One bookable start.
typedef Slot = ({DateTime startUtc, DateTime endUtc});

/// The offered times for one target (`GET /v1/appointments/slots`).
class AppointmentSlots {
  const AppointmentSlots({
    required this.configured,
    required this.timezone,
    this.slotMinutes = 30,
    this.services = const [],
    this.days = const [],
  });

  factory AppointmentSlots.fromJson(Map<String, dynamic> json) =>
      AppointmentSlots(
        configured: json['configured'] == true,
        timezone: json['timezone'] as String? ?? 'UTC',
        slotMinutes: (json['slot_minutes'] as num?)?.toInt() ?? 30,
        services: [
          for (final s in (json['services'] as List?) ?? const [])
            ConsultationService.fromJson(s as Map<String, dynamic>),
        ],
        days: [
          for (final d in (json['days'] as List?) ?? const [])
            (
              date: (d as Map<String, dynamic>)['date'] as String,
              slots: <Slot>[
                for (final s in (d['slots'] as List?) ?? const [])
                  (
                    startUtc: DateTime.parse(
                      (s as Map<String, dynamic>)['start_utc'] as String,
                    ),
                    endUtc: DateTime.parse(s['end_utc'] as String),
                  ),
              ],
            ),
        ],
      );

  /// False when nobody's calendar is behind the target, or availability is
  /// off: any time may then be asked for, as before.
  final bool configured;

  /// The market's zone the slots are laid out in.
  final String timezone;
  final int slotMinutes;
  final List<ConsultationService> services;

  /// Market-local dates (`YYYY-MM-DD`) with their free starts.
  final List<({String date, List<Slot> slots})> days;

  bool get anyFree => days.any((d) => d.slots.isNotEmpty);
}

/// One working range on a weekday (1 = Monday … 7 = Sunday), "HH:MM".
typedef WorkingRange = ({int weekday, String opens, String closes});

/// A date that is closed or keeps its own hours.
typedef AvailabilityException = ({
  String date,
  bool closed,
  String? opens,
  String? closes,
  String? note,
});

/// The signed-in professional's calendar rules
/// (`/v1/me/appointment-settings`).
class AvailabilitySettings {
  const AvailabilitySettings({
    required this.enabled,
    required this.timezone,
    this.workingHours = const [],
    this.exceptions = const [],
    this.slotMinutes = 30,
    this.bufferMinutes = 0,
    this.leadTimeHours = 24,
    this.horizonDays = 30,
    this.maxPerDay = 0,
  });

  factory AvailabilitySettings.fromJson(Map<String, dynamic> json) =>
      AvailabilitySettings(
        enabled: json['enabled'] == true,
        timezone: json['timezone'] as String? ?? 'Africa/Harare',
        workingHours: [
          for (final r in (json['working_hours'] as List?) ?? const [])
            (
              weekday: ((r as Map<String, dynamic>)['weekday'] as num).toInt(),
              opens: r['opens'] as String,
              closes: r['closes'] as String,
            ),
        ],
        exceptions: [
          for (final e in (json['exceptions'] as List?) ?? const [])
            (
              date: (e as Map<String, dynamic>)['date'] as String,
              closed: e['closed'] == true,
              opens: e['opens'] as String?,
              closes: e['closes'] as String?,
              note: e['note'] as String?,
            ),
        ],
        slotMinutes: (json['slot_minutes'] as num?)?.toInt() ?? 30,
        bufferMinutes: (json['buffer_minutes'] as num?)?.toInt() ?? 0,
        leadTimeHours: (json['lead_time_hours'] as num?)?.toInt() ?? 24,
        horizonDays: (json['horizon_days'] as num?)?.toInt() ?? 30,
        maxPerDay: (json['max_per_day'] as num?)?.toInt() ?? 0,
      );

  final bool enabled;
  final String timezone;
  final List<WorkingRange> workingHours;
  final List<AvailabilityException> exceptions;
  final int slotMinutes;
  final int bufferMinutes;
  final int leadTimeHours;
  final int horizonDays;

  /// 0: no daily limit.
  final int maxPerDay;

  AvailabilitySettings copyWith({
    bool? enabled,
    List<WorkingRange>? workingHours,
    List<AvailabilityException>? exceptions,
    int? slotMinutes,
    int? bufferMinutes,
    int? leadTimeHours,
    int? horizonDays,
    int? maxPerDay,
  }) => AvailabilitySettings(
    enabled: enabled ?? this.enabled,
    timezone: timezone,
    workingHours: workingHours ?? this.workingHours,
    exceptions: exceptions ?? this.exceptions,
    slotMinutes: slotMinutes ?? this.slotMinutes,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    leadTimeHours: leadTimeHours ?? this.leadTimeHours,
    horizonDays: horizonDays ?? this.horizonDays,
    maxPerDay: maxPerDay ?? this.maxPerDay,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'timezone': timezone,
    'working_hours': [
      for (final r in workingHours)
        {'weekday': r.weekday, 'opens': r.opens, 'closes': r.closes},
    ],
    'exceptions': [
      for (final e in exceptions)
        {
          'date': e.date,
          'closed': e.closed,
          if (!e.closed) 'opens': e.opens,
          if (!e.closed) 'closes': e.closes,
          if (e.note != null && e.note!.trim().isNotEmpty) 'note': e.note,
        },
    ],
    'slot_minutes': slotMinutes,
    'buffer_minutes': bufferMinutes,
    'lead_time_hours': leadTimeHours,
    'horizon_days': horizonDays,
    'max_per_day': maxPerDay,
  };
}

class AvailabilityRepository {
  AvailabilityRepository(this._api);

  final ApiClient _api;

  static const _services = '/v1/me/consultation-services';

  /// Free starts for a listing's viewing or consultation, from [from]
  /// (market-local date) for [days] days.
  Future<AppointmentSlots> slotsForListing({
    required String listingId,
    required bool consultation,
    String? serviceId,
    DateTime? from,
    int days = 14,
  }) async {
    final query = {
      'type': consultation ? 'CONSULTATION' : 'VIEWING',
      'listing_id': listingId,
      'service_id': ?serviceId,
      if (from != null)
        'from':
            '${from.year.toString().padLeft(4, '0')}-'
            '${from.month.toString().padLeft(2, '0')}-'
            '${from.day.toString().padLeft(2, '0')}',
      'days': '$days',
    };
    final body = (await _api.get(
      Uri(path: '/v1/appointments/slots', queryParameters: query).toString(),
    )).body;
    return AppointmentSlots.fromJson(body);
  }

  Future<AvailabilitySettings> settings() async =>
      AvailabilitySettings.fromJson(
        (await _api.get('/v1/me/appointment-settings')).body,
      );

  Future<AvailabilitySettings> save(AvailabilitySettings settings) async =>
      AvailabilitySettings.fromJson(
        (await _api.putJson(
          '/v1/me/appointment-settings',
          settings.toJson(),
        )).body,
      );

  /// Active and archived services.
  Future<List<ConsultationService>> services() async {
    final body = (await _api.get(_services)).body;
    return [
      for (final s in (body['items'] as List?) ?? const [])
        ConsultationService.fromJson(s as Map<String, dynamic>),
    ];
  }

  Map<String, dynamic> _serviceBody({
    required String name,
    required int durationMinutes,
    required ConsultationChannel channel,
    String? location,
    String? notes,
  }) => {
    'name': name.trim(),
    'duration_minutes': durationMinutes,
    'channel': channel.wire,
    'location': (location ?? '').trim(),
    'notes': (notes ?? '').trim(),
  };

  static ConsultationService _service(ApiResponse r) =>
      ConsultationService.fromJson(switch (r.body['service']) {
        final Map<String, dynamic> s => s,
        _ => r.body,
      });

  Future<ConsultationService> createService({
    required String name,
    required int durationMinutes,
    required ConsultationChannel channel,
    String? location,
    String? notes,
  }) async => _service(
    await _api.postJson(
      _services,
      _serviceBody(
        name: name,
        durationMinutes: durationMinutes,
        channel: channel,
        location: location,
        notes: notes,
      ),
    ),
  );

  Future<ConsultationService> updateService(
    String id, {
    required String name,
    required int durationMinutes,
    required ConsultationChannel channel,
    String? location,
    String? notes,
  }) async => _service(
    await _api.patchJson(
      '$_services/${Uri.encodeComponent(id)}',
      _serviceBody(
        name: name,
        durationMinutes: durationMinutes,
        channel: channel,
        location: location,
        notes: notes,
      ),
    ),
  );

  /// Archives it: existing appointments keep its name and channel.
  Future<void> archiveService(String id) =>
      _api.delete('$_services/${Uri.encodeComponent(id)}');
}
