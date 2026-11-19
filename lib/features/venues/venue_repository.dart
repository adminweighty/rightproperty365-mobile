import '../../core/api/api_client.dart';

/// "This is an estimate..." as the API words it, used when a response has
/// none (it always does).
const venueNoPaymentNotice =
    'This is an estimate. No payment is taken on RightProperty365; the host confirms and arranges payment with you.';

/// A listing's hourly booking summary from the public listing
/// (`hourly_booking`, API 0.33.0).
class HourlyOffer {
  const HourlyOffer({
    required this.enabled,
    required this.ratePerHour,
    required this.currency,
    required this.incrementMinutes,
  });

  static HourlyOffer? fromJson(Object? json) => json is Map<String, dynamic>
      ? HourlyOffer(
          enabled: json['enabled'] == true,
          ratePerHour: json['rate_per_hour'] as String? ?? '',
          currency: json['currency'] as String? ?? '',
          incrementMinutes: json['increment_minutes'] as int? ?? 60,
        )
      : null;

  final bool enabled;
  final String ratePerHour;
  final String currency;
  final int incrementMinutes;
}

typedef TimeRange = ({DateTime start, DateTime end});

TimeRange _range(Object? json) {
  final m = json as Map<String, dynamic>;
  return (
    start: DateTime.parse(m['start'] as String),
    end: DateTime.parse(m['end'] as String),
  );
}

class VenueDay {
  const VenueDay({
    required this.date,
    required this.closed,
    required this.open,
    required this.booked,
    this.note,
  });

  final String date;
  final bool closed;
  final String? note;
  final List<TimeRange> open;
  final List<TimeRange> booked;

  bool get bookable => !closed && open.isNotEmpty;
}

/// When a venue can be booked (`GET /v1/venues/{id}/availability`).
class VenueAvailability {
  const VenueAvailability({
    required this.timeZone,
    required this.currency,
    required this.ratePerHour,
    required this.incrementMinutes,
    required this.minMinutes,
    required this.maxMinutes,
    required this.days,
    this.deposit,
    this.depositNote = 'payable to the host if confirmed',
    this.cancellationPolicy = '',
    this.freeCancellationHours = 24,
    this.notice = venueNoPaymentNotice,
  });

  factory VenueAvailability.fromJson(
    Map<String, dynamic> json,
  ) => VenueAvailability(
    timeZone: json['time_zone'] as String? ?? 'UTC',
    currency: json['currency'] as String? ?? '',
    ratePerHour: json['rate_per_hour'] as String? ?? '',
    deposit: json['deposit'] as String?,
    depositNote:
        json['deposit_note'] as String? ?? 'payable to the host if confirmed',
    incrementMinutes: json['increment_minutes'] as int? ?? 60,
    minMinutes: json['min_minutes'] as int? ?? 60,
    maxMinutes: json['max_minutes'] as int? ?? 480,
    cancellationPolicy: json['cancellation_policy'] as String? ?? '',
    freeCancellationHours: json['free_cancellation_hours'] as int? ?? 24,
    notice: json['notice'] as String? ?? venueNoPaymentNotice,
    days: [
      for (final d in (json['days'] as List?) ?? const [])
        VenueDay(
          date: (d as Map<String, dynamic>)['date'] as String,
          closed: d['closed'] == true,
          note: d['note'] as String?,
          open: [
            for (final r in (d['open_ranges'] as List?) ?? const []) _range(r),
          ],
          booked: [
            for (final r in (d['booked'] as List?) ?? const []) _range(r),
          ],
        ),
    ],
  );

  final String timeZone;
  final String currency;
  final String ratePerHour;
  final String? deposit;
  final String depositNote;
  final int incrementMinutes;
  final int minMinutes;
  final int maxMinutes;
  final String cancellationPolicy;
  final int freeCancellationHours;
  final String notice;
  final List<VenueDay> days;

  Duration get _step => Duration(minutes: incrementMinutes);

  static bool _overlaps(DateTime s, DateTime e, TimeRange r) =>
      s.isBefore(r.end) && e.isAfter(r.start);

