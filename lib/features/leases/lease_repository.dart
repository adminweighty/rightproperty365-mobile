import 'dart:typed_data';

import '../../core/api/api_client.dart';

DateTime? _at(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Lease status wording, as on the website.
String leaseStatusLabel(String status) => switch (status) {
  'DRAFT' => 'Draft',
  'SENT_FOR_SIGNING' => 'Out for signing',
  'SIGNED' => 'Signed',
  'DECLINED' => 'Declined',
  'CANCELLED' => 'Cancelled',
  'EXPIRED' => 'Expired',
  _ => status,
};

String rentPeriodLabel(String period) => switch (period) {
  'MONTHLY' => 'per month',
  'WEEKLY' => 'per week',
  'ANNUALLY' => 'per year',
  _ => period.toLowerCase(),
};

const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// What the audit trail says for each event.
String leaseEventLabel(String action) => switch (action) {
  'CREATED' => 'Created',
  'EDITED' => 'Edited',
  'PDF_GENERATED' => 'PDF made',
  'SENT' => 'Sent for signing',
  'SIGNED' => 'Signed by everyone',
  'DECLINED' => 'Declined',
  'CANCELLED' => 'Cancelled',
  'EXPIRED' => 'Expired',
  _ =>
    action.isEmpty
        ? action
        : action[0] + action.substring(1).toLowerCase().replaceAll('_', ' '),
};

/// Plain words for lease and signing failures; other codes keep the API's.
String leaseMessage(ApiFailure failure) => switch (failure.code) {
  'FORBIDDEN' => 'Only people who manage listings (and their agency principal or administrators) can do this.',
  'LEASE_NOT_FOUND' =>
    'We could not find that lease, or you no longer have access to it.',
  'LISTING_NOT_FOUND' =>
    'That listing is not one you can use. Choose another or type the address.',
  'LEASE_DOCUMENT_UNAVAILABLE' =>
    'The PDF is not ready yet. Try again in a moment.',
  'LEASE_NOT_EDITABLE' =>
    'This lease was already sent, so it can no longer be changed.',
  'LEASE_STATE_CONFLICT' =>
    'This lease has moved on since you opened it. It has been loaded again.',
  'LEASE_TEMPLATE_NOT_AVAILABLE' =>
    'That template is no longer offered. Choose another one.',
  'LEASE_MARKET_MISMATCH' => "That template is for another country than the property. Choose a template for the property's country.",
  _ => failure.message,
};

class LeaseClause {
  const LeaseClause(this.code, this.title, this.text);
  final String code;
  final String title;
  final String text;
}

/// An approved template a lease can be drafted from.
class LeaseTemplate {
  const LeaseTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.marketCode,
    required this.leaseKind,
    this.description,
    this.optionalClauses = const [],
    this.reviewedBy,
    this.source = 'SAMPLE',
    this.organisationId,
    this.canEdit = false,
  });

  factory LeaseTemplate.fromJson(Map<String, dynamic> json) {
    final review = json['legal_review'];
    return LeaseTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as int? ?? 1,
      marketCode: json['market_code'] as String? ?? '',
      leaseKind: json['lease_kind'] as String? ?? '',
      description: json['description'] as String?,
      optionalClauses: [
        for (final c in (json['optional_clauses'] as List?) ?? const [])
          LeaseClause(
            c['code'] as String,
            c['title'] as String,
            c['text'] as String? ?? '',
          ),
      ],
      reviewedBy: review is Map
          ? '${review['reviewer_name']}, ${review['organisation']}'
          : null,
      source: json['source'] as String? ?? 'SAMPLE',
      organisationId: json['organisation_id'] as String?,
      canEdit: json['can_edit'] == true,
    );
  }

  final String id;
  final String name;
  final int version;
  final String marketCode;
  final String leaseKind;
  final String? description;
  final List<LeaseClause> optionalClauses;

  /// Who reviewed the wording, when the template records a review.
  final String? reviewedBy;

  /// SAMPLE (the platform's starting points) or ORGANISATION (one of the
  /// caller's organisations' own published templates).
  final String source;
  final String? organisationId;
  final bool canEdit;

  bool get sample => source != 'ORGANISATION';
}

