import 'dart:typed_data';

import '../../core/api/api_client.dart';
import 'properties_repository.dart' show Money, PartyRef;

/// Rent, part (b) (API 0.36.1): a tenancy's schedule of dues, the receipts
/// recorded against it, waivers, the tenant statement and arrears. A
/// tenancy has one currency (its rent's); every figure here carries its
/// currency and nothing adds two currencies together.

Money _money(Map<String, dynamic> json, String key) =>
    Money(json[key] as String? ?? '0', json['currency'] as String? ?? '');

class RentDue {
  const RentDue({
    required this.id,
    required this.dueDate,
    required this.periodFrom,
    required this.periodTo,
    required this.amount,
    required this.paid,
    required this.waived,
    required this.outstanding,
    required this.status,
    required this.statusLabel,
    this.overdue = false,
    this.daysOverdue = 0,
    this.waiverReason,
    this.canWaive = false,
  });

  factory RentDue.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? const {};
    final waiver = json['waiver'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    return RentDue(
      id: json['id'] as String,
      dueDate: json['due_date'] as String,
      periodFrom: period['from'] as String? ?? json['due_date'] as String,
      periodTo: period['to'] as String? ?? json['due_date'] as String,
      amount: _money(json, 'amount'),
      paid: _money(json, 'paid'),
      waived: _money(json, 'waived'),
      outstanding: _money(json, 'outstanding'),
      status: json['status'] as String? ?? 'DUE',
      statusLabel: json['status_label'] as String? ?? '',
      overdue: json['overdue'] as bool? ?? false,
      daysOverdue: json['days_overdue'] as int? ?? 0,
      waiverReason: waiver?['reason'] as String?,
      canWaive: can['waive'] as bool? ?? false,
    );
  }

  final String id;
  final String dueDate;
  final String periodFrom;
  final String periodTo;
  final Money amount;
  final Money paid;
  final Money waived;
  final Money outstanding;

  /// DUE, PART_PAID, PAID or WAIVED.
  final String status;
  final String statusLabel;
  final bool overdue;
  final int daysOverdue;

  /// Managers only; the tenant's view has no reason.
  final String? waiverReason;
  final bool canWaive;
}

class DueSummary {
  const DueSummary({
    required this.charged,
    required this.paid,
    required this.waived,
    required this.outstanding,
    required this.overdue,
    required this.overdueCount,
    required this.paidInAdvance,
    this.nextDue,
  });

  factory DueSummary.fromJson(Map<String, dynamic> json) => DueSummary(
    charged: _money(json, 'charged'),
    paid: _money(json, 'paid'),
    waived: _money(json, 'waived'),
    outstanding: _money(json, 'outstanding'),
    overdue: _money(json, 'overdue'),
    overdueCount: json['overdue_count'] as int? ?? 0,
    paidInAdvance: _money(json, 'paid_in_advance'),
    nextDue: switch (json['next_due']) {
      final Map<String, dynamic> due => RentDue.fromJson(due),
      _ => null,
    },
  );

  final Money charged;
  final Money paid;
  final Money waived;
  final Money outstanding;
  final Money overdue;
  final int overdueCount;
  final Money paidInAdvance;
  final RentDue? nextDue;
}

class RentSchedule {
  const RentSchedule({
    required this.dues,
    required this.summary,
    this.rule,
    this.through,
    this.rolling = false,
  });

  factory RentSchedule.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'] as Map<String, dynamic>?;
    return RentSchedule(
      dues: [
        for (final d in json['items'] as List? ?? const [])
          RentDue.fromJson(d as Map<String, dynamic>),
      ],
      summary: DueSummary.fromJson(json['summary'] as Map<String, dynamic>),
      rule: schedule?['rule'] as String?,
      through: schedule?['through'] as String?,
      rolling: schedule?['rolling'] as bool? ?? false,
    );
  }

  final List<RentDue> dues;
  final DueSummary summary;

  /// For example "Monthly on day 1"; null for a draft (no schedule yet).
  final String? rule;
  final String? through;
  final bool rolling;
}

