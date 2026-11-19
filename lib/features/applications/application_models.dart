/// Questionnaires and applications (API 0.32.0): a published form version,
/// the answers to it, and an application's status.
library;

import '../../core/api/scan.dart';

const applicationFileTypes = ['pdf', 'jpg', 'png', 'webp', 'heic', 'docx'];
const maxFileBytes = 10 * 1024 * 1024;

class FormOption {
  const FormOption(this.value, this.label);
  final String value;
  final String label;
}

/// When a field shows: another, earlier choice field equals a value or is
/// one of several.
class VisibleIf {
  const VisibleIf({required this.field, this.equals, this.anyOf});

  static VisibleIf? fromJson(Object? json) => json is Map<String, dynamic>
      ? VisibleIf(
          field: json['field'] as String,
          equals: json['equals'] as String?,
          anyOf: (json['in'] as List?)?.cast<String>(),
        )
      : null;

  final String field;
  final String? equals;
  final List<String>? anyOf;

  bool matches(Object? answer) {
    final wanted = anyOf ?? [?equals];
    // A multiple-choice answer matches when it contains the value.
    if (answer is List) return answer.any((a) => wanted.contains(a));
    return answer is String && wanted.contains(answer);
  }
}

class FormFieldSpec {
  const FormFieldSpec({
    required this.key,
    required this.type,
    required this.label,
    this.required = false,
    this.help,
    this.options = const [],
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.minDate,
    this.maxDate,
    this.accept = applicationFileTypes,
    this.maxFiles = 1,
    this.visibleIf,
  });

  factory FormFieldSpec.fromJson(Map<String, dynamic> json) => FormFieldSpec(
    key: json['key'] as String,
    type: json['type'] as String,
    label: json['label'] as String,
    required: json['required'] == true,
    help: json['help'] as String?,
    options: [
      for (final o in (json['options'] as List?) ?? const [])
        FormOption(
          (o as Map<String, dynamic>)['value'] as String,
          o['label'] as String,
        ),
    ],
    min: json['min'] as num?,
    max: json['max'] as num?,
    minLength: json['min_length'] as int?,
    maxLength: json['max_length'] as int?,
    minDate: json['min_date'] as String?,
    maxDate: json['max_date'] as String?,
    accept: (json['accept'] as List?)?.cast<String>() ?? applicationFileTypes,
    maxFiles: json['max_files'] as int? ?? 1,
    visibleIf: VisibleIf.fromJson(json['visible_if']),
  );

  final String key;

  /// short_text, long_text, number, date, single_choice, multiple_choice,
  /// file.
  final String type;
  final String label;
  final bool required;
  final String? help;
  final List<FormOption> options;
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final String? minDate;
  final String? maxDate;
  final List<String> accept;
  final int maxFiles;
  final VisibleIf? visibleIf;

  int get textLimit => maxLength ?? (type == 'long_text' ? 5000 : 200);

  /// Plain words for what is wrong with [value], or null. Missing answers are
  /// only a problem at submit ([required]).
  String? problem(Object? value) {
    final empty =
        value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty);
    if (empty) return required ? 'This question needs an answer.' : null;
    switch (type) {
      case 'short_text' || 'long_text':
        final length = (value as String).trim().length;
        if (minLength != null && length < minLength!) {
          return 'Write at least $minLength characters.';
        }
        if (length > textLimit) return 'Keep it to $textLimit characters.';
      case 'number':
        final n = value is num ? value : num.tryParse('$value');
        if (n == null) return 'Enter a number.';
        if (min != null && n < min!) return 'The lowest allowed is $min.';
        if (max != null && n > max!) return 'The highest allowed is $max.';
      case 'multiple_choice':
        final count = (value as List).length;
        if (min != null && count < min!) return 'Choose at least $min.';
        if (max != null && count > max!) return 'Choose at most $max.';
      case 'date':
        final d = '$value';
        if (minDate != null && d.compareTo(minDate!) < 0) {
          return 'Choose $minDate or later.';
        }
        if (maxDate != null && d.compareTo(maxDate!) > 0) {
          return 'Choose $maxDate or earlier.';
        }
    }
    return null;
  }
}