  bool _free(VenueDay day, DateTime start, DateTime end) =>
      day.open.any((r) => !start.isBefore(r.start) && !end.isAfter(r.end)) &&
      !day.booked.any((r) => _overlaps(start, end, r));

  /// Start times on the increment at which at least the minimum duration
  /// is free (inside one opening range, overlapping no booked time).
  List<DateTime> starts(VenueDay day) => [
    for (final r in day.open)
      for (
        var t = r.start;
        !t.add(Duration(minutes: minMinutes)).isAfter(r.end);
        t = t.add(_step)
      )
        if (_free(day, t, t.add(Duration(minutes: minMinutes)))) t,
  ];

  /// Durations (in minutes) that fit from [start].
  List<int> durations(VenueDay day, DateTime start) => [
    for (var m = minMinutes; m <= maxMinutes; m += incrementMinutes)
      if (_free(day, start, start.add(Duration(minutes: m)))) m,
  ];
}

typedef QuoteLine = ({String code, String kind, String label, String amount});

/// An estimate for one slot (`Quote`): itemised, in one currency.
class VenueQuote {
  const VenueQuote({
    required this.id,
    required this.currency,
    required this.lines,
    required this.subtotal,
    required this.total,
    required this.start,
    required this.end,
    required this.durationMinutes,
    required this.timeZone,
    this.deposit,
    this.depositNote = 'payable to the host if confirmed',
    this.notice = venueNoPaymentNotice,
  });

  factory VenueQuote.fromJson(Map<String, dynamic> json) => VenueQuote(
    id: json['quote_id'] as String? ?? '',
    currency: json['currency'] as String,
    lines: [
      for (final l in (json['lines'] as List?) ?? const [])
        (
          code: (l as Map<String, dynamic>)['code'] as String? ?? '',
          kind: l['kind'] as String? ?? '',
          label: l['label'] as String? ?? '',
          amount: l['amount'] as String? ?? '',
        ),
    ],
    subtotal: json['subtotal'] as String? ?? '',
    deposit: json['deposit'] as String?,
    depositNote:
        json['deposit_note'] as String? ?? 'payable to the host if confirmed',
    total: json['total_excluding_deposit'] as String? ?? '',
    start: DateTime.parse(json['start'] as String? ?? '1970-01-01T00:00:00Z'),
    end: DateTime.parse(json['end'] as String? ?? '1970-01-01T00:00:00Z'),
    durationMinutes: json['duration_minutes'] as int? ?? 0,
    timeZone: json['time_zone'] as String? ?? 'UTC',
    notice: json['notice'] as String? ?? venueNoPaymentNotice,
  );

  final String id;
  final String currency;
  final List<QuoteLine> lines;
  final String subtotal;
  final String? deposit;
  final String depositNote;
  final String total;
  final DateTime start;
  final DateTime end;
  final int durationMinutes;
  final String timeZone;
  final String notice;

  /// The rate and the fixed and per-hour fees, which make the subtotal.
  List<QuoteLine> get beforeSubtotal => [
    for (final l in lines)
      if (l.kind != 'PERCENT') l,
  ];

  /// Percentage fees such as VAT, charged on the subtotal.
  List<QuoteLine> get onSubtotal => [
    for (final l in lines)
      if (l.kind == 'PERCENT') l,
  ];
}

/// An hourly booking request (`VenueBooking`).
class VenueBooking {
  const VenueBooking({
    required this.id,
    required this.reference,
    required this.status,
    required this.statusLabel,
    required this.listingTitle,
    required this.start,
    required this.end,
    required this.timeZone,
    required this.quote,
    this.listingSlug,
    this.attendees,
    this.message,
    this.policy = '',
    this.freeUntil,
    this.proposal,
    this.declineReason,
    this.cancellation,
    this.actions = const [],
    this.customerName,
    this.customerEmail,
    this.events = const [],
  });

