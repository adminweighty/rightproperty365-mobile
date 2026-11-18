import '../../core/api/api_client.dart';
import '../property_requests/data/property_request.dart';

/// A property request as the Property Seeker who sent it sees it
/// (`CustomerPropertyRequest`): the customer status, never the lead stage,
/// the recipient or internal notes.
class MyRequest {
  const MyRequest({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.statusLabel,
    required this.message,
    required this.contactMethod,
    required this.createdAt,
    this.listingSlug,
    this.listingTitle,
    this.preferredSlotUtc,
    this.timeline = const [],
  });

  factory MyRequest.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>?;
    return MyRequest(
      id: json['request_id'] as String,
      reference: json['reference'] as String,
      type: json['request_type'] as String,
      status: json['status'] as String,
      statusLabel: json['status_label'] as String? ?? json['status'] as String,
      message: json['message'] as String? ?? '',
      contactMethod: json['preferred_contact_method'] as String? ?? 'EMAIL',
      createdAt: DateTime.parse(json['created_at'] as String),
      listingSlug: listing?['slug'] as String?,
      listingTitle: listing?['title'] as String?,
      preferredSlotUtc: switch (json['preferred_slot_utc']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      timeline: [
        for (final entry in (json['timeline'] as List?) ?? const [])
          (
            label: (entry as Map<String, dynamic>)['status_label'] as String,
            received: entry['event'] == 'RECEIVED',
            at: DateTime.parse(entry['at'] as String),
          ),
      ],
    );
  }

  final String id;
  final String reference;
  final String type;

  /// RECEIVED, IN_PROGRESS, RESPONDED, VIEWING_SCHEDULED or CLOSED.
  final String status;
  final String statusLabel;
  final String message;
  final String contactMethod;
  final DateTime createdAt;

  /// Null when the listing no longer has a public page.
  final String? listingSlug;
  final String? listingTitle;
  final DateTime? preferredSlotUtc;

  /// Only on a single request: when its status changed, oldest first.
  final List<({String label, bool received, DateTime at})> timeline;

  String get typeLabel => type == 'STAY_REQUEST'
      ? 'Request to stay'
      : RequestType.values
            .firstWhere(
              (t) => t.wire == type,
              orElse: () => RequestType.enquiry,
            )
            .label;
}

/// The requests this account sent while signed in (`/v1/me/property-requests`).
/// Requests sent as a guest are never linked to the account.
abstract interface class MyRequestsRepository {
  /// Newest first: the latest 50.
  Future<({List<MyRequest> items, int total})> list();

  /// One request with its status history.
  Future<MyRequest> get(String id);
}

class ApiMyRequestsRepository implements MyRequestsRepository {
  ApiMyRequestsRepository(this._api);

  final ApiClient _api;

  @override
  Future<({List<MyRequest> items, int total})> list() async {
    final response = await _api.get('/v1/me/property-requests?page_size=50');
    return (
      items: [
        for (final item in (response.body['items'] as List?) ?? const [])
          MyRequest.fromJson(item as Map<String, dynamic>),
      ],
      total: response.body['total'] as int? ?? 0,
    );
  }

  @override
  Future<MyRequest> get(String id) async {
    final response = await _api.get(
      '/v1/me/property-requests/${Uri.encodeComponent(id)}',
    );
    return MyRequest.fromJson(response.body['request'] as Map<String, dynamic>);
  }
}
