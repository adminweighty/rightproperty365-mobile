import '../../core/api/api_client.dart';

/// Lead stages of a contact, in pipeline order (a fixed list in the API).
const contactStages = {
  'NEW': 'New',
  'CONTACTED': 'Contacted',
  'VIEWING_REQUESTED': 'Viewing requested',
  'VIEWING_CONFIRMED': 'Viewing confirmed',
  'NEGOTIATING': 'Negotiating',
  'CLOSED': 'Closed',
  'UNSUCCESSFUL': 'Unsuccessful',
};

/// The `contact_types` reference set's baseline, used when the reference
/// endpoint cannot be read.
const contactTypesFallback = {
  'buyer': 'Buyer',
  'tenant': 'Tenant',
  'landlord': 'Landlord',
  'owner': 'Owner',
  'other': 'Other',
};

/// A contact book: an organisation's, or an approved direct owner's own.
class ContactBook {
  const ContactBook({
    required this.id,
    required this.name,
    required this.canWrite,
    this.canExport = false,
    this.personal = false,
  });

  /// The organisation ID, or the direct owner's own user ID.
  final String id;
  final String name;

  /// OWNER, MANAGER and AGENT (and a direct owner); STAFF only read.
  final bool canWrite;

  /// OWNER and MANAGER import and export, on the website.
  final bool canExport;
  final bool personal;
}

DateTime? _time(Object? v) => v is String ? DateTime.parse(v) : null;
String? _name(Object? v) => (v as Map<String, dynamic>?)?['name'] as String?;

class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.emails,
    required this.phones,
    required this.type,
    required this.typeLabel,
    required this.stage,
    required this.stageLabel,
    required this.tags,
    this.ownerName,
    this.sourceLabel,
    this.marketingGranted,
    this.marketingAt,
    this.marketingSource,
    this.marketingRecordedBy,
    this.lastContactAt,
    this.remindersDue = 0,
    this.openReminders = 0,
    this.nextReminderAt,
    this.mergedInto,
    this.linkedListings = const [],
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    final marketing = json['marketing_permission'] as Map<String, dynamic>?;
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String,
      emails: [for (final e in (json['emails'] as List?) ?? const []) '$e'],
      phones: [for (final p in (json['phones'] as List?) ?? const []) '$p'],
      type: json['type'] as String? ?? 'other',
      typeLabel: json['type_label'] as String? ?? '',
      stage: json['stage'] as String? ?? 'NEW',
      stageLabel:
          json['stage_label'] as String? ?? contactStages[json['stage']] ?? '',
      tags: [for (final t in (json['tags'] as List?) ?? const []) '$t'],
      ownerName: json['owner_name'] as String?,
      sourceLabel: json['source_label'] as String?,
      marketingGranted: marketing?['granted'] as bool?,
      marketingAt: _time(marketing?['granted_at']),
      marketingSource: marketing?['source'] as String?,
      marketingRecordedBy: marketing?['recorded_by_name'] as String?,
      lastContactAt: _time(json['last_contact_at']),
      remindersDue: json['reminders_due'] as int? ?? 0,
      openReminders: json['open_reminders'] as int? ?? 0,
      nextReminderAt: _time(json['next_reminder_at']),
      mergedInto: json['merged_into'] as String?,
      linkedListings: [
        for (final l in (json['linked_listings'] as List?) ?? const [])
          (
            title: (l as Map<String, dynamic>)['title'] as String? ?? '',
            reference: l['reference'] as String? ?? '',
            slug: l['slug'] as String?,
          ),
      ],
    );
  }

  final String id;
  final String name;
  final List<String> emails;
  final List<String> phones;
  final String type;
  final String typeLabel;
  final String stage;
  final String stageLabel;
  final List<String> tags;
  final String? ownerName;
  final String? sourceLabel;
  final bool? marketingGranted;
  final DateTime? marketingAt;
  final String? marketingSource;
  final String? marketingRecordedBy;
  final DateTime? lastContactAt;
  final int remindersDue;
  final int openReminders;
  final DateTime? nextReminderAt;

  /// Set on a merged contact: the one it now lives in.
  final String? mergedInto;
  final List<({String title, String reference, String? slug})> linkedListings;
}

class ContactReminder {
  const ContactReminder({
    required this.id,
    required this.dueAt,
    required this.text,
    required this.done,
    required this.overdue,
    this.contactId,
    this.contactName,
  });

