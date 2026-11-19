import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../applications/applications_repository.dart'
    show ChosenFile, fileContentType;

/// Inspections, part (d) (API 0.36.3): a checklist copied from a template,
/// a finding per item (OK, Needs attention, Damaged, Not applicable) with a
/// note and photos, completed into a frozen report. A move-out is compared
/// with the tenancy's move-in. Tenants see completed ones only.

class InspectionPhoto {
  const InspectionPhoto({required this.id, required this.url});

  factory InspectionPhoto.fromJson(Map<String, dynamic> json) =>
      InspectionPhoto(id: json['id'] as String, url: json['url'] as String);

  final String id;

  /// An API path, read with the session.
  final String url;
}

class InspectionItem {
  const InspectionItem({
    required this.id,
    required this.label,
    this.status,
    this.statusLabel,
    this.note = '',
    this.photos = const [],
    this.baselineStatus,
    this.baselineLabel,
    this.baselineNote,
  });

  factory InspectionItem.fromJson(Map<String, dynamic> json) {
    final baseline = json['baseline'] as Map<String, dynamic>?;
    return InspectionItem(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      status: json['status'] as String?,
      statusLabel: json['status_label'] as String?,
      note: json['note'] as String? ?? '',
      photos: [
        for (final p in json['photos'] as List? ?? const [])
          InspectionPhoto.fromJson(p as Map<String, dynamic>),
      ],
      baselineStatus: baseline?['status'] as String?,
      baselineLabel: baseline?['status_label'] as String?,
      baselineNote: baseline?['note'] as String?,
    );
  }

  final String id;
  final String label;

  /// OK, ATTENTION, DAMAGED, NA, or null while not recorded.
  final String? status;
  final String? statusLabel;
  final String note;
  final List<InspectionPhoto> photos;

  /// The move-in's finding for the same item (move-outs only).
  final String? baselineStatus;
  final String? baselineLabel;
  final String? baselineNote;
}

class InspectionArea {
  const InspectionArea({
    required this.id,
    required this.label,
    required this.items,
  });

  factory InspectionArea.fromJson(Map<String, dynamic> json) => InspectionArea(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    items: [
      for (final i in json['items'] as List? ?? const [])
        InspectionItem.fromJson(i as Map<String, dynamic>),
    ],
  );

  final String id;
  final String label;
  final List<InspectionItem> items;
}

class InspectionProgress {
  const InspectionProgress({
    this.items = 0,
    this.done = 0,
    this.ok = 0,
    this.attention = 0,
    this.damaged = 0,
    this.na = 0,
  });

  factory InspectionProgress.fromJson(Map<String, dynamic>? json) =>
      InspectionProgress(
        items: json?['items'] as int? ?? 0,
        done: json?['done'] as int? ?? 0,
        ok: json?['ok'] as int? ?? 0,
        attention: json?['attention'] as int? ?? 0,
        damaged: json?['damaged'] as int? ?? 0,
        na: json?['na'] as int? ?? 0,
      );

  final int items;
  final int done;
  final int ok;
  final int attention;
  final int damaged;
  final int na;
}

/// The manager's summary and detail, and the tenant's view, in one shape;
/// what the tenant's lacks is empty or false.
class Inspection {
  const Inspection({
    required this.id,
    required this.reference,
    required this.type,
    required this.typeLabel,
    required this.status,
    required this.statusLabel,
    required this.propertyName,
    required this.scheduledFor,
    required this.progress,
    this.unitLabel,
    this.tenancyId,
    this.tenants = const [],
    this.inspectorName,
    this.templateLabel,
    this.completedAt,
    this.areas = const [],
    this.summary = '',
    this.tenantSignOff,
    this.agentSignOff,
    this.cancelReason,
    this.baselineReference,
    this.reportUrl,
    this.canRecord = false,
    this.canAddPhoto = false,
    this.canStart = false,
    this.canComplete = false,
    this.canCancel = false,
  });