  factory VenueBooking.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>? ?? const {};
    final policy = json['cancellation_policy'] as Map<String, dynamic>?;
    final proposal = json['proposal'] as Map<String, dynamic>?;
    final cancellation = json['cancellation'] as Map<String, dynamic>?;
    final customer = json['customer'] as Map<String, dynamic>?;
    final quote = json['quote'] as Map<String, dynamic>? ?? const {};
    return VenueBooking(
      id: json['id'] as String,
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String,
      statusLabel: json['status_label'] as String? ?? json['status'] as String,
      listingTitle: listing['title'] as String? ?? 'Venue',
      listingSlug: listing['slug'] as String?,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      timeZone: json['time_zone'] as String? ?? 'UTC',
      attendees: json['attendees'] as int?,
      message: json['message'] as String?,
      quote: VenueQuote.fromJson({
        ...quote,
        'start': json['start'],
        'end': json['end'],
        'time_zone': json['time_zone'],
        'duration_minutes': json['duration_minutes'],
        'notice': json['notice'],
        'deposit_note': json['deposit_note'],
        'currency': quote['currency'] ?? '',
      }),
      policy: policy?['text'] as String? ?? '',
      freeUntil: switch (policy?['free_until']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      proposal: proposal == null
          ? null
          : (
              by: proposal['proposed_by'] as String? ?? '',
              start: DateTime.parse(proposal['start'] as String),
              end: DateTime.parse(proposal['end'] as String),
            ),
      declineReason: json['decline_reason'] as String?,
      cancellation: cancellation == null
          ? null
          : (
              by: cancellation['by'] as String? ?? '',
              reason: cancellation['reason'] as String?,
              free: cancellation['free'] == true,
            ),
      actions: (json['actions'] as List?)?.cast<String>() ?? const [],
      customerName: customer?['name'] as String?,
      customerEmail: customer?['email'] as String?,
      events: [
        for (final e in (json['events'] as List?) ?? const [])
          (
            action: (e as Map<String, dynamic>)['action'] as String? ?? '',
            actor: e['actor'] as String? ?? '',
            actorName: e['actor_name'] as String?,
            reason: e['reason'] as String?,
            at: DateTime.parse(e['at'] as String),
          ),
      ],
    );
  }

  final String id;

  /// VB-...
  final String reference;
  final String status;
  final String statusLabel;
  final String listingTitle;
  final String? listingSlug;
  final DateTime start;
  final DateTime end;
  final String timeZone;
  final int? attendees;
  final String? message;
  final VenueQuote quote;
  final String policy;

  /// Free cancellation until then.
  final DateTime? freeUntil;
  final ({String by, DateTime start, DateTime end})? proposal;
  final String? declineReason;
  final ({String by, String? reason, bool free})? cancellation;

  /// What may be done now: customer cancel, reschedule, accept; host
  /// confirm, decline, propose, cancel, complete, no_show.
  final List<String> actions;
  final String? customerName;
  final String? customerEmail;
  final List<
    ({
      String action,
      String actor,
      String? actorName,
      String? reason,
      DateTime at,
    })
  >
  events;
}

/// Plain words for a slot the API says is unavailable.
String slotProblem(ApiFailure failure) => switch (failure.code) {
  'SLOT_UNAVAILABLE' => switch (failure.details['reason']) {
    'CLOSED' => 'The venue is closed then. Choose another time.',
    'TAKEN' => 'That time has just been booked. Choose another time.',
    'BUFFER' => 'That time is too close to another booking (the venue needs time to clean). Choose another time.',
    'LEAD_TIME' => 'That is too soon to book. Choose a later time.',
    'OUTSIDE_HORIZON' => 'That is too far ahead to book yet.',
    _ => 'That time is not available. Choose another time.',
  },
  'SLOT_TAKEN' => 'Another booking for that time has already been confirmed, so this one cannot be. Propose another time or decline it.',
  'QUOTE_EXPIRED' => 'The estimate expired. Check the time again.',
  'INVALID_BOOKING_TRANSITION' => 'This booking has changed since you opened it. Refresh to see where it stands.',
  _ => failure.message,
};

/// Hourly venue bookings (API 0.33.0). Request mode only: no payment is
/// taken or implied anywhere.
class VenueRepository {
  VenueRepository(this._api);