class FormSectionSpec {
  const FormSectionSpec({
    required this.key,
    required this.title,
    this.description,
    this.fields = const [],
  });

  factory FormSectionSpec.fromJson(Map<String, dynamic> json) =>
      FormSectionSpec(
        key: json['key'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        fields: [
          for (final f in (json['fields'] as List?) ?? const [])
            FormFieldSpec.fromJson(f as Map<String, dynamic>),
        ],
      );

  final String key;
  final String title;
  final String? description;
  final List<FormFieldSpec> fields;
}

/// A published form version, as an applicant sees it (`PublicForm`).
class ApplicationForm {
  const ApplicationForm({
    required this.id,
    required this.version,
    required this.name,
    this.purpose = '',
    this.privacyNotice = '',
    this.retentionDays,
    this.sections = const [],
  });

  factory ApplicationForm.fromJson(Map<String, dynamic> json) =>
      ApplicationForm(
        id: json['id'] as String,
        version: json['version'] as int? ?? 1,
        name: json['name'] as String? ?? 'Application',
        purpose: json['purpose'] as String? ?? '',
        privacyNotice: json['privacy_notice'] as String? ?? '',
        retentionDays: json['retention_days'] as int?,
        sections: [
          for (final s in (json['sections'] as List?) ?? const [])
            FormSectionSpec.fromJson(s as Map<String, dynamic>),
        ],
      );

  final String id;
  final int version;
  final String name;
  final String purpose;
  final String privacyNotice;
  final int? retentionDays;
  final List<FormSectionSpec> sections;

  Iterable<FormFieldSpec> get fields => sections.expand((s) => s.fields);

  /// Whether [field] shows with these answers (a hidden field is not
  /// required and its answer is dropped on submit).
  bool visible(FormFieldSpec field, Map<String, Object?> answers) {
    final rule = field.visibleIf;
    return rule == null || rule.matches(answers[rule.field]);
  }

  /// Every problem with the visible fields, keyed by field key.
  Map<String, String> problems(Map<String, Object?> answers) => {
    for (final f in fields)
      if (visible(f, answers))
        if (f.problem(answers[f.key]) case final String p) f.key: p,
  };
}

class ApplicationFile {
  const ApplicationFile({
    required this.id,
    required this.field,
    required this.fileName,
    required this.size,
    this.scan = ScanStatus.none,
  });

  factory ApplicationFile.fromJson(Map<String, dynamic> json) =>
      ApplicationFile(
        id: json['id'] as String,
        field: json['field'] as String? ?? '',
        fileName: json['file_name'] as String? ?? 'file',
        size: json['size'] as int? ?? 0,
        scan: ScanStatus.parse(json['scan_status']),
      );

  final String id;
  final String field;
  final String fileName;
  final int size;

  /// The virus check (API 0.41.0); none when scanning is off.
  final ScanStatus scan;
}

typedef ApplicationEvent = ({
  String kind,
  String label,
  String? message,
  String? actorName,
  DateTime at,
});

/// An application, from either side (`ApplicantApplication` or
/// `AgentApplication`).
class Application {
  const Application({
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.listingId,
    required this.listingTitle,
    this.reference,
    this.listingSlug,
    this.form,
    this.formName,
    this.answers = const {},
    this.files = const [],
    this.missingRequired = const [],
    this.infoRequest,
    this.timeline = const [],
    this.canEdit = false,
    this.canSubmit = false,
    this.canWithdraw = false,
    this.erased = false,
    this.submittedAt,
    this.updatedAt,
    this.applicantName,
    this.applicantEmail,
    this.rendered = const [],
    this.notes = const [],
    this.allowedTransitions = const [],
  });

