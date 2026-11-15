import '../../core/api/api_client.dart';
import '../../core/terminology.dart';
import '../property_requests/data/property_request.dart';

/// An enquiry a professional or property owner has received.
///
/// It carries the Property Seeker's contact details, which the API returns
/// only to the authorised recipient. Do not cache it on the device.
class ReceivedEnquiry {
  const ReceivedEnquiry({
    required this.reference,
    required this.subject,
    required this.kind,
    required this.status,
    this.stageLabel,
    required this.message,
    required this.contactMethod,
    required this.contactName,
    required this.contactEmail,
    required this.receivedAt,
    this.contactPhone,
    this.listingSlug,
  });

  /// From GET /v1/agent/property-requests (`OrganisationPropertyRequest`).
  factory ReceivedEnquiry.fromPropertyRequest(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>?;
    final type = json['request_type'] as String;
    return ReceivedEnquiry(
      reference: json['reference'] as String,
      subject: listing?['title'] as String? ?? 'Property enquiry',
      kind: RequestType.values
          .firstWhere((t) => t.wire == type, orElse: () => RequestType.enquiry)
          .label,
      listingSlug: listing?['slug'] as String?,
      status: json['status'] as String,
      stageLabel: json['stage_label'] as String?,
      message: json['message'] as String,
      contactMethod: json['preferred_contact_method'] as String,
      contactName: json['contact']['name'] as String,
      contactEmail: json['contact']['email'] as String,
      contactPhone: json['contact']['phone'] as String?,
      receivedAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// From GET /v1/inbox/business-enquiries (`ReceivedBusinessEnquiry`).
  factory ReceivedEnquiry.fromBusinessEnquiry(Map<String, dynamic> json) =>
      ReceivedEnquiry(
        reference: json['reference'] as String,
        subject: json['service'] as String? ?? 'General enquiry',
        kind: 'To ${json['recipient']['name']}',
        status: json['status'] as String,
        message: json['message'] as String,
        contactMethod: json['preferred_contact_method'] as String,
        contactName: json['contact']['name'] as String,
        contactEmail: json['contact']['email'] as String,
        contactPhone: json['contact']['phone'] as String?,
        receivedAt: DateTime.parse(json['created_at'] as String),
      );

  final String reference;

  /// The listing title, or the service asked about.
  final String subject;

  /// The request type for a listing, or who the enquiry was addressed to.
  final String kind;
  final String? listingSlug;
  final String status;

  /// The lead stage's wording from the API (property requests only).
  final String? stageLabel;
  final String message;

  /// EMAIL, PHONE or WHATSAPP: how the Property Seeker wants the reply.
  final String contactMethod;
  final String contactName;
  final String contactEmail;
  final String? contactPhone;
  final DateTime receivedAt;

  String get statusLabel => stageLabel ?? enquiryStatusLabel(status);

  String get replyBy => switch (contactMethod) {
    'PHONE' => 'Phone call',
    'WHATSAPP' => 'WhatsApp',
    _ => 'Email',
  };
}

abstract interface class InboxRepository {
  /// Every enquiry the signed-in person is authorised to see, newest first.
  /// Throws [ApiFailure]; status 403 means the account has no inbox.
  Future<List<ReceivedEnquiry>> received();
}

/// Enquiries about listings and enquiries to directory profiles, merged.
///
/// The API decides what each person sees from their listing assignments,
/// property ownership and organisation memberships: an Agency Principal sees
/// the whole agency, an Estate Agent or Solicitor their own.
class ApiInboxRepository implements InboxRepository {
  ApiInboxRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ReceivedEnquiry>> received() async {
    final results = await Future.wait([
      // Paged since API 0.20.0: the newest 100, the most one page holds.
      _list(
        '/v1/agent/property-requests?page_size=100',
        ReceivedEnquiry.fromPropertyRequest,
      ),
      _list(
        '/v1/inbox/business-enquiries',
        ReceivedEnquiry.fromBusinessEnquiry,
      ),
    ]);
    final (listings, business) = (results[0], results[1]);
    if (listings == null && business == null) {
      throw const ApiFailure(
        status: 403,
        code: 'FORBIDDEN',
        message: 'This account does not have an enquiries inbox.',
      );
    }
    return [...?listings, ...?business]
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  /// The items of one inbox, or null when this account may not open it.
  Future<List<ReceivedEnquiry>?> _list(
    String path,
    ReceivedEnquiry Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = await _api.get(path);
      return [
        for (final item in (response.body['items'] as List?) ?? const [])
          parse(item as Map<String, dynamic>),
      ];
    } on ApiFailure catch (failure) {
      if (failure.status == 403) return null;
      rethrow;
    }
  }
}
