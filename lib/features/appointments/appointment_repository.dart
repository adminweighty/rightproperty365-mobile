import '../../core/api/api_client.dart';

/// One entry of an appointment's history (`AppointmentTimelineEntry`).
class AppointmentEvent {
  const AppointmentEvent({
    required this.event,
    required this.toLabel,
    required this.actor,
    required this.at,
    this.note,
    this.startUtc,
  });

  factory AppointmentEvent.fromJson(Map<String, dynamic> json) =>
      AppointmentEvent(
        event: json['event'] as String,
        toLabel: json['to_label'] as String? ?? '',
        actor: json['actor'] as String? ?? 'SYSTEM',
        note: json['note'] as String?,
        startUtc: _time(json['start_utc']),
        at: DateTime.parse(json['at'] as String),
      );

  final String event;
  final String toLabel;

  /// CUSTOMER, PROFESSIONAL or SYSTEM; never a name.
  final String actor;
  final String? note;
  final DateTime? startUtc;
  final DateTime at;

  /// What happened, in words, for the side that is reading.
  String describe({required bool professional}) {
    final who = switch (actor) {
      'CUSTOMER' => professional ? 'The customer' : 'You',
      'PROFESSIONAL' => professional ? 'You' : 'They',
      _ => 'RightProperty365',
    };
    return switch (event) {
      'REQUESTED' => '$who asked for this time',
      'CONFIRMED' => '$who confirmed',
      'RESCHEDULE_REQUESTED' => '$who proposed a new time',
      'CANCELLED' => '$who cancelled',
      'COMPLETED' => 'Marked as completed',
      'NO_SHOW' => 'Marked as a no-show',
      'ASSIGNED' => 'Assigned to a team member',
      'UNASSIGNED' => 'Returned to the organisation',
      _ => toLabel,
    };
  }
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.parse(value) : null;

/// A viewing or consultation, as either side sees it (`CustomerAppointment`
/// or `ReceivedAppointment`). The `can*` flags come from the API; the app
/// offers exactly the actions they allow.
class Appointment {
  const Appointment({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.statusLabel,
    required this.startUtc,
    required this.timezone,
    required this.durationMinutes,
    this.proposedStartUtc,
    this.proposedBy,
    this.listingSlug,
    this.listingTitle,
    this.withName,
    this.locationNote,
    this.note,
    this.requestReference,
    this.cancelledBy,
    this.cancelReason,
    this.timeline = const [],
    this.canCancel = false,
    this.canReschedule = false,
    this.canAccept = false,
    this.canConfirm = false,
    this.canComplete = false,
    this.canNoShow = false,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    this.contactMethod,
    this.assignedTo,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>?;
    final contact = json['contact'] as Map<String, dynamic>?;
    return Appointment(
      id: json['id'] as String,
      reference: json['reference'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      statusLabel: json['status_label'] as String? ?? json['status'] as String,
      startUtc: DateTime.parse(json['start_utc'] as String),
      timezone: json['timezone'] as String? ?? 'UTC',
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      proposedStartUtc: _time(json['proposed_start_utc']),
      proposedBy: json['proposed_by'] as String?,
      listingSlug: listing?['slug'] as String?,
      listingTitle: listing?['title'] as String?,
      withName: (json['with'] as Map<String, dynamic>?)?['name'] as String?,
      locationNote: json['location_note'] as String?,
      note: json['note'] as String?,
      requestReference: json['property_request_reference'] as String?,
      cancelledBy: json['cancelled_by'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      timeline: [
        for (final entry in (json['timeline'] as List?) ?? const [])
          AppointmentEvent.fromJson(entry as Map<String, dynamic>),
      ],
      canCancel: json['can_cancel'] == true,
      canReschedule: json['can_reschedule'] == true,
      canAccept: json['can_accept'] == true,
      canConfirm: json['can_confirm'] == true,
      canComplete: json['can_complete'] == true,
      canNoShow: json['can_no_show'] == true,
      contactName: contact?['name'] as String?,
      contactEmail: contact?['email'] as String?,
      contactPhone: contact?['phone'] as String?,
      contactMethod: json['preferred_contact_method'] as String?,
      assignedTo:
          (json['assigned_to'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }

  final String id;

  /// `AP-...`, quoted in emails.
  final String reference;

  /// VIEWING or CONSULTATION.
  final String type;
  final String status;
  final String statusLabel;
  final DateTime startUtc;

  /// The market's IANA zone; times are shown in it.
  final String timezone;
  final int durationMinutes;
  final DateTime? proposedStartUtc;

  /// CUSTOMER or PROFESSIONAL: who proposed [proposedStartUtc].
  final String? proposedBy;
  final String? listingSlug;
  final String? listingTitle;

  /// The professional or business, when they have a public profile.
  final String? withName;
  final String? locationNote;
  final String? note;
  final String? requestReference;
  final String? cancelledBy;
  final String? cancelReason;
  final List<AppointmentEvent> timeline;

  final bool canCancel;
  final bool canReschedule;

  /// Customer: accept the professional's proposed time.
  final bool canAccept;

  /// Professional: confirm the requested time or the customer's proposal.
  final bool canConfirm;
  final bool canComplete;
  final bool canNoShow;

  /// Professional only: the customer's contact details.
  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String? contactMethod;
  final String? assignedTo;

  String get typeLabel => type == 'VIEWING' ? 'Viewing' : 'Consultation';

  String get title => listingTitle ?? withName ?? typeLabel;

  bool get open =>
      status == 'REQUESTED' ||
      status == 'CONFIRMED' ||
      status == 'RESCHEDULE_REQUESTED';
}

/// A page of appointments.
typedef AppointmentPage = ({List<Appointment> items, int total});

/// The customer's own appointments (`/v1/me/appointments`).
abstract interface class MyAppointmentsRepository {
  /// [when] is `upcoming` (soonest first) or `past` (newest first).
  Future<AppointmentPage> list({String when = 'upcoming'});
  Future<Appointment> get(String id);
  Future<Appointment> cancel(String id, {String? reason});

  /// Proposes [startUtc]; the professional accepts it.
  Future<Appointment> reschedule(String id, DateTime startUtc, {String? note});

  /// Accepts the time the professional proposed.
  Future<Appointment> accept(String id);

  /// The calendar file (`.ics`) of the appointment, read with the session.
  Future<List<int>> calendarFile(String id);
}

/// Appointments a professional or property owner received
/// (`/v1/inbox/appointments`). A 403 means the account takes none.
abstract interface class ReceivedAppointmentsRepository {
  /// Soonest first, starting at [from] (the start of today for the list).
  Future<AppointmentPage> list({required DateTime from});
  Future<Appointment> get(String id);

  /// Confirms the time on the table (the requested time, or the customer's
  /// proposal).
  Future<Appointment> confirm(String id, {String? locationNote});

  /// Proposes [startUtc]; the customer accepts it.
  Future<Appointment> reschedule(String id, DateTime startUtc, {String? note});
  Future<Appointment> cancel(String id, String reason);
  Future<Appointment> complete(String id);
  Future<Appointment> noShow(String id);

  /// The calendar file (`.ics`) of the appointment, read with the session.
  Future<List<int>> calendarFile(String id);
}

String _utc(DateTime time) => time.toUtc().toIso8601String();

AppointmentPage _page(ApiResponse response) => (
  items: [
    for (final item in (response.body['items'] as List?) ?? const [])
      Appointment.fromJson(item as Map<String, dynamic>),
  ],
  total: response.body['total'] as int? ?? 0,
);

Appointment _one(ApiResponse response) =>
    Appointment.fromJson(response.body['appointment'] as Map<String, dynamic>);

/// Wording for the API's appointment conflicts, so both sides read the same.
ApiFailure appointmentFailure(ApiFailure failure) => switch (failure.code) {
  'SLOT_TAKEN' => failure.withMessage(
    'That time overlaps another confirmed appointment. Choose another time.',
  ),
  'INVALID_STATE' => failure.withMessage(
    'This appointment has changed since you opened it, or that time has passed. '
    'Refresh to see where it stands.',
  ),
  _ => failure,
};

Future<Appointment> _act(Future<ApiResponse> call) async {
  try {
    return _one(await call);
  } on ApiFailure catch (failure) {
    throw appointmentFailure(failure);
  }
}

class ApiMyAppointmentsRepository implements MyAppointmentsRepository {
  ApiMyAppointmentsRepository(this._api);

  final ApiClient _api;
  static const _base = '/v1/me/appointments';

  @override
  Future<List<int>> calendarFile(String id) =>
      _api.getBytes('$_base/${Uri.encodeComponent(id)}/calendar.ics');

  @override
  Future<AppointmentPage> list({String when = 'upcoming'}) async =>
      _page(await _api.get('$_base?when=$when&page_size=50'));

  @override
  Future<Appointment> get(String id) async =>
      _one(await _api.get('$_base/${Uri.encodeComponent(id)}'));

  @override
  Future<Appointment> cancel(String id, {String? reason}) => _act(
    _api.postJson('$_base/${Uri.encodeComponent(id)}/cancel', {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    }),
  );

  @override
  Future<Appointment> reschedule(
    String id,
    DateTime startUtc, {
    String? note,
  }) => _act(
    _api.postJson('$_base/${Uri.encodeComponent(id)}/reschedule', {
      'start_utc': _utc(startUtc),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }),
  );

  @override
  Future<Appointment> accept(String id) =>
      _act(_api.post('$_base/${Uri.encodeComponent(id)}/accept'));
}

class ApiReceivedAppointmentsRepository
    implements ReceivedAppointmentsRepository {
  ApiReceivedAppointmentsRepository(this._api);

  final ApiClient _api;
  static const _base = '/v1/inbox/appointments';

  @override
  Future<List<int>> calendarFile(String id) =>
      _api.getBytes('$_base/${Uri.encodeComponent(id)}/calendar.ics');

  @override
  Future<AppointmentPage> list({required DateTime from}) async => _page(
    await _api.get(
      '$_base?from=${Uri.encodeQueryComponent(_utc(from))}&page_size=50',
    ),
  );

  @override
  Future<Appointment> get(String id) async =>
      _one(await _api.get('$_base/${Uri.encodeComponent(id)}'));

  @override
  Future<Appointment> confirm(String id, {String? locationNote}) => _act(
    _api.postJson('$_base/${Uri.encodeComponent(id)}/confirm', {
      if (locationNote != null && locationNote.trim().isNotEmpty)
        'location_note': locationNote.trim(),
    }),
  );

  @override
  Future<Appointment> reschedule(
    String id,
    DateTime startUtc, {
    String? note,
  }) => _act(
    _api.postJson('$_base/${Uri.encodeComponent(id)}/reschedule', {
      'start_utc': _utc(startUtc),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }),
  );

  @override
  Future<Appointment> cancel(String id, String reason) => _act(
    _api.postJson('$_base/${Uri.encodeComponent(id)}/cancel', {
      'reason': reason.trim(),
    }),
  );

  @override
  Future<Appointment> complete(String id) =>
      _act(_api.post('$_base/${Uri.encodeComponent(id)}/complete'));

  @override
  Future<Appointment> noShow(String id) =>
      _act(_api.post('$_base/${Uri.encodeComponent(id)}/no-show'));
}