  factory Application.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>? ?? const {};
    final form = json['form'] as Map<String, dynamic>?;
    final info = json['info_request'] as Map<String, dynamic>?;
    final applicant = json['applicant'] as Map<String, dynamic>?;
    return Application(
      id: json['id'] as String,
      reference: json['reference'] as String?,
      status: json['status'] as String,
      statusLabel: json['status_label'] as String? ?? json['status'] as String,
      listingId: json['listing_id'] as String? ?? '',
      listingTitle: listing['title'] as String? ?? 'Property',
      listingSlug: listing['slug'] as String?,
      form: form != null && form.containsKey('sections')
          ? ApplicationForm.fromJson(form)
          : null,
      formName: form?['name'] as String?,
      answers: Map<String, Object?>.from(
        json['answers'] as Map<String, dynamic>? ?? const {},
      ),
      files: [
        for (final f in (json['files'] as List?) ?? const [])
          ApplicationFile.fromJson(f as Map<String, dynamic>),
      ],
      missingRequired:
          (json['missing_required'] as List?)?.cast<String>() ?? const [],
      infoRequest: info?['message'] as String?,
      timeline: [
        for (final e in (json['timeline'] as List?) ?? const [])
          (
            kind: (e as Map<String, dynamic>)['kind'] as String? ?? '',
            label: e['label'] as String? ?? '',
            message: e['message'] as String?,
            actorName: e['actor_name'] as String?,
            at: DateTime.parse(e['at'] as String),
          ),
      ],
      canEdit: json['can_edit'] == true,
      canSubmit: json['can_submit'] == true,
      canWithdraw: json['can_withdraw'] == true,
      erased: json['erased'] == true,
      submittedAt: switch (json['submitted_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      updatedAt: switch (json['updated_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      applicantName: applicant?['name'] as String?,
      applicantEmail: applicant?['email'] as String?,
      rendered: [
        for (final s in (json['rendered'] as List?) ?? const [])
          (
            title: (s as Map<String, dynamic>)['title'] as String? ?? '',
            fields: [
              for (final f in (s['fields'] as List?) ?? const [])
                if ((f as Map<String, dynamic>)['visible'] != false)
                  (
                    label: f['label'] as String? ?? '',
                    display: f['display'] as String?,
                    files: [
                      for (final file in (f['files'] as List?) ?? const [])
                        ApplicationFile.fromJson(file as Map<String, dynamic>),
                    ],
                  ),
            ],
          ),
      ],
      notes: [
        for (final n in (json['notes'] as List?) ?? const [])
          (
            text: (n as Map<String, dynamic>)['text'] as String? ?? '',
            author: n['author_name'] as String? ?? '',
            at: DateTime.parse(n['created_at'] as String),
          ),
      ],
      allowedTransitions:
          (json['allowed_transitions'] as List?)?.cast<String>() ?? const [],
    );
  }

  final String id;

  /// RPA-APP-2026-000001, once submitted.
  final String? reference;
  final String status;
  final String statusLabel;
  final String listingId;
  final String listingTitle;

  /// Null when the listing is no longer public.
  final String? listingSlug;

  /// The exact version the application was started or submitted on (not
  /// in lists).
  final ApplicationForm? form;
  final String? formName;
  final Map<String, Object?> answers;
  final List<ApplicationFile> files;
  final List<String> missingRequired;

  /// What the agent asked for (MORE_INFO).
  final String? infoRequest;
  final List<ApplicationEvent> timeline;
  final bool canEdit;
  final bool canSubmit;
  final bool canWithdraw;

  /// Answers and files removed by retention or account deletion.
  final bool erased;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  /// Agent side only.
  final String? applicantName;
  final String? applicantEmail;
  final List<
    ({
      String title,
      List<({String label, String? display, List<ApplicationFile> files})>
      fields,
    })
  >
  rendered;
  final List<({String text, String author, DateTime at})> notes;
  final List<String> allowedTransitions;
}

/// The plain words for an agent's possible decision.
String transitionLabel(String status) => switch (status) {
  'UNDER_REVIEW' => 'Mark as in review',
  'SHORTLISTED' => 'Shortlist',
  'ACCEPTED' => 'Accept',
  'REJECTED' => 'Decline',
  _ => status,
};
