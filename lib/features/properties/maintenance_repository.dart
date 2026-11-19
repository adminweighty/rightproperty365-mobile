import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../applications/applications_repository.dart'
    show ChosenFile, fileContentType;
import 'properties_repository.dart' show Money;

/// Maintenance requests, part (c) (API 0.36.2). Managers (owners, managers
/// and agents; staff read) work them through NEW, TRIAGED, ASSIGNED,
/// IN_PROGRESS, RESOLVED and CLOSED (or CANCELLED); tenants raise and
/// follow the requests on their own tenancy.

class CodeLabel {
  const CodeLabel(this.code, this.label);

  factory CodeLabel.fromJson(Map<String, dynamic>? json) => CodeLabel(
    json?['code'] as String? ?? '',
    json?['label'] as String? ?? json?['code'] as String? ?? '',
  );

  final String code;
  final String label;
}

class MaintenanceProvider {
  const MaintenanceProvider({
    required this.id,
    required this.name,
    this.trade,
    this.city,
    this.verified = false,
  });

  factory MaintenanceProvider.fromJson(Map<String, dynamic> json) =>
      MaintenanceProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        trade: (json['trade'] as Map<String, dynamic>?)?['label'] as String?,
        city: json['city'] as String?,
        verified: json['verified'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String? trade;
  final String? city;
  final bool verified;
}

class MaintenancePhoto {
  const MaintenancePhoto({required this.id, required this.url});

  factory MaintenancePhoto.fromJson(Map<String, dynamic> json) =>
      MaintenancePhoto(id: json['id'] as String, url: json['url'] as String);

  final String id;

  /// An API path (`/v1/...`), read with the session.
  final String url;
}

class MaintenanceCost {
  const MaintenanceCost({
    required this.id,
    required this.money,
    required this.description,
    required this.methodLabel,
    required this.incurredOn,
    this.ledgerStatusLabel,
    this.reversed = false,
  });

  factory MaintenanceCost.fromJson(Map<String, dynamic> json) =>
      MaintenanceCost(
        id: json['id'] as String,
        money: Money(json['amount'] as String, json['currency'] as String),
        description: json['description'] as String? ?? '',
        methodLabel: json['method_label'] as String? ?? '',
        incurredOn: json['incurred_on'] as String,
        ledgerStatusLabel: json['ledger_status_label'] as String?,
        reversed: json['reversed'] as bool? ?? false,
      );

  final String id;
  final Money money;
  final String description;
  final String methodLabel;
  final String incurredOn;

  /// The ledger's wording, "Recorded by you, not verified".
  final String? ledgerStatusLabel;
  final bool reversed;
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.type,
    required this.at,
    required this.actorName,
    this.actorKind = 'SYSTEM',
    this.you = false,
    this.fromStatus,
    this.toStatus,
    this.text,
    this.internal = false,
    this.details,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>? ?? const {};
    return TimelineItem(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      at: DateTime.parse(json['at'] as String).toLocal(),
      actorName: actor['name'] as String? ?? '',
      actorKind: actor['kind'] as String? ?? 'SYSTEM',
      you: actor['you'] as bool? ?? false,
      fromStatus: json['from_status'] as String?,
      toStatus: json['to_status'] as String?,
      text: json['text'] as String?,
      internal: json['internal'] as bool? ?? false,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  final String id;

  /// CREATED, STATUS_CHANGED, COMMENT, ASSIGNED, COST_ADDED, PHOTO_ADDED or
  /// UPDATED (the tenant never sees the last two, nor internal comments).
  final String type;
  final DateTime at;
  final String actorName;
  final String actorKind;
  final bool you;
  final String? fromStatus;
  final String? toStatus;
  final String? text;
  final bool internal;
  final Map<String, dynamic>? details;
}

/// A request as the manager sees it (list and detail) or as the tenant sees
/// it; the tenant's has no costs, assignment ids, internal items or `can`
/// beyond commenting and photos.
class MaintenanceRequest {
  const MaintenanceRequest({
    required this.id,
    required this.reference,
    required this.status,
    required this.statusLabel,
    required this.category,
    required this.priority,
    required this.title,
    required this.propertyName,
    required this.createdAt,
    this.description = '',
    this.propertyId,
    this.propertyAddress,
    this.unitLabel,
    this.tenancyId,
    this.tenants = const [],
    this.raisedByName,
    this.raisedByKind,
    this.raisedByYou = false,
    this.providerName,
    this.enquiryReference,
    this.photoCount = 0,
    this.costTotals = const [],
    this.photos = const [],
    this.costs = const [],
    this.timeline = const [],
    this.canEdit = false,
    this.transitions = const [],
    this.canAssign = false,
    this.canAddCost = false,
    this.canComment = false,
    this.canAddPhoto = false,
  });

