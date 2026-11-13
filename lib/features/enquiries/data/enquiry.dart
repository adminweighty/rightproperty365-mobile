/// Pieces shared by listing requests (`/v1/property-requests`) and directory
/// enquiries (`/v1/business-enquiries`).
library;

enum ContactMethod {
  email('EMAIL', 'Email'),
  phone('PHONE', 'Phone call'),
  whatsapp('WHATSAPP', 'WhatsApp');

  const ContactMethod(this.wire, this.label);
  final String wire;
  final String label;

  /// The API rejects PHONE and WHATSAPP without a phone number.
  bool get needsPhone => this != email;
}

/// Who is asking. When the customer is signed in, [name] and [email] are null
/// and the API uses their profile.
class EnquiryContact {
  const EnquiryContact({this.name, this.email, this.phone});

  final String? name;
  final String? email;
  final String? phone;

  /// Drops the spaces, dashes and brackets people type; the API wants E.164.
  static String? normalisePhone(String? input) {
    final cleaned = (input ?? '').replaceAll(RegExp(r'[\s()\-]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _clean(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The `guest_contact` object, or null when there is nothing to send.
  Map<String, dynamic>? toJson() {
    final json = {
      'name': ?_clean(name),
      'email': ?_clean(email),
      'phone': ?normalisePhone(phone),
    };
    return json.isEmpty ? null : json;
  }
}

/// What the API returns once an enquiry is saved. `status` is RECEIVED: saved
/// and queued for routing. It never means delivered or read.
class EnquiryReceipt {
  const EnquiryReceipt({
    required this.id,
    required this.reference,
    required this.status,
    required this.createdAt,
  });

  /// [idField] is `request_id` for listing requests and `enquiry_id` for
  /// business enquiries.
  factory EnquiryReceipt.fromJson(Map<String, dynamic> json, String idField) =>
      EnquiryReceipt(
        id: json[idField] as String,
        reference: json['reference'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String reference;
  final String status;
  final DateTime createdAt;
}