/// One of the caller's listings, to attach a lease to.
class LeaseListing {
  const LeaseListing({
    required this.id,
    required this.title,
    required this.reference,
    required this.countryCode,
    this.city,
    this.currency,
  });

  factory LeaseListing.fromJson(Map<String, dynamic> json) {
    String? name(Object? place) => switch (place) {
      final String s => s,
      {'name': final String s} => s,
      _ => null,
    };
    final country = json['country'];
    return LeaseListing(
      id: json['id'] as String,
      title: json['title'] as String,
      reference: json['reference'] as String? ?? '',
      countryCode: switch (country) {
        {'code': final String code} => code,
        final String code => code,
        _ => '',
      },
      city: name(json['city']),
      currency:
          (json['price'] as Map<String, dynamic>?)?['currency'] as String?,
    );
  }

  final String id;
  final String title;
  final String reference;
  final String countryCode;
  final String? city;
  final String? currency;
}

class LeaseParty {
  const LeaseParty({required this.name, required this.email, this.phone});

  factory LeaseParty.fromJson(Map<String, dynamic> json) => LeaseParty(
    name: json['name'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String?,
  );

  final String name;
  final String email;
  final String? phone;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': email.trim(),
    if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
  };
}

/// What a lease form sends (`LeaseInput`).
class LeaseDraft {
  const LeaseDraft({
    required this.templateId,
    this.listingId,
    this.organisationId,
    this.propertyAddress,
    required this.landlords,
    required this.tenants,
    required this.startDate,
    this.endDate,
    this.periodic = false,
    required this.rentAmount,
    required this.rentCurrency,
    required this.rentPeriod,
    required this.paymentDay,
    this.depositAmount,
    required this.noticePeriodDays,
    this.optionalClauses = const [],
    this.specialConditions,
    this.landlordStamp = false,
  });

  final String templateId;
  final String? listingId;
  final String? organisationId;
  final String? propertyAddress;
  final List<LeaseParty> landlords;
  final List<LeaseParty> tenants;
  final DateTime startDate;
  final DateTime? endDate;
  final bool periodic;
  final String rentAmount;
  final String rentCurrency;
  final String rentPeriod;
  final int paymentDay;
  final String? depositAmount;
  final int noticePeriodDays;
  final List<String> optionalClauses;
  final String? specialConditions;

  /// Each landlord also adds a company stamp next to their signature.
  final bool landlordStamp;

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [creating] adds the keys that cannot change after the lease exists.
  Map<String, dynamic> toJson({required bool creating}) => {
    'template_id': templateId,
    if (creating) 'listing_id': ?listingId,
    if (creating) 'organisation_id': ?organisationId,
    if (propertyAddress != null && propertyAddress!.trim().isNotEmpty)
      'property_address': propertyAddress!.trim(),
    'landlords': [for (final p in landlords) p.toJson()],
    'tenants': [for (final p in tenants) p.toJson()],
    'start_date': date(startDate),
    if (!periodic && endDate != null) 'end_date': date(endDate!),
    'periodic': periodic,
    'rent_amount': rentAmount.trim(),
    'rent_currency': rentCurrency.trim().toUpperCase(),
    'rent_period': rentPeriod,
    'payment_day': paymentDay,
    if (depositAmount != null && depositAmount!.trim().isNotEmpty)
      'deposit_amount': depositAmount!.trim(),
    'notice_period_days': noticePeriodDays,
    'optional_clauses': optionalClauses,
    'special_conditions': (specialConditions ?? '').trim(),
    'landlord_stamp': landlordStamp,
  };
}