class RentAllocation {
  const RentAllocation(this.dueDate, this.amount);

  factory RentAllocation.fromJson(Map<String, dynamic> json) =>
      RentAllocation(json['due_date'] as String? ?? '', _money(json, 'amount'));

  final String dueDate;
  final Money amount;
}

class RentReceipt {
  const RentReceipt({
    required this.id,
    required this.amount,
    required this.methodLabel,
    required this.receivedOn,
    required this.status,
    required this.statusLabel,
    required this.allocations,
    this.reference,
    this.tenant,
    this.ledgerEntryId,
    this.ledgerStatusLabel,
    this.reversedOn,
    this.canReverse = false,
  });

  /// The manager's and the tenant's shapes.
  factory RentReceipt.fromJson(Map<String, dynamic> json) {
    final reversal = json['reversal'] as Map<String, dynamic>?;
    final tenant = json['tenant'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    final reference = json['reference'] as String?;
    return RentReceipt(
      id: json['id'] as String,
      amount: _money(json, 'amount'),
      methodLabel: json['method_label'] as String? ?? '',
      receivedOn: json['received_on'] as String,
      reference: reference == null || reference.isEmpty ? null : reference,
      tenant: tenant == null ? null : PartyRef.fromJson(tenant),
      status: json['status'] as String? ?? 'RECORDED',
      statusLabel: json['status_label'] as String? ?? '',
      allocations: [
        for (final a in json['allocations'] as List? ?? const [])
          RentAllocation.fromJson(a as Map<String, dynamic>),
      ],
      ledgerEntryId: json['ledger_entry_id'] as String?,
      ledgerStatusLabel: json['ledger_status_label'] as String?,
      reversedOn:
          reversal?['reversed_on'] as String? ?? json['reversed_on'] as String?,
      canReverse: can['reverse'] as bool? ?? false,
    );
  }

  final String id;
  final Money amount;
  final String methodLabel;
  final String receivedOn;
  final String? reference;
  final PartyRef? tenant;

  /// RECORDED or REVERSED.
  final String status;
  final String statusLabel;

  /// Kept after a reversal, when they no longer count.
  final List<RentAllocation> allocations;
  final String? ledgerEntryId;

  /// The ledger's own wording: "Recorded by you, not verified" or
  /// "Marked reconciled by your team".
  final String? ledgerStatusLabel;
  final String? reversedOn;
  final bool canReverse;

  bool get reversed => status == 'REVERSED';
}

class StatementLine {
  const StatementLine({
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.reference,
  });

  factory StatementLine.fromJson(Map<String, dynamic> json) => StatementLine(
    date: json['date'] as String,
    type: json['type'] as String? ?? '',
    description: json['description'] as String? ?? '',
    reference: switch (json['reference']) {
      final String r when r.isNotEmpty => r,
      _ => null,
    },
    debit: _money(json, 'debit'),
    credit: _money(json, 'credit'),
    balance: _money(json, 'balance'),
  );

  final String date;

  /// CHARGE, PAYMENT, PAYMENT_REVERSED or WAIVER.
  final String type;
  final String description;
  final String? reference;
  final Money debit;
  final Money credit;

  /// Positive: the tenant owes; negative: in credit.
  final Money balance;
}

class StatementCurrency {
  const StatementCurrency({
    required this.currency,
    required this.opening,
    required this.charged,
    required this.paid,
    required this.reversed,
    required this.waived,
    required this.closing,
    required this.overdue,
    required this.lines,
  });

  factory StatementCurrency.fromJson(Map<String, dynamic> json) =>
      StatementCurrency(
        currency: json['currency'] as String,
        opening: _money(json, 'opening_balance'),
        charged: _money(json, 'charged'),
        paid: _money(json, 'paid'),
        reversed: _money(json, 'reversed'),
        waived: _money(json, 'waived'),
        closing: _money(json, 'closing_balance'),
        overdue: _money(json, 'overdue'),
        lines: [
          for (final l in json['lines'] as List? ?? const [])
            StatementLine.fromJson(l as Map<String, dynamic>),
        ],
      );