  final ApiClient _api;

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The next [days] days (the API allows 62 at most).
  Future<VenueAvailability> availability(
    String listingId, {
    required DateTime from,
    int days = 62,
  }) async => VenueAvailability.fromJson(
    (await _api.get(
      '/v1/venues/${Uri.encodeComponent(listingId)}/availability'
      '?from=${_date(from)}&to=${_date(from.add(Duration(days: days - 1)))}',
    )).body,
  );

  /// Throws [ApiFailure]; see [slotProblem] for the words.
  Future<VenueQuote> quote(
    String listingId,
    DateTime start,
    DateTime end,
  ) async => VenueQuote.fromJson(
    (await _api.postJson(
      '/v1/venues/${Uri.encodeComponent(listingId)}/quotes',
      {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    )).body,
  );

  Future<VenueBooking> request(
    String quoteId, {
    String? message,
    int? attendees,
    required String privacyVersion,
  }) async => VenueBooking.fromJson(
    (await _api.postJson('/v1/me/venue-bookings', {
      'quote_id': quoteId,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      'attendees': ?attendees,
      'consent': {'privacy_version': privacyVersion, 'accepted': true},
    })).body,
  );

  Future<List<VenueBooking>> mine() async => [
    for (final b
        in ((await _api.get('/v1/me/venue-bookings?page_size=50')).body['items']
                as List?) ??
            const [])
      VenueBooking.fromJson(b as Map<String, dynamic>),
  ];

  Future<VenueBooking> myBooking(String id) async => VenueBooking.fromJson(
    (await _api.get('/v1/me/venue-bookings/${Uri.encodeComponent(id)}')).body,
  );

  Future<VenueBooking> cancelMine(
    String id, {
    String? reason,
  }) async => VenueBooking.fromJson(
    (await _api.postJson(
      '/v1/me/venue-bookings/${Uri.encodeComponent(id)}/cancel',
      {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    )).body,
  );

  Future<VenueBooking> acceptProposal(String id) async => VenueBooking.fromJson(
    (await _api.post('/v1/me/venue-bookings/${Uri.encodeComponent(id)}/accept'))
        .body,
  );

  /// The host's base path: an organisation's, or a direct owner's own
  /// The calendar file (`.ics`) of the customer's own booking.
  Future<List<int>> myCalendarFile(String id) => _api.getBytes(
    '/v1/me/venue-bookings/${Uri.encodeComponent(id)}/calendar.ics',
  );

  /// The calendar file (`.ics`) of a booking the book hosts.
  Future<List<int>> hostedCalendarFile(
    String book,
    String id, {
    bool personal = false,
  }) => _api.getBytes(
    '${_host(book, personal)}/${Uri.encodeComponent(id)}/calendar.ics',
  );

  /// (`personal`).
  String _host(String book, bool personal) => personal
      ? '/v1/me/hosted-venue-bookings'
      : '/v1/agent/organisations/${Uri.encodeComponent(book)}/venue-bookings';

  Future<List<VenueBooking>> hosted(
    String book, {
    bool personal = false,
    String? status,
  }) async => [
    for (final b
        in ((await _api.get(
                  Uri(
                    path: _host(book, personal),
                    queryParameters: {'status': ?status, 'page_size': '50'},
                  ).toString(),
                )).body['items']
                as List?) ??
            const [])
      VenueBooking.fromJson(b as Map<String, dynamic>),
  ];

  Future<VenueBooking> hostedBooking(
    String book,
    String id, {
    bool personal = false,
  }) async => VenueBooking.fromJson(
    (await _api.get('${_host(book, personal)}/${Uri.encodeComponent(id)}'))
        .body,
  );

  /// confirm, decline, cancel, complete or no-show. [reason] is required to
  /// decline and cancel.
  Future<VenueBooking> hostAction(
    String book,
    String id,
    String action, {
    bool personal = false,
    String? reason,
  }) async => VenueBooking.fromJson(
    (await _api.postJson(
      '${_host(book, personal)}/${Uri.encodeComponent(id)}/${action == 'no_show' ? 'no-show' : action}',
      {if (reason != null) 'reason': reason.trim()},
    )).body,
  );
}
