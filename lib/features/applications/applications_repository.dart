import '../../core/api/api_client.dart';
import 'application_models.dart';

/// Applications are closed for this listing (`409 APPLICATIONS_CLOSED`).
class ApplicationsClosed implements Exception {
  const ApplicationsClosed(this.message, {this.reason});
  final String message;

  /// PAUSED, CLOSED, CLOSES_AT_PASSED, FORM_EXPIRED, FORM_RETIRED or NONE.
  final String? reason;
}

/// A file chosen on the phone, to upload to an application.
typedef ChosenFile = ({List<int> bytes, String name});

Application _one(ApiResponse r) =>
    Application.fromJson(r.body['application'] as Map<String, dynamic>);

Never _closedOr(ApiFailure failure) {
  if (failure.code == 'APPLICATIONS_CLOSED') {
    throw ApplicationsClosed(
      failure.message,
      reason: failure.details['reason'] as String?,
    );
  }
  throw failure;
}

/// The content type the API expects, from the file name.
String? fileContentType(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => null,
  };
}

/// A Property Seeker's own applications (`/v1/me/applications`).
class MyApplicationsRepository {
  MyApplicationsRepository(this._api);

  final ApiClient _api;
  static const _base = '/v1/me/applications';

  /// The form attached to a listing and whether intake is open; null when
  /// the listing takes no applications.
  Future<({ApplicationForm form, String status, String? reason})?> formFor(
    String slug,
  ) async {
    try {
      final body = (await _api.get(
        '/v1/listings/${Uri.encodeComponent(slug)}/application-form',
      )).body;
      final intake = body['intake'] as Map<String, dynamic>? ?? const {};
      return (
        form: ApplicationForm.fromJson(body['form'] as Map<String, dynamic>),
        status: intake['status'] as String? ?? 'NONE',
        reason: intake['closed_reason'] as String?,
      );
    } on ApiFailure catch (failure) {
      if (failure.status == 404) return null;
      rethrow;
    }
  }

  /// Starts (or reopens) this customer's application for [listingId].
  /// Throws [ApplicationsClosed].
  Future<Application> start(String listingId) async {
    try {
      return _one(await _api.postJson(_base, {'listing_id': listingId}));
    } on ApiFailure catch (failure) {
      _closedOr(failure);
    }
  }

  Future<List<Application>> list() async {
    final body = (await _api.get('$_base?page_size=50')).body;
    return [
      for (final a in (body['items'] as List?) ?? const [])
        Application.fromJson(a as Map<String, dynamic>),
    ];
  }

  Future<Application> get(String id) async =>
      _one(await _api.get('$_base/${Uri.encodeComponent(id)}'));

  /// Autosave: answers are merged; null removes one.
  Future<Application> save(String id, Map<String, Object?> answers) async =>
      _one(
        await _api.patchJson('$_base/${Uri.encodeComponent(id)}', {
          'answers': answers,
        }),
      );

  Future<Application> upload(String id, String field, ChosenFile file) async {
    try {
      return _one(
        await _api.postFile(
          '$_base/${Uri.encodeComponent(id)}/files?field=${Uri.encodeQueryComponent(field)}',
          field: 'file',
          bytes: file.bytes,
          fileName: file.name,
          contentType: fileContentType(file.name),
        ),
      );
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'UNSUPPORTED_FILE_TYPE' => failure.withMessage(
          'That kind of file is not accepted. Use a PDF, a photo (JPG, PNG, WebP, HEIC) or a Word document.',
        ),
        'FILE_TOO_LARGE' => failure.withMessage(
          'That file is over 10 MB. Choose a smaller one.',
        ),
        'TOO_MANY_FILES' => failure.withMessage(
          'This question takes no more files.',
        ),
        _ => failure,
      };
    }
  }

  Future<Application> removeFile(String id, String fileId) async => _one(
    await _api.delete(
      '$_base/${Uri.encodeComponent(id)}/files/${Uri.encodeComponent(fileId)}',
    ),
  );

  /// Throws [ApplicationsClosed]; a 400 carries the answers' problems in
  /// `fields` (`answers.<key>`).
  Future<Application> submit(String id) async {
    try {
      return _one(await _api.post('$_base/${Uri.encodeComponent(id)}/submit'));
    } on ApiFailure catch (failure) {
      _closedOr(failure);
    }
  }

  Future<Application> withdraw(String id) async =>
      _one(await _api.post('$_base/${Uri.encodeComponent(id)}/withdraw'));
}

/// Applications an organisation received
/// (`/v1/agent/organisations/{book}/applications`).
class AgentApplicationsRepository {
  AgentApplicationsRepository(this._api);

  final ApiClient _api;

  String _base(String org) =>
      '/v1/agent/organisations/${Uri.encodeComponent(org)}/applications';

  Future<({List<Application> items, Map<String, int> counts})> list(
    String org, {
    String? status,
    String query = '',
  }) async {
    final body = (await _api.get(
      Uri(
        path: _base(org),
        queryParameters: {
          'status': ?status,
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'page_size': '50',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final a in (body['items'] as List?) ?? const [])
          Application.fromJson(a as Map<String, dynamic>),
      ],
      counts: {
        for (final e
            in ((body['status_counts'] as Map<String, dynamic>?) ?? const {})
                .entries)
          e.key: e.value as int? ?? 0,
      },
    );
  }

  /// Reading the answers is recorded in the organisation's audit trail.
  Future<Application> get(String org, String id) async =>
      _one(await _api.get('${_base(org)}/${Uri.encodeComponent(id)}'));

  Future<Application> decide(
    String org,
    String id,
    String status, {
    String? note,
  }) async {
    try {
      return _one(
        await _api.postJson('${_base(org)}/${Uri.encodeComponent(id)}/status', {
          'status': status,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }),
      );
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'INVALID_APPLICATION_TRANSITION' ||
        'APPLICATION_CONFLICT' => failure.withMessage(
          'This application has changed since you opened it. Refresh to see where it stands.',
        ),
        _ => failure,
      };
    }
  }

  Future<Application> requestInfo(
    String org,
    String id,
    String message,
  ) async => _one(
    await _api.postJson(
      '${_base(org)}/${Uri.encodeComponent(id)}/request-info',
      {'message': message.trim()},
    ),
  );

  Future<void> addNote(String org, String id, String text) => _api.postJson(
    '${_base(org)}/${Uri.encodeComponent(id)}/notes',
    {'text': text.trim()},
  );
}