  final String currency;
  final Money opening;
  final Money charged;
  final Money paid;
  final Money reversed;
  final Money waived;
  final Money closing;
  final Money overdue;
  final List<StatementLine> lines;
}

class RentStatement {
  const RentStatement({
    required this.from,
    required this.to,
    required this.currencies,
  });

  factory RentStatement.fromJson(Map<String, dynamic> json) => RentStatement(
    from: json['from'] as String,
    to: json['to'] as String,
    currencies: [
      for (final c in json['currencies'] as List? ?? const [])
        StatementCurrency.fromJson(c as Map<String, dynamic>),
    ],
  );

  final String from;
  final String to;

  /// One table per currency; empty with no dues or receipts.
  final List<StatementCurrency> currencies;
}

class AgeBucket {
  const AgeBucket(this.bucket, this.outstanding, this.count);

  factory AgeBucket.fromJson(Map<String, dynamic> json) => AgeBucket(
    json['bucket'] as String,
    _money(json, 'outstanding'),
    json['count'] as int? ?? 0,
  );

  /// 0-30, 31-60, 61-90 or 90+ days overdue.
  final String bucket;
  final Money outstanding;
  final int count;

  String get label => '$bucket days';
}

class TenancyArrears {
  const TenancyArrears({
    required this.tenancyId,
    required this.place,
    required this.tenants,
    required this.outstanding,
    required this.count,
    required this.oldestDueDate,
    required this.daysOverdue,
  });

  factory TenancyArrears.fromJson(Map<String, dynamic> json) {
    final t = json['tenancy'] as Map<String, dynamic>;
    final property = t['property'] as Map<String, dynamic>? ?? const {};
    final unit = t['unit'] as Map<String, dynamic>?;
    final name = property['name'] as String? ?? '';
    return TenancyArrears(
      tenancyId: t['id'] as String,
      place: unit == null ? name : '$name, ${unit['label']}',
      tenants: [
        for (final p in t['tenants'] as List? ?? const [])
          (p as Map<String, dynamic>)['name'] as String? ?? '',
      ].join(', '),
      outstanding: _money(json, 'outstanding'),
      count: json['count'] as int? ?? 0,
      oldestDueDate: json['oldest_due_date'] as String? ?? '',
      daysOverdue: json['days_overdue'] as int? ?? 0,
    );
  }

  final String tenancyId;
  final String place;
  final String tenants;
  final Money outstanding;
  final int count;
  final String oldestDueDate;
  final int daysOverdue;
}

class CurrencyArrears {
  const CurrencyArrears({
    required this.currency,
    required this.outstanding,
    required this.count,
    required this.buckets,
    required this.tenancies,
  });

  factory CurrencyArrears.fromJson(Map<String, dynamic> json) =>
      CurrencyArrears(
        currency: json['currency'] as String,
        outstanding: _money(json, 'outstanding'),
        count: json['count'] as int? ?? 0,
        buckets: [
          for (final b in json['buckets'] as List? ?? const [])
            AgeBucket.fromJson(b as Map<String, dynamic>),
        ],
        tenancies: [
          for (final t in json['tenancies'] as List? ?? const [])
            TenancyArrears.fromJson(t as Map<String, dynamic>),
        ],
      );

  final String currency;
  final Money outstanding;
  final int count;
  final List<AgeBucket> buckets;
  final List<TenancyArrears> tenancies;
}

/// Where a tenancy's rent is read from: the manager's book, or the tenant's
/// own (`/v1/me/tenancies`), which answers 404 for anybody else's.
class RentScope {
  const RentScope.manager(String this.book, this.tenancyId);
  const RentScope.tenant(this.tenancyId) : book = null;

  /// Null for the tenant's own view.
  final String? book;
  final String tenancyId;