  factory ContactReminder.fromJson(Map<String, dynamic> json) =>
      ContactReminder(
        id: json['id'] as String,
        dueAt: DateTime.parse(json['due_at'] as String),
        text: json['text'] as String? ?? '',
        done: json['done'] == true,
        overdue: json['overdue'] == true,
        contactId:
            json['contact_id'] as String? ??
            (json['contact'] as Map<String, dynamic>?)?['id'] as String?,
        contactName:
            (json['contact'] as Map<String, dynamic>?)?['name'] as String?,
      );

  final String id;
  final DateTime dueAt;
  final String text;
  final bool done;
  final bool overdue;
  final String? contactId;
  final String? contactName;
}

/// A contact with what is linked to it and its reminders (`ContactBody`).
class ContactDetail {
  const ContactDetail({
    required this.contact,
    required this.linkedItems,
    required this.reminders,
  });

  factory ContactDetail.fromJson(Map<String, dynamic> json) => ContactDetail(
    contact: Contact.fromJson(json['contact'] as Map<String, dynamic>),
    linkedItems: [
      for (final i in (json['linked_items'] as List?) ?? const [])
        (
          kind: (i as Map<String, dynamic>)['kind'] as String,
          reference: i['reference'] as String? ?? '',
          title: i['title'] as String? ?? '',
          status: i['status'] as String? ?? '',
          auto: i['auto'] == true,
          at: DateTime.parse(i['created_at'] as String),
        ),
    ],
    reminders: [
      for (final r in (json['reminders'] as List?) ?? const [])
        ContactReminder.fromJson(r as Map<String, dynamic>),
    ],
  );

  final Contact contact;
  final List<
    ({
      String kind,
      String reference,
      String title,
      String status,
      bool auto,
      DateTime at,
    })
  >
  linkedItems;
  final List<ContactReminder> reminders;
}

class ContactEvent {
  const ContactEvent({
    required this.kind,
    required this.at,
    required this.label,
    this.text,
    this.actorName,
    this.reference,
  });

  factory ContactEvent.fromJson(Map<String, dynamic> json) => ContactEvent(
    kind: json['kind'] as String,
    at: DateTime.parse(json['at'] as String),
    // Kinds may be added: show the API's own sentence.
    label: json['label'] as String? ?? json['kind'] as String,
    text: json['text'] as String?,
    actorName: json['actor_name'] as String? ?? _name(json['actor']),
    reference: (json['ref'] as Map<String, dynamic>?)?['reference'] as String?,
  );

  final String kind;
  final DateTime at;
  final String label;
  final String? text;
  final String? actorName;
  final String? reference;
}

/// What to create a contact with (`ContactCreate`).
class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.type,
    this.emails = const [],
    this.phones = const [],
    this.tags = const [],
    this.stage = 'NEW',
    this.note,
    this.marketingGranted,
    this.marketingSource,
  });

  final String name;
  final String type;
  final List<String> emails;
  final List<String> phones;
  final List<String> tags;
  final String stage;
  final String? note;
  final bool? marketingGranted;
  final String? marketingSource;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'type': type,
    'emails': [
      for (final e in emails)
        if (e.trim().isNotEmpty) e.trim(),
    ],
    'phones': [
      for (final p in phones)
        if (p.trim().isNotEmpty) p.replaceAll(RegExp(r'[\s()-]'), ''),
    ],
    if (tags.isNotEmpty) 'tags': tags,
    'stage': stage,
    if (note != null && note!.trim().isNotEmpty) 'notes': note!.trim(),
    if (marketingGranted != null)
      'marketing_permission': {
        'granted': marketingGranted,
        if (marketingSource != null && marketingSource!.trim().isNotEmpty)
          'source': marketingSource!.trim(),
      },
  };
}

/// Another contact of the book already has one of these emails or phones
/// (`409 CONTACT_DUPLICATE`).
class DuplicateContacts implements Exception {
  const DuplicateContacts(this.duplicates);
  final List<({String id, String name})> duplicates;
}

typedef ContactPage = ({
  List<Contact> items,
  int total,
  int totalPages,
  Map<String, int> stageCounts,
});

/// The agent CRM (`/v1/agent/organisations/{book}/contacts`, API 0.31.0).
/// Another organisation's book is `404 CONTACT_NOT_FOUND`.
class ContactsRepository {
  ContactsRepository(this._api);

  final ApiClient _api;