class Lease {
  const Lease({
    required this.id,
    required this.reference,
    required this.status,
    required this.templateId,
    required this.templateName,
    required this.templateVersion,
    required this.marketCode,
    required this.propertyAddress,
    required this.landlords,
    required this.tenants,
    required this.startDate,
    required this.periodic,
    required this.rentAmount,
    required this.rentCurrency,
    required this.rentPeriod,
    required this.paymentDay,
    required this.noticePeriodDays,
    required this.createdAt,
    required this.createdBy,
    this.endDate,
    this.depositAmount,
    this.optionalClauses = const [],
    this.specialConditions,
    this.organisationName,
    this.listingId,
    this.listingTitle,
    this.agreementId,
    this.hasDocument = false,
    this.canEdit = false,
    this.canSend = false,
    this.canCancel = false,
    this.canDelete = false,
    this.sentAt,
    this.completedAt,
    this.cancelReason,
    this.landlordStamp = false,
  });

  factory Lease.fromJson(Map<String, dynamic> json) {
    final template = json['template'] as Map<String, dynamic>;
    final listing = json['listing'] as Map<String, dynamic>?;
    return Lease(
      id: json['id'] as String,
      reference: json['reference'] as String,
      status: json['status'] as String,
      templateId: template['id'] as String,
      templateName: template['name'] as String,
      templateVersion: template['version'] as int? ?? 1,
      marketCode: template['market_code'] as String? ?? '',
      organisationName:
          (json['organisation'] as Map<String, dynamic>?)?['name'] as String?,
      listingId: listing?['id'] as String?,
      listingTitle: listing?['title'] as String?,
      createdBy:
          (json['created_by'] as Map<String, dynamic>?)?['name'] as String? ??
          '',
      propertyAddress: json['property_address'] as String? ?? '',
      landlords: [
        for (final p in (json['landlords'] as List?) ?? const [])
          LeaseParty.fromJson(p as Map<String, dynamic>),
      ],
      tenants: [
        for (final p in (json['tenants'] as List?) ?? const [])
          LeaseParty.fromJson(p as Map<String, dynamic>),
      ],
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: _at(json['end_date']),
      periodic: json['periodic'] == true,
      rentAmount: json['rent_amount'] as String,
      rentCurrency: json['rent_currency'] as String,
      rentPeriod: json['rent_period'] as String,
      paymentDay: json['payment_day'] as int,
      depositAmount: json['deposit_amount'] as String?,
      noticePeriodDays: json['notice_period_days'] as int,
      optionalClauses: [
        for (final c in (json['optional_clauses'] as List?) ?? const [])
          c as String,
      ],
      specialConditions: json['special_conditions'] as String?,
      agreementId: json['agreement_id'] as String?,
      hasDocument: json['document'] != null,
      canEdit: json['can_edit'] == true,
      canSend: json['can_send'] == true,
      canCancel: json['can_cancel'] == true,
      canDelete: json['can_delete'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: _at(json['sent_at']),
      completedAt: _at(json['completed_at']),
      cancelReason: json['cancel_reason'] as String?,
      landlordStamp: json['landlord_stamp'] == true,
    );
  }

  final String id;
  final String reference;
  final String status;
  final String templateId;
  final String templateName;
  final int templateVersion;
  final String marketCode;
  final String? organisationName;
  final String? listingId;
  final String? listingTitle;
  final String createdBy;
  final String propertyAddress;
  final List<LeaseParty> landlords;
  final List<LeaseParty> tenants;
  final DateTime startDate;
  final DateTime? endDate;
  final bool periodic;
  final String rentAmount;
  final String rentCurrency;
  final String rentPeriod;
  final int paymentDay;
  final String? depositAmount;
  final int noticePeriodDays;
  final List<String> optionalClauses;
  final String? specialConditions;
  final String? agreementId;
  final bool hasDocument;
  final bool canEdit;
  final bool canSend;
  final bool canCancel;
  final bool canDelete;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? completedAt;
  final String? cancelReason;
  final bool landlordStamp;

  String get statusLabel => leaseStatusLabel(status);

  String get title => listingTitle ?? propertyAddress;

  /// "Day 1" of the month, or "Monday" for weekly rent.
  String get paymentDayLabel => rentPeriod == 'WEEKLY' && paymentDay <= 7
      ? weekdays[paymentDay - 1]
      : 'Day $paymentDay';

  /// The form's starting values for editing this draft.
  LeaseDraft toDraft() => LeaseDraft(
    templateId: templateId,
    propertyAddress: propertyAddress,
    landlords: landlords,
    tenants: tenants,
    startDate: startDate,
    endDate: endDate,
    periodic: periodic,
    rentAmount: rentAmount,
    rentCurrency: rentCurrency,
    rentPeriod: rentPeriod,
    paymentDay: paymentDay,
    depositAmount: depositAmount,
    noticePeriodDays: noticePeriodDays,
    optionalClauses: optionalClauses,
    specialConditions: specialConditions,
    landlordStamp: landlordStamp,
  );
}

class LeaseEvent {
  const LeaseEvent(this.action, this.actorName, this.at);