  factory MaintenanceRequest.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>? ?? const {};
    final unit = json['unit'] as Map<String, dynamic>?;
    final raised = json['raised_by'] as Map<String, dynamic>?;
    final provider = json['provider'] as Map<String, dynamic>?;
    final assignment = json['assignment'] as Map<String, dynamic>?;
    final tenancy = json['tenancy'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    return MaintenanceRequest(
      id: json['id'] as String,
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? 'NEW',
      statusLabel: json['status_label'] as String? ?? '',
      category: CodeLabel.fromJson(json['category'] as Map<String, dynamic>?),
      priority: CodeLabel.fromJson(json['priority'] as Map<String, dynamic>?),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      propertyId: property['id'] as String?,
      propertyName: property['name'] as String? ?? '',
      propertyAddress: property['address'] as String?,
      unitLabel: unit?['label'] as String?,
      tenancyId: json['tenancy_id'] as String? ?? tenancy?['id'] as String?,
      tenants: [
        for (final t in tenancy?['tenants'] as List? ?? const [])
          (t as Map<String, dynamic>)['name'] as String? ?? '',
      ],
      raisedByName: raised?['name'] as String?,
      raisedByKind: raised?['kind'] as String?,
      raisedByYou: raised?['you'] as bool? ?? false,
      providerName: provider?['name'] as String?,
      enquiryReference:
          (assignment?['enquiry'] as Map<String, dynamic>?)?['reference']
              as String?,
      photoCount: json['photo_count'] as int? ?? 0,
      costTotals: [
        for (final t in json['cost_totals'] as List? ?? const [])
          Money(
            (t as Map<String, dynamic>)['amount'] as String,
            t['currency'] as String,
          ),
      ],
      photos: [
        for (final p in json['photos'] as List? ?? const [])
          MaintenancePhoto.fromJson(p as Map<String, dynamic>),
      ],
      costs: [
        for (final c in json['costs'] as List? ?? const [])
          MaintenanceCost.fromJson(c as Map<String, dynamic>),
      ],
      timeline: [
        for (final t in json['timeline'] as List? ?? const [])
          TimelineItem.fromJson(t as Map<String, dynamic>),
      ],
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      canEdit: can['edit'] as bool? ?? false,
      transitions: [
        for (final t in can['transitions'] as List? ?? const []) t as String,
      ],
      canAssign: can['assign'] as bool? ?? false,
      canAddCost: can['add_cost'] as bool? ?? false,
      canComment: can['comment'] as bool? ?? false,
      canAddPhoto: can['add_photo'] as bool? ?? false,
    );
  }

  final String id;
  final String reference;
  final String status;
  final String statusLabel;
  final CodeLabel category;
  final CodeLabel priority;
  final String title;
  final String description;
  final String? propertyId;
  final String propertyName;
  final String? propertyAddress;
  final String? unitLabel;
  final String? tenancyId;
  final List<String> tenants;
  final String? raisedByName;

  /// MANAGER, TENANT or SYSTEM.
  final String? raisedByKind;
  final bool raisedByYou;
  final String? providerName;
  final String? enquiryReference;
  final int photoCount;

  /// One per currency, reversed costs left out.
  final List<Money> costTotals;
  final List<MaintenancePhoto> photos;
  final List<MaintenanceCost> costs;
  final List<TimelineItem> timeline;
  final DateTime createdAt;
  final bool canEdit;

  /// The statuses the request may move to now (never ASSIGNED: that is
  /// [canAssign]).
  final List<String> transitions;
  final bool canAssign;
  final bool canAddCost;
  final bool canComment;
  final bool canAddPhoto;

  String get place =>
      unitLabel == null ? propertyName : '$propertyName, $unitLabel';
  bool get open => status != 'CLOSED' && status != 'CANCELLED';
}

class MaintenanceOptions {
  const MaintenanceOptions({
    required this.categories,
    required this.priorities,
    this.statuses = const {},
    this.currencies = const {},
    this.methods = const {},
    this.maxPhotos = 10,
    this.canWrite = false,
  });

