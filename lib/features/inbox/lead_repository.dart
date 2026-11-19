import '../../core/api/api_client.dart';
import '../property_requests/data/request_message.dart';
import 'inbox_repository.dart';

/// A received property request in full (`ReceivedPropertyRequest`): the
/// lead stage, the moves allowed from it, the history and internal notes.
class Lead {
  const Lead({
    required this.enquiry,
    required this.stage,
    required this.allowedStages,
    required this.timeline,
    required this.notes,
    this.messages = const [],
  });

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
    enquiry: ReceivedEnquiry.fromPropertyRequest(json),
    stage: json['stage'] as String? ?? 'NEW_ENQUIRY',
    allowedStages: [
      for (final s in (json['allowed_stages'] as List?) ?? const [])
        (
          stage: (s as Map<String, dynamic>)['stage'] as String,
          label: s['label'] as String,
        ),
    ],
    timeline: [
      for (final e in (json['timeline'] as List?) ?? const [])
        (
          label: (e as Map<String, dynamic>)['label'] as String,
          who: e['actor_name'] as String?,
          at: DateTime.parse(e['at'] as String),
        ),
    ],
    notes: [
      for (final n in (json['notes'] as List?) ?? const [])
        (
          body: (n as Map<String, dynamic>)['body'] as String,
          author: n['author_name'] as String,
          mine: n['mine'] == true,
          at: DateTime.parse(n['created_at'] as String),
        ),
    ],
    messages: RequestMessage.listFrom(json['messages']),
  );

  final ReceivedEnquiry enquiry;
  final String stage;
  final List<({String stage, String label})> allowedStages;

  /// Oldest first.
  final List<({String label, String? who, DateTime at})> timeline;

  /// Internal to the receiving side; never shown to the customer.
  final List<({String body, String author, bool mine, DateTime at})> notes;

  /// The conversation with the customer, oldest first (API 0.46.0). The
  /// customer sees these; never the notes.
  final List<RequestMessage> messages;

  bool get closed => stage == 'CLOSED';
}

/// Working a received request (`/v1/agent/property-requests/{id}`).
abstract interface class LeadRepository {
  Future<Lead> get(String requestId);

  /// Moves the request to one of [Lead.allowedStages]. No email is sent.
  Future<Lead> moveTo(String requestId, String stage);

  /// Adds an internal note (1 to 2000 characters).
  Future<Lead> addNote(String requestId, String body);

  /// Replies to the customer (1 to 2000 characters). A NEW or ASSIGNED
  /// request moves to Contacted with it.
  Future<RequestMessage> reply(String requestId, String body);
}

class ApiLeadRepository implements LeadRepository {
  ApiLeadRepository(this._api);

  final ApiClient _api;

  String _path(String id) =>
      '/v1/agent/property-requests/${Uri.encodeComponent(id)}';

  Lead _lead(ApiResponse response) =>
      Lead.fromJson(response.body['request'] as Map<String, dynamic>);

  @override
  Future<Lead> get(String requestId) async =>
      _lead(await _api.get(_path(requestId)));

  @override
  Future<Lead> moveTo(String requestId, String stage) async {
    try {
      return _lead(await _api.patchJson(_path(requestId), {'stage': stage}));
    } on ApiFailure catch (failure) {
      throw failure.code == 'INVALID_STAGE_TRANSITION'
          ? failure.withMessage(
              'This request has moved on since you opened it. Refresh and try again.',
            )
          : failure;
    }
  }

  @override
  Future<RequestMessage> reply(String requestId, String body) async =>
      messageOf(
        await _api.postJson('${_path(requestId)}/messages', {
          'body': body.trim(),
        }),
      );

  @override
  Future<Lead> addNote(String requestId, String body) async => _lead(
    await _api.postJson('${_path(requestId)}/notes', {'body': body.trim()}),
  );
}
