import '../../core/api/api_client.dart';

/// Property management, part (a) (API 0.36.0): properties with units, and
/// tenancies, kept in the same book as the CRM and the ledger (an
/// organisation, or an approved direct owner's own). Money is a decimal
/// string in one currency; amounts in different currencies are never added.

class PropertyUnit {
  const PropertyUnit({
    required this.id,
    required this.label,
    this.activeTenancyId,
  });

  factory PropertyUnit.fromJson(Map<String, dynamic> json) => PropertyUnit(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    activeTenancyId: json['active_tenancy_id'] as String?,
  );

  final String id;
  final String label;
  final String? activeTenancyId;

  bool get occupied => activeTenancyId != null;
}

class ManagedProperty {
  const ManagedProperty({
    required this.id,
    required this.name,
    required this.address,
    required this.marketCode,
    required this.units,
    required this.lettableUnits,
    required this.occupiedUnits,
    required this.openTenancies,
    this.notes = '',
    this.listingTitle,
    this.listingReference,
    this.activeTenancyId,
    this.canEdit = false,
    this.canDelete = false,
  });

  factory ManagedProperty.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    return ManagedProperty(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      marketCode: json['market_code'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      listingTitle: listing?['title'] as String?,
      listingReference: listing?['reference'] as String?,
      units: [
        for (final u in json['units'] as List? ?? const [])
          PropertyUnit.fromJson(u as Map<String, dynamic>),
      ],
      lettableUnits: json['lettable_units'] as int? ?? 1,
      occupiedUnits: json['occupied_units'] as int? ?? 0,
      openTenancies: json['open_tenancies'] as int? ?? 0,
      activeTenancyId: json['active_tenancy_id'] as String?,
      canEdit: can['edit'] as bool? ?? false,
      canDelete: can['delete'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String address;
  final String marketCode;
  final String notes;
  final String? listingTitle;
  final String? listingReference;
  final List<PropertyUnit> units;

  /// A property with no units counts as one.
  final int lettableUnits;
  final int occupiedUnits;

  /// Draft and active tenancies.
  final int openTenancies;

  /// The active tenancy of the whole property (one with no unit).
  final String? activeTenancyId;
  final bool canEdit;
  final bool canDelete;

  String get occupancy => units.isEmpty
      ? (occupiedUnits > 0 ? 'Let' : 'Vacant')
      : '$occupiedUnits of $lettableUnits units let';
}

/// A rent or deposit: one currency, the amount as the API gives it.
class Money {
  const Money(this.amount, this.currency);

  factory Money.fromJson(Map<String, dynamic> json) =>
      Money(json['amount'] as String, json['currency'] as String);

  final String amount;
  final String currency;

  @override
  String toString() => '$currency $amount';
}

class Rent {
  const Rent({
    required this.money,
    required this.frequency,
    required this.frequencyLabel,
    required this.dueDay,
  });

  factory Rent.fromJson(Map<String, dynamic> json) => Rent(
    money: Money.fromJson(json),
    frequency: json['frequency'] as String? ?? 'MONTHLY',
    frequencyLabel: json['frequency_label'] as String? ?? '',
    dueDay: json['due_day'] as int? ?? 1,
  );

  final Money money;
  final String frequency;
  final String frequencyLabel;

  /// WEEKLY: ISO weekday (1 = Monday); otherwise the day of the month.
  final int dueDay;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String get dueText => frequency == 'WEEKLY'
      ? 'due each ${_weekdays[(dueDay - 1).clamp(0, 6)]}'
      : 'due on day $dueDay';

  @override
  String toString() => '$money ${frequencyLabel.toLowerCase()}, $dueText';
}

class PartyRef {
  const PartyRef({required this.name, this.id, this.live = true});

  factory PartyRef.fromJson(Map<String, dynamic> json) => PartyRef(
    id: json['id'] as String?,
    name: json['name'] as String? ?? '',
    live: json['live'] as bool? ?? true,
  );

  final String? id;
  final String name;

  /// False when the CRM contact was deleted or merged since.
  final bool live;
}

class Tenancy {
  const Tenancy({
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.propertyName,
    required this.propertyAddress,
    required this.tenants,
    required this.landlords,
    required this.rent,
    required this.startDate,
    this.propertyId,
    this.propertyArchived = false,
    this.unitLabel,
    this.leaseReference,
    this.deposit,
    this.endDate,
    this.endedOn,
    this.endReason,
    this.notes = '',
    this.managedBy,
    this.canEdit = false,
    this.canActivate = false,
    this.canEnd = false,
    this.canDelete = false,
  });

  /// The manager's view and the tenant's (`/v1/me/tenancies`) share this.
  factory Tenancy.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>? ?? const {};
    final unit = json['unit'] as Map<String, dynamic>?;
    final lease = json['lease'] as Map<String, dynamic>?;
    final deposit = json['deposit'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    final managed = json['managed_by'] as Map<String, dynamic>?;
    List<PartyRef> parties(String key) => [
      for (final p in json[key] as List? ?? const [])
        PartyRef.fromJson(p as Map<String, dynamic>),
    ];
    return Tenancy(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'DRAFT',
      statusLabel: json['status_label'] as String? ?? '',
      propertyId: property['id'] as String?,
      propertyName: property['name'] as String? ?? '',
      propertyAddress: property['address'] as String? ?? '',
      propertyArchived: property['archived'] as bool? ?? false,
      unitLabel: unit?['label'] as String?,
      tenants: parties('tenants'),
      landlords: parties('landlords'),
      leaseReference: lease?['reference'] as String?,
      rent: Rent.fromJson(json['rent'] as Map<String, dynamic>),
      deposit: deposit == null ? null : Money.fromJson(deposit),
      startDate: json['start_date'] as String,
      endDate: json['end_date'] as String?,
      endedOn: json['ended_on'] as String?,
      endReason: json['end_reason'] as String?,
      notes: json['notes'] as String? ?? '',
      managedBy: managed?['name'] as String?,
      canEdit: can['edit'] as bool? ?? false,
      canActivate: can['activate'] as bool? ?? false,
      canEnd: can['end'] as bool? ?? false,
      canDelete: can['delete'] as bool? ?? false,
    );
  }

  final String id;

  /// DRAFT, ACTIVE, ENDED or TERMINATED.
  final String status;
  final String statusLabel;
  final String? propertyId;
  final String propertyName;
  final String propertyAddress;
  final bool propertyArchived;
  final String? unitLabel;
  final List<PartyRef> tenants;
  final List<PartyRef> landlords;
  final String? leaseReference;
  final Rent rent;
  final Money? deposit;
  final String startDate;

  /// The agreed end; [endedOn] is when it actually ended.
  final String? endDate;
  final String? endedOn;
  final String? endReason;
  final String notes;

  /// The tenant's view: who manages it.
  final String? managedBy;
  final bool canEdit;
  final bool canActivate;
  final bool canEnd;
  final bool canDelete;

  String get place =>
      unitLabel == null ? propertyName : '$propertyName, $unitLabel';
}

class TenancyOptions {
  const TenancyOptions({
    required this.frequencies,
    required this.currencies,
    required this.canWrite,
  });

  factory TenancyOptions.fromJson(Map<String, dynamic> json) => TenancyOptions(
    frequencies: {
      for (final f in json['frequencies'] as List? ?? const [])
        (f as Map<String, dynamic>)['code'] as String:
            f['label'] as String? ?? f['code'] as String,
    },
    currencies: {
      for (final c in json['currencies'] as List? ?? const [])
        (c as Map<String, dynamic>)['code'] as String:
            c['minor_unit'] as int? ?? 2,
    },
    canWrite:
        (json['permissions'] as Map<String, dynamic>?)?['write'] as bool? ??
        false,
  );

  /// Code to label, in the API's order.
  final Map<String, String> frequencies;

  /// Code to minor unit.
  final Map<String, int> currencies;
  final bool canWrite;

  /// Why [amount] is not a valid amount of [currency], or null.
  String? amountProblem(String amount, String currency) {
    final a = amount.trim();
    if (!RegExp(r'^\d{1,16}(\.\d+)?$').hasMatch(a)) {
      return 'Enter an amount, for example 950.00.';
    }
    if (double.parse(a) <= 0) return 'The amount must be more than zero.';
    final decimals = a.contains('.') ? a.split('.').last.length : 0;
    final allowed = currencies[currency] ?? 2;
    if (decimals > allowed) {
      return allowed == 0
          ? '$currency has no decimals.'
          : 'At most $allowed decimals for $currency.';
    }
    return null;
  }
}

/// A new tenancy, always created as a draft.
class TenancyDraft {
  const TenancyDraft({
    required this.propertyId,
    required this.tenantIds,
    required this.rentAmount,
    required this.currency,
    required this.frequency,
    required this.dueDay,
    required this.startDate,
    this.unitId,
    this.landlordIds = const [],
    this.depositAmount,
    this.endDate,
    this.notes = '',
  });

  final String propertyId;
  final String? unitId;
  final List<String> tenantIds;
  final List<String> landlordIds;
  final String rentAmount;
  final String currency;
  final String frequency;
  final int dueDay;
  final String? depositAmount;
  final String startDate;
  final String? endDate;
  final String notes;

  Map<String, Object?> toJson() => {
    'property_id': propertyId,
    'unit_id': unitId,
    'tenants': tenantIds,
    'landlords': landlordIds,
    'rent': {
      'amount': rentAmount.trim(),
      'currency': currency,
      'frequency': frequency,
      'due_day': dueDay,
    },
    if (depositAmount != null && depositAmount!.trim().isNotEmpty)
      'deposit': {'amount': depositAmount!.trim(), 'currency': currency},
    'start_date': startDate,
    'end_date': endDate,
    'notes': notes,
  };
}

typedef PropertyPage = ({List<ManagedProperty> items, int total});
typedef TenancyPage = ({
  List<Tenancy> items,
  int total,
  Map<String, int> statusCounts,
});

class PropertiesRepository {
  PropertiesRepository(this._api);

  final ApiClient _api;

  String _book(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}';

  ManagedProperty _property(ApiResponse r) =>
      ManagedProperty.fromJson(r.body['property'] as Map<String, dynamic>);
  Tenancy _tenancy(ApiResponse r) =>
      Tenancy.fromJson(r.body['tenancy'] as Map<String, dynamic>);

  Future<PropertyPage> properties(
    String book, {
    String query = '',
    int page = 1,
  }) async {
    final body = (await _api.get(
      Uri(
        path: '${_book(book)}/properties',
        queryParameters: {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'page': '$page',
          'page_size': '50',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final p in body['items'] as List? ?? const [])
          ManagedProperty.fromJson(p as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
    );
  }

  Future<ManagedProperty> property(String book, String id) async => _property(
    await _api.get('${_book(book)}/properties/${Uri.encodeComponent(id)}'),
  );

  Future<ManagedProperty> createProperty(
    String book, {
    required String name,
    required String address,
    required String marketCode,
    List<String> units = const [],
    String notes = '',
  }) async => _property(
    await _api.postJson('${_book(book)}/properties', {
      'name': name.trim(),
      'address': address.trim(),
      'market_code': marketCode,
      'notes': notes,
      'units': [
        for (final u in units)
          if (u.trim().isNotEmpty) {'label': u.trim()},
      ],
    }),
  );

  Future<ManagedProperty> addUnit(String book, String id, String label) async =>
      _property(
        await _api.postJson(
          '${_book(book)}/properties/${Uri.encodeComponent(id)}/units',
          {'label': label.trim()},
        ),
      );

  /// `UNIT_IN_USE` while a draft or active tenancy uses it.
  Future<ManagedProperty> removeUnit(
    String book,
    String id,
    String unitId,
  ) async => _property(
    await _api.delete(
      '${_book(book)}/properties/${Uri.encodeComponent(id)}/units/${Uri.encodeComponent(unitId)}',
    ),
  );

  /// Archives it. `PROPERTY_IN_USE` while a draft or active tenancy uses it.
  Future<void> deleteProperty(String book, String id) async {
    await _api.delete('${_book(book)}/properties/${Uri.encodeComponent(id)}');
  }

  Future<TenancyOptions> tenancyOptions(String book) async =>
      TenancyOptions.fromJson(
        (await _api.get('${_book(book)}/tenancies/options')).body,
      );

  Future<TenancyPage> tenancies(
    String book, {
    String? status,
    String? propertyId,
    int page = 1,
  }) async {
    final body = (await _api.get(
      Uri(
        path: '${_book(book)}/tenancies',
        queryParameters: {
          'status': ?status,
          'property_id': ?propertyId,
          'page': '$page',
          'page_size': '50',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final t in body['items'] as List? ?? const [])
          Tenancy.fromJson(t as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
      statusCounts: {
        for (final e
            in (body['status_counts'] as Map<String, dynamic>? ?? const {})
                .entries)
          e.key: e.value as int? ?? 0,
      },
    );
  }

  Future<Tenancy> tenancy(String book, String id) async => _tenancy(
    await _api.get('${_book(book)}/tenancies/${Uri.encodeComponent(id)}'),
  );

  Future<Tenancy> createTenancy(String book, TenancyDraft draft) async =>
      _tenancy(await _api.postJson('${_book(book)}/tenancies', draft.toJson()));

  /// `UNIT_OCCUPIED` when the unit (or the whole property) is already let.
  Future<Tenancy> activate(String book, String id) async {
    try {
      return _tenancy(
        await _api.post(
          '${_book(book)}/tenancies/${Uri.encodeComponent(id)}/activate',
        ),
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'UNIT_OCCUPIED') {
        throw failure.withMessage(
          'This place already has an active tenancy. End that one first.',
        );
      }
      rethrow;
    }
  }

  Future<Tenancy> end(
    String book,
    String id, {
    required String endDate,
    required String reason,
  }) async => _tenancy(
    await _api.postJson(
      '${_book(book)}/tenancies/${Uri.encodeComponent(id)}/end',
      {'end_date': endDate, 'reason': reason.trim()},
    ),
  );

  /// Drafts only.
  Future<void> deleteTenancy(String book, String id) async {
    await _api.delete('${_book(book)}/tenancies/${Uri.encodeComponent(id)}');
  }

  /// The signed-in tenant's own tenancies (matched by verified email).
  Future<List<Tenancy>> myTenancies() async => [
    for (final t
        in (await _api.get('/v1/me/tenancies')).body['items'] as List? ??
            const [])
      Tenancy.fromJson(t as Map<String, dynamic>),
  ];

  Future<Tenancy> myTenancy(String id) async =>
      _tenancy(await _api.get('/v1/me/tenancies/${Uri.encodeComponent(id)}'));
}