  factory MaintenanceOptions.fromJson(Map<String, dynamic> json) {
    Map<String, String> labels(String key) => {
      for (final c in json[key] as List? ?? const [])
        (c as Map<String, dynamic>)['code'] as String:
            c['label'] as String? ?? c['code'] as String,
    };
    return MaintenanceOptions(
      categories: labels('categories'),
      priorities: labels('priorities'),
      statuses: labels('statuses'),
      methods: labels('methods'),
      currencies: {
        for (final c in json['currencies'] as List? ?? const [])
          (c as Map<String, dynamic>)['code'] as String:
              c['minor_unit'] as int? ?? 2,
      },
      maxPhotos:
          (json['photo_rules'] as Map<String, dynamic>?)?['max_photos']
              as int? ??
          10,
      canWrite:
          (json['permissions'] as Map<String, dynamic>?)?['write'] as bool? ??
          false,
    );
  }

  final Map<String, String> categories;
  final Map<String, String> priorities;
  final Map<String, String> statuses;
  final Map<String, int> currencies;
  final Map<String, String> methods;
  final int maxPhotos;
  final bool canWrite;

  String? amountProblem(String amount, String currency) {
    final a = amount.trim();
    if (!RegExp(r'^\d{1,16}(\.\d+)?$').hasMatch(a)) {
      return 'Enter an amount, for example 85.00.';
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

typedef MaintenancePage = ({
  List<MaintenanceRequest> items,
  int total,
  Map<String, int> statusCounts,
});

class MaintenanceRepository {
  MaintenanceRepository(this._api);

  final ApiClient _api;

  String _base(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}/maintenance';
  String _one(String book, String id) =>
      '${_base(book)}/${Uri.encodeComponent(id)}';
  String _mine(String tenancyId) =>
      '/v1/me/tenancies/${Uri.encodeComponent(tenancyId)}/maintenance';

  MaintenanceRequest _request(Map<String, dynamic> body) =>
      MaintenanceRequest.fromJson(body['request'] as Map<String, dynamic>);

  Never _explain(ApiFailure failure) => throw switch (failure.code) {
    'MAINTENANCE_INVALID_TRANSITION' => failure.withMessage(
      'The request cannot move to that status from where it is now.',
    ),
    'MAINTENANCE_CLOSED' => failure.withMessage(
      'This request is closed, so it cannot be changed.',
    ),
    'MAINTENANCE_CHANGED' => failure.withMessage(
      'Someone changed this request just now. It has been reloaded; try '
      'again.',
    ),
    'MAINTENANCE_PHOTO_LIMIT' => failure.withMessage(
      'This request already has the most photos it can have.',
    ),
    'UNSUPPORTED_FILE_TYPE' => failure.withMessage(
      'Only photos (JPEG, PNG or WebP) can be added.',
    ),
    'FILE_TOO_LARGE' => failure.withMessage('That photo is larger than 10 MB.'),
    _ => failure,
  };

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiFailure catch (failure) {
      _explain(failure);
    }
  }

  // The manager's side.

  Future<MaintenanceOptions> options(String book) async =>
      MaintenanceOptions.fromJson(
        (await _api.get('${_base(book)}/options')).body,
      );

  Future<MaintenancePage> list(
    String book, {
    String? status,
    String query = '',
    int page = 1,
  }) async {
    final body = (await _api.get(
      Uri(
        path: _base(book),
        queryParameters: {
          'status': ?status,
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'page': '$page',
          'page_size': '50',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final r in body['items'] as List? ?? const [])
          MaintenanceRequest.fromJson(r as Map<String, dynamic>),
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

  Future<MaintenanceRequest> get(String book, String id) async =>
      _request((await _api.get(_one(book, id))).body);

  Future<MaintenanceRequest> create(
    String book, {
    required String propertyId,
    String? unitId,
    required String category,
    required String priority,
    required String title,
    String description = '',
  }) async => _request(
    (await _api.postJson(_base(book), {
      'property_id': propertyId,
      'unit_id': unitId,
      'category': category,
      'priority': priority,
      'title': title.trim(),
      'description': description.trim(),
    })).body,
  );

  /// CANCELLED needs a [note] (the reason).
  Future<MaintenanceRequest> setStatus(
    String book,
    String id,
    String status, {
    String? note,
  }) => _run(
    () async => _request(
      (await _api.postJson('${_one(book, id)}/status', {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      })).body,
    ),
  );

  Future<void> comment(
    String book,
    String id,
    String text, {
    bool internal = false,
  }) => _run(
    () => _api.postJson('${_one(book, id)}/comments', {
      'text': text.trim(),
      'internal': internal,
    }),
  );

  Future<List<MaintenanceProvider>> providers(
    String book, {
    String query = '',
  }) async => [
    for (final p
        in (await _api.get(
                  Uri(
                    path: '${_base(book)}/providers',
                    queryParameters: {
                      if (query.trim().isNotEmpty) 'q': query.trim(),
                    },
                  ).toString(),
                )).body['items']
                as List? ??
            const [])
      MaintenanceProvider.fromJson(p as Map<String, dynamic>),
  ];

  /// Sends the provider one business enquiry quoting the request (never
  /// the tenant's details); retrying never sends a second.
  Future<({MaintenanceRequest request, String? enquiryReference})> assign(
    String book,
    String id,
    String providerId, {
    String? message,
  }) => _run(() async {
    final body = (await _api.postJson('${_one(book, id)}/assign', {
      'directory_profile_id': providerId,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
    })).body;
    return (
      request: _request(body),
      enquiryReference:
          (body['enquiry'] as Map<String, dynamic>?)?['reference'] as String?,
    );
  });

  /// Writes one EXPENSE entry in the books, "Recorded by you, not
  /// verified".
  Future<MaintenanceRequest> addCost(
    String book,
    String id, {
    required String amount,
    required String currency,
    required String description,
    required String method,
    required String incurredOn,
  }) => _run(
    () async => _request(
      (await _api.postJson('${_one(book, id)}/costs', {
        'amount': amount.trim(),
        'currency': currency,
        'description': description.trim(),
        'method': method,
        'incurred_on': incurredOn,
      })).body,
    ),
  );

  Future<void> addPhoto(String book, String id, ChosenFile file) => _run(
    () => _api.postFile(
      '${_one(book, id)}/photos',
      field: 'file',
      bytes: file.bytes,
      fileName: file.name,
      contentType: fileContentType(file.name),
    ),
  );

  /// A photo's bytes, read with the session (manager's or tenant's URL).
  Future<Uint8List> photo(String url) => _api.getBytes(url);

  // The tenant's side.

  Future<MaintenanceOptions> myOptions(String tenancyId) async =>
      MaintenanceOptions.fromJson(
        (await _api.get('${_mine(tenancyId)}/options')).body,
      );

  Future<List<MaintenanceRequest>> mine(String tenancyId) async => [
    for (final r
        in (await _api.get(_mine(tenancyId))).body['items'] as List? ??
            const [])
      MaintenanceRequest.fromJson(r as Map<String, dynamic>),
  ];

  Future<MaintenanceRequest> myRequest(String tenancyId, String id) async =>
      _request(
        (await _api.get('${_mine(tenancyId)}/${Uri.encodeComponent(id)}')).body,
      );

  /// Only on an active tenancy.
  Future<MaintenanceRequest> report(
    String tenancyId, {
    required String category,
    required String priority,
    required String title,
    String description = '',
  }) => _run(() async {
    try {
      return _request(
        (await _api.postJson(_mine(tenancyId), {
          'category': category,
          'priority': priority,
          'title': title.trim(),
          'description': description.trim(),
        })).body,
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'TENANCY_INVALID_STATE') {
        throw failure.withMessage(
          'Requests can be raised only while the tenancy is active.',
        );
      }
      rethrow;
    }
  });

  Future<void> myComment(String tenancyId, String id, String text) => _run(
    () => _api.postJson(
      '${_mine(tenancyId)}/${Uri.encodeComponent(id)}/comments',
      {'text': text.trim()},
    ),
  );

  Future<void> myPhoto(String tenancyId, String id, ChosenFile file) => _run(
    () => _api.postFile(
      '${_mine(tenancyId)}/${Uri.encodeComponent(id)}/photos',
      field: 'file',
      bytes: file.bytes,
      fileName: file.name,
      contentType: fileContentType(file.name),
    ),
  );
}