  bool get tenant => book == null;

  String get path => tenant
      ? '/v1/me/tenancies/${Uri.encodeComponent(tenancyId)}'
      : '/v1/agent/organisations/${Uri.encodeComponent(book!)}/tenancies/${Uri.encodeComponent(tenancyId)}';
}

/// What a receipt was recorded against.
typedef RecordedReceipt = ({RentReceipt receipt, List<RentDue> dues});

class RentRepository {
  RentRepository(this._api);

  final ApiClient _api;

  String _org(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}';

  Future<RentSchedule> schedule(RentScope scope, {String? status}) async =>
      RentSchedule.fromJson(
        (await _api.get(
          Uri(
            path: '${scope.path}/dues',
            queryParameters: {'status': ?status},
          ).toString(),
        )).body,
      );

  Future<List<RentReceipt>> receipts(RentScope scope) async => [
    for (final r
        in (await _api.get('${scope.path}/receipts')).body['items'] as List? ??
            const [])
      RentReceipt.fromJson(r as Map<String, dynamic>),
  ];

  Future<RentStatement> statement(
    RentScope scope, {
    String? from,
    String? to,
  }) async => RentStatement.fromJson(
    (await _api.get(
      Uri(
        path: '${scope.path}/statement',
        queryParameters: {'from': ?from, 'to': ?to},
      ).toString(),
    )).body,
  );

  /// The same statement as a PDF, to show in the app.
  Future<Uint8List> statementPdf(RentScope scope, {String? from, String? to}) =>
      _api.getBytes(
        Uri(
          path: '${scope.path}/statement',
          queryParameters: {'from': ?from, 'to': ?to, 'format': 'pdf'},
        ).toString(),
      );

  /// Records rent received. The currency must be the rent's; without
  /// allocations the amount goes to the oldest dues first. Writes one ledger
  /// entry, "Recorded by you, not verified".
  Future<RecordedReceipt> record(
    String book,
    String tenancyId, {
    required String amount,
    required String currency,
    required String method,
    required String receivedOn,
    String? reference,
    String? tenantContactId,
  }) async {
    try {
      final body = (await _api.postJson(
        '${_org(book)}/tenancies/${Uri.encodeComponent(tenancyId)}/receipts',
        {
          'amount': amount.trim(),
          'currency': currency,
          'method': method,
          'received_on': receivedOn,
          if (reference != null && reference.trim().isNotEmpty)
            'reference': reference.trim(),
          'tenant_contact_id': ?tenantContactId,
        },
      )).body;
      return (
        receipt: RentReceipt.fromJson(body['receipt'] as Map<String, dynamic>),
        dues: [
          for (final d in body['dues'] as List? ?? const [])
            RentDue.fromJson(d as Map<String, dynamic>),
        ],
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'RENT_DUE_CHANGED') {
        throw failure.withMessage(
          'The schedule changed while you were recording. Check it and try '
          'again.',
        );
      }
      rethrow;
    }
  }

  /// Forgives what is outstanding on a due.
  Future<RentDue> waive(String book, String dueId, String reason) async {
    try {
      return RentDue.fromJson(
        (await _api.postJson(
              '${_org(book)}/dues/${Uri.encodeComponent(dueId)}/waive',
              {'reason': reason.trim()},
            )).body['due']
            as Map<String, dynamic>,
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'RENT_DUE_NOT_WAIVABLE') {
        throw failure.withMessage(
          'This due is already paid or waived, so there is nothing to waive.',
        );
      }
      rethrow;
    }
  }

  /// Arrears by age, one table per currency.
  Future<({String asOf, List<CurrencyArrears> currencies})> arrears(
    String book,
  ) async {
    final body = (await _api.get('${_org(book)}/arrears')).body;
    return (
      asOf: body['as_of'] as String? ?? '',
      currencies: [
        for (final c in body['currencies'] as List? ?? const [])
          CurrencyArrears.fromJson(c as Map<String, dynamic>),
      ],
    );
  }
}