  String _base(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}/contacts';
  String _one(String book, String id) =>
      '${_base(book)}/${Uri.encodeComponent(id)}';

  Future<ContactPage> list(
    String book, {
    String query = '',
    String? stage,
    bool dueOnly = false,
    int page = 1,
  }) async {
    final body = (await _api.get(
      Uri(
        path: _base(book),
        queryParameters: {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'stage': ?stage,
          if (dueOnly) 'has_reminder_due': 'true',
          'page': '$page',
          'page_size': '25',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final c in (body['items'] as List?) ?? const [])
          Contact.fromJson(c as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
      totalPages: body['total_pages'] as int? ?? 0,
      stageCounts: {
        for (final e
            in ((body['stage_counts'] as Map<String, dynamic>?) ?? const {})
                .entries)
          e.key: e.value as int? ?? 0,
      },
    );
  }

  Future<ContactDetail> get(String book, String id) async =>
      ContactDetail.fromJson((await _api.get(_one(book, id))).body);

  Future<List<ContactEvent>> timeline(String book, String id) async => [
    for (final e
        in ((await _api.get('${_one(book, id)}/timeline')).body['items']
                as List?) ??
            const [])
      ContactEvent.fromJson(e as Map<String, dynamic>),
  ];

  /// Throws [DuplicateContacts] when the book already has the email or
  /// phone, unless [allowDuplicate].
  Future<ContactDetail> create(
    String book,
    ContactDraft draft, {
    bool allowDuplicate = false,
  }) async {
    try {
      return ContactDetail.fromJson(
        (await _api.postJson(
          '${_base(book)}${allowDuplicate ? '?allow_duplicate=true' : ''}',
          draft.toJson(),
        )).body,
      );
    } on ApiFailure catch (failure) {
      if (failure.code != 'CONTACT_DUPLICATE') rethrow;
      throw DuplicateContacts([
        for (final d in (failure.details['duplicates'] as List?) ?? const [])
          (
            id: (d as Map<String, dynamic>)['id'] as String,
            name: d['name'] as String? ?? '',
          ),
      ]);
    }
  }

  Future<void> addNote(String book, String id, String text) =>
      _api.postJson('${_one(book, id)}/notes', {'text': text.trim()});

  Future<ContactReminder> addReminder(
    String book,
    String id,
    DateTime dueAt,
    String text,
  ) async => ContactReminder.fromJson(
    (await _api.postJson('${_one(book, id)}/reminders', {
      'due_at': dueAt.toUtc().toIso8601String(),
      'text': text.trim(),
    })).body,
  );

  Future<ContactReminder> setReminderDone(
    String book,
    String id,
    String reminderId,
    bool done,
  ) async => ContactReminder.fromJson(
    (await _api.patchJson(
      '${_one(book, id)}/reminders/${Uri.encodeComponent(reminderId)}',
      {'done': done},
    )).body,
  );

  Future<ContactDetail> moveStage(
    String book,
    String id,
    String stage, {
    String? note,
  }) async => ContactDetail.fromJson(
    (await _api.postJson('${_one(book, id)}/stage', {
      'stage': stage,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    })).body,
  );

  /// Creates a contact from a property request, business enquiry or
  /// appointment, or links it to the contact that already has its email or
  /// phone. `created` is false in the second case.
  Future<({ContactDetail detail, bool created})> fromRequest(
    String book,
    String requestId, {
    required String kind,
  }) async {
    final response = await _api.post(
      '${_base(book)}/from-request/${Uri.encodeComponent(requestId)}?kind=$kind',
    );
    return (
      detail: ContactDetail.fromJson(response.body),
      created: response.status == 201,
    );
  }

  /// Open reminders due by the end of today (overdue included).
  Future<List<ContactReminder>> dueReminders(String book) async => [
    for (final r
        in ((await _api.get('${_base(book)}/reminders?due=today')).body['items']
                as List?) ??
            const [])
      ContactReminder.fromJson(r as Map<String, dynamic>),
  ];

  /// The `contact_types` reference set, in display order.
  Future<Map<String, String>> types() async {
    try {
      final body = (await _api.get('/v1/reference/contact_types')).body;
      final items = (body['items'] as List?) ?? const [];
      if (items.isEmpty) return contactTypesFallback;
      return {
        for (final i in items)
          (i as Map<String, dynamic>)['code'] as String: i['label'] as String,
      };
    } on ApiFailure {
      return contactTypesFallback;
    }
  }
}