  factory LeaseEvent.fromJson(Map<String, dynamic> json) => LeaseEvent(
    json['action'] as String,
    (json['actor'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    DateTime.parse(json['at'] as String),
  );

  final String action;
  final String actorName;
  final DateTime at;
}

abstract interface class LeaseRepository {
  Future<List<Lease>> list({String? status});
  Future<Lease> get(String id);
  Future<List<LeaseTemplate>> templates({String? market});
  Future<List<LeaseListing>> listings();
  Future<Lease> create(LeaseDraft draft);
  Future<Lease> update(String id, LeaseDraft draft);
  Future<void> delete(String id);
  Future<Lease> send(String id, {String? message, String? reminders});
  Future<Lease> cancel(String id, {String? reason});
  Future<List<LeaseEvent>> events(String id);
  Future<Uint8List> pdf(String id);
}

class ApiLeaseRepository implements LeaseRepository {
  ApiLeaseRepository(this._api);

  final ApiClient _api;

  String _lease(String id) => '/v1/me/leases/${Uri.encodeComponent(id)}';

  Lease _one(ApiResponse r) =>
      Lease.fromJson(r.body['lease'] as Map<String, dynamic>);

  @override
  Future<List<Lease>> list({String? status}) async {
    final query = Uri(queryParameters: {'page_size': '100', 'status': ?status})
        .query;
    final body = (await _api.get('/v1/me/leases?$query')).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        Lease.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Lease> get(String id) async => _one(await _api.get(_lease(id)));

  @override
  Future<List<LeaseTemplate>> templates({String? market}) async {
    final body = (await _api.get(
      market == null
          ? '/v1/me/lease-templates'
          : '/v1/me/lease-templates?market=${Uri.encodeComponent(market)}',
    )).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        LeaseTemplate.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<LeaseListing>> listings() async {
    try {
      final body = (await _api.get('/v1/me/listings?page_size=48')).body;
      return [
        for (final item in (body['items'] as List?) ?? const [])
          // API 0.26.1: an agent may draft leases only for the listings they
          // may edit. Older answers have no can_edit and are all offered.
          if ((item as Map<String, dynamic>)['can_edit'] != false)
            LeaseListing.fromJson(item),
      ];
    } on ApiFailure catch (failure) {
      // No listings to choose from; the address can still be typed.
      if (failure.status == 403) return const [];
      rethrow;
    }
  }

  @override
  Future<Lease> create(LeaseDraft draft) async =>
      _one(await _api.postJson('/v1/me/leases', draft.toJson(creating: true)));

  @override
  Future<Lease> update(String id, LeaseDraft draft) async =>
      _one(await _api.patchJson(_lease(id), draft.toJson(creating: false)));

  @override
  Future<void> delete(String id) async {
    await _api.delete(_lease(id));
  }

  @override
  Future<Lease> send(String id, {String? message, String? reminders}) async =>
      _one(
        await _api.postJson('${_lease(id)}/send', {
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
          'reminder_frequency': ?reminders,
        }),
      );

  @override
  Future<Lease> cancel(String id, {String? reason}) async => _one(
    await _api.postJson('${_lease(id)}/cancel', {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    }),
  );

  @override
  Future<List<LeaseEvent>> events(String id) async {
    final body = (await _api.get('${_lease(id)}/events')).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        LeaseEvent.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Uint8List> pdf(String id) => _api.getBytes('${_lease(id)}/pdf');
}
