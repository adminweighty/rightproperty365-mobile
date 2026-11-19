import '../../../core/api/api_client.dart';

/// One message in the conversation on a property request (API 0.46.0),
/// between the customer and the professional working it. Private notes are
/// never messages.
class RequestMessage {
  const RequestMessage({
    required this.id,
    required this.fromProfessional,
    required this.authorName,
    required this.body,
    required this.at,
    required this.mine,
  });

  factory RequestMessage.fromJson(Map<String, dynamic> json) => RequestMessage(
    id: json['id'] as String,
    fromProfessional: json['author'] == 'PROFESSIONAL',
    authorName: json['author_name'] as String? ?? '',
    body: json['body'] as String? ?? '',
    at: DateTime.parse(json['created_at'] as String),
    mine: json['mine'] == true,
  );

  static List<RequestMessage> listFrom(Object? json) => [
    for (final m in (json as List?) ?? const [])
      RequestMessage.fromJson(m as Map<String, dynamic>),
  ];

  final String id;
  final bool fromProfessional;

  /// The agency or seller's public name, the customer's name as on the
  /// request, or "You". Never an email address or phone number.
  final String authorName;

  /// Plain text, 1 to 2000 characters.
  final String body;
  final DateTime at;
  final bool mine;
}

/// The longest message the API accepts.
const requestMessageMax = 2000;

/// The posted message (`201`), whether sent bare or under `message`.
RequestMessage messageOf(ApiResponse response) =>
    RequestMessage.fromJson(switch (response.body['message']) {
      final Map<String, dynamic> m => m,
      _ => response.body,
    });