  factory Inspection.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>? ?? const {};
    final unit = json['unit'] as Map<String, dynamic>?;
    final tenancy = json['tenancy'] as Map<String, dynamic>?;
    final signOff = json['sign_off'] as Map<String, dynamic>?;
    final baseline = json['baseline'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    DateTime? at(String key) => switch (json[key]) {
      final String s => DateTime.parse(s).toLocal(),
      _ => null,
    };
    return Inspection(
      id: json['id'] as String,
      reference: json['reference'] as String? ?? '',
      type: json['type'] as String? ?? '',
      typeLabel: json['type_label'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      propertyName: property['name'] as String? ?? '',
      unitLabel: unit?['label'] as String?,
      tenancyId: json['tenancy_id'] as String? ?? tenancy?['id'] as String?,
      tenants: [
        for (final t in tenancy?['tenants'] as List? ?? const [])
          (t as Map<String, dynamic>)['name'] as String? ?? '',
      ],
      scheduledFor: at('scheduled_for')!,
      completedAt: at('completed_at'),
      inspectorName:
          (json['inspector'] as Map<String, dynamic>?)?['name'] as String?,
      templateLabel:
          (json['template'] as Map<String, dynamic>?)?['label'] as String?,
      progress: InspectionProgress.fromJson(
        json['progress'] as Map<String, dynamic>?,
      ),
      areas: [
        for (final a in json['areas'] as List? ?? const [])
          InspectionArea.fromJson(a as Map<String, dynamic>),
      ],
      summary: json['summary'] as String? ?? '',
      tenantSignOff: signOff?['tenant_name'] as String?,
      agentSignOff: signOff?['agent_name'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      baselineReference: baseline?['reference'] as String?,
      reportUrl: json['report_url'] as String?,
      canRecord: can['record_findings'] as bool? ?? false,
      canAddPhoto: can['add_photo'] as bool? ?? false,
      canStart: can['start'] as bool? ?? false,
      canComplete: can['complete'] as bool? ?? false,
      canCancel: can['cancel'] as bool? ?? false,
    );
  }

  final String id;
  final String reference;

  /// MOVE_IN, ROUTINE or MOVE_OUT.
  final String type;
  final String typeLabel;

  /// SCHEDULED, IN_PROGRESS, COMPLETED or CANCELLED.
  final String status;
  final String statusLabel;
  final String propertyName;
  final String? unitLabel;
  final String? tenancyId;
  final List<String> tenants;
  final DateTime scheduledFor;
  final DateTime? completedAt;
  final String? inspectorName;
  final String? templateLabel;
  final InspectionProgress progress;
  final List<InspectionArea> areas;
  final String summary;

  /// Typed names, not signatures.
  final String? tenantSignOff;
  final String? agentSignOff;
  final String? cancelReason;

  /// The move-in a move-out is compared with.
  final String? baselineReference;
  final String? reportUrl;
  final bool canRecord;
  final bool canAddPhoto;
  final bool canStart;
  final bool canComplete;
  final bool canCancel;

  String get place =>
      unitLabel == null ? propertyName : '$propertyName, $unitLabel';

  /// Completed and cancelled inspections cannot change.
  bool get frozen => status == 'COMPLETED' || status == 'CANCELLED';
}

class InspectionTemplate {
  const InspectionTemplate(this.code, this.label, this.areas, this.items);

  final String code;
  final String label;
  final int areas;
  final int items;
}

class InspectionOptions {
  const InspectionOptions({
    required this.types,
    required this.findingStatuses,
    required this.templates,
    required this.inspectors,
    this.canWrite = false,
  });

  factory InspectionOptions.fromJson(Map<String, dynamic> json) {
    Map<String, String> labels(String key) => {
      for (final c in json[key] as List? ?? const [])
        (c as Map<String, dynamic>)['code'] as String:
            c['label'] as String? ?? c['code'] as String,
    };
    return InspectionOptions(
      types: labels('types'),
      findingStatuses: labels('finding_statuses'),
      templates: [
        for (final t in json['templates'] as List? ?? const [])
          InspectionTemplate(
            (t as Map<String, dynamic>)['code'] as String,
            t['label'] as String? ?? t['code'] as String,
            (t['areas'] as List? ?? const []).length,
            [
              for (final a in t['areas'] as List? ?? const [])
                ...((a as Map<String, dynamic>)['items'] as List? ?? const []),
            ].length,
          ),
      ],
      inspectors: {
        for (final i in json['inspectors'] as List? ?? const [])
          (i as Map<String, dynamic>)['user_id'] as String:
              i['name'] as String? ?? '',
      },
      canWrite:
          (json['permissions'] as Map<String, dynamic>?)?['write'] as bool? ??
          false,
    );
  }

  final Map<String, String> types;
  final Map<String, String> findingStatuses;
  final List<InspectionTemplate> templates;

  /// User id to name.
  final Map<String, String> inspectors;
  final bool canWrite;
}

/// One line of a findings save: only what is given changes.
class FindingChange {
  const FindingChange(this.itemId, {this.status, this.note});

  final String itemId;
  final String? status;
  final String? note;

  Map<String, Object?> toJson() => {
    'item_id': itemId,
    'status': ?status,
    'note': ?note,
  };
}

typedef InspectionPage = ({
  List<Inspection> items,
  int total,
  Map<String, int> statusCounts,
});

class InspectionRepository {
  InspectionRepository(this._api);

  final ApiClient _api;

  String _base(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}/inspections';
  String _one(String book, String id) =>
      '${_base(book)}/${Uri.encodeComponent(id)}';
  String _mine(String tenancyId) =>
      '/v1/me/tenancies/${Uri.encodeComponent(tenancyId)}/inspections';

  Inspection _inspection(Map<String, dynamic> body) =>
      Inspection.fromJson(body['inspection'] as Map<String, dynamic>);

  Future<Inspection> _write(Future<ApiResponse> Function() call) async {
    try {
      return _inspection((await call()).body);
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'INSPECTION_CLOSED' => failure.withMessage(
          'This inspection is finished, so it can no longer change.',
        ),
        'INSPECTION_INCOMPLETE' => failure.withMessage(
          switch (failure.details['missing']) {
            1 => '1 item still needs a status before it can be completed.',
            final int n =>
              '$n items still need a status before it can be '
                  'completed.',
            _ => 'Some items still need a status before it can be completed.',
          },
        ),
        'INSPECTION_CHANGED' => failure.withMessage(
          'Someone changed this inspection just now. It has been reloaded; '
          'try again.',
        ),
        'INSPECTION_INVALID_TRANSITION' => failure.withMessage(
          'That cannot be done from where the inspection is now.',
        ),
        'INSPECTION_PHOTO_LIMIT' => failure.withMessage(
          'This item already has the most photos it can have.',
        ),
        'UNSUPPORTED_FILE_TYPE' => failure.withMessage(
          'Only photos (JPEG, PNG or WebP) can be added.',
        ),
        'FILE_TOO_LARGE' => failure.withMessage(
          'That photo is larger than 10 MB.',
        ),
        _ => failure,
      };
    }
  }

  Future<InspectionOptions> options(String book) async =>
      InspectionOptions.fromJson(
        (await _api.get('${_base(book)}/options')).body,
      );

  Future<InspectionPage> list(String book, {String? status}) async {
    final body = (await _api.get(
      Uri(
        path: _base(book),
        queryParameters: {'status': ?status, 'page_size': '50'},
      ).toString(),
    )).body;
    return (
      items: [
        for (final i in body['items'] as List? ?? const [])
          Inspection.fromJson(i as Map<String, dynamic>),
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

  Future<Inspection> get(String book, String id) async =>
      _inspection((await _api.get(_one(book, id))).body);

  Future<Inspection> create(
    String book, {
    required String propertyId,
    String? unitId,
    String? tenancyId,
    required String type,
    required DateTime scheduledFor,
    String? inspectorUserId,
    required String template,
  }) => _write(
    () => _api.postJson(_base(book), {
      'property_id': propertyId,
      'unit_id': unitId,
      'tenancy_id': tenancyId,
      'type': type,
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'inspector_user_id': ?inspectorUserId,
      'checklist_template': template,
    }),
  );

  /// Saves only the listed items; the first save starts the inspection.
  Future<Inspection> saveFindings(
    String book,
    String id,
    List<FindingChange> changes,
  ) => _write(
    () => _api.putJson('${_one(book, id)}/findings', {
      'items': [for (final c in changes) c.toJson()],
    }),
  );

  Future<Inspection> start(String book, String id) =>
      _write(() => _api.post('${_one(book, id)}/start'));

  /// Refused while any item has no status.
  Future<Inspection> complete(
    String book,
    String id, {
    String? summary,
    String? tenantName,
    String? agentName,
  }) {
    String? text(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    return _write(
      () => _api.postJson('${_one(book, id)}/complete', {
        'summary': ?text(summary),
        'tenant_sign_off_name': ?text(tenantName),
        'agent_sign_off_name': ?text(agentName),
      }),
    );
  }

  Future<Inspection> cancel(String book, String id, String reason) => _write(
    () => _api.postJson('${_one(book, id)}/cancel', {'reason': reason.trim()}),
  );

  Future<void> addPhoto(
    String book,
    String id,
    String itemId,
    ChosenFile file,
  ) async {
    try {
      await _api.postFile(
        '${_one(book, id)}/items/${Uri.encodeComponent(itemId)}/photos',
        field: 'file',
        bytes: file.bytes,
        fileName: file.name,
        contentType: fileContentType(file.name),
      );
    } on ApiFailure catch (failure) {
      // The same wording as the other writes.
      await _write(() => Future.error(failure));
    }
  }

  /// A photo or the report PDF, read with the session.
  Future<Uint8List> bytes(String url) => _api.getBytes(url);

  // The tenant's side: completed inspections of their own tenancy.

  Future<List<Inspection>> mine(String tenancyId) async => [
    for (final i
        in (await _api.get(_mine(tenancyId))).body['items'] as List? ??
            const [])
      Inspection.fromJson(i as Map<String, dynamic>),
  ];

  Future<Inspection> myInspection(String tenancyId, String id) async =>
      _inspection(
        (await _api.get('${_mine(tenancyId)}/${Uri.encodeComponent(id)}')).body,
      );
}
