enum RequestType {
  enquiry('ENQUIRY', 'General enquiry'),
  propertyInformation('PROPERTY_INFORMATION', 'More information'),
  viewingRequest('VIEWING_REQUEST', 'Book a viewing'),
  consultationRequest('CONSULTATION_REQUEST', 'Speak to the agent');

  const RequestType(this.wire, this.label);
  final String wire;
  final String label;

  /// Only these types may carry a preferred slot.
  bool get allowsSlot => this == viewingRequest || this == consultationRequest;
}

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

/// Body of POST /v1/property-requests for a guest (signed-out) customer.
class PropertyRequestDraft {
  const PropertyRequestDraft({
    required this.listingId,
    required this.requestType,
    required this.message,
    required this.contactMethod,
    required this.name,
    required this.email,
    required this.consentAccepted,
    required this.privacyVersion,
    this.phone,
    this.preferredSlot,
  });

  final String listingId;
  final RequestType requestType;
  final String message;
  final ContactMethod contactMethod;
  final String name;
  final String email;
  final String? phone;
  final bool consentAccepted;
  final String privacyVersion;

  /// Any time zone; it is sent as UTC.
  final DateTime? preferredSlot;

  /// Drops the spaces, dashes and brackets people type; the API wants E.164.
  static String? normalisePhone(String? input) {
    final cleaned = (input ?? '').replaceAll(RegExp(r'[\s()\-]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  Map<String, dynamic> toJson(String idempotencyKey) {
    final phoneNumber = normalisePhone(phone);
    return {
      'listing_id': listingId,
      'request_type': requestType.wire,
      'message': message.trim(),
      'preferred_contact_method': contactMethod.wire,
      if (preferredSlot != null && requestType.allowsSlot)
        'preferred_slot_utc': preferredSlot!.toUtc().toIso8601String(),
      'idempotency_key': idempotencyKey,
      'guest_contact': {
        'name': name.trim(),
        'email': email.trim(),
        'phone': ?phoneNumber,
      },
      'consent': {
        'privacy_version': privacyVersion,
        'accepted': consentAccepted,
      },
    };
  }

  /// Identifies the content, so a retry can tell whether anything changed.
  String get fingerprint => toJson('').toString();
}

/// What the API returns once a request is saved. `status` is RECEIVED: saved
/// and queued for routing. It never means delivered or read.
class PropertyRequestReceipt {
  const PropertyRequestReceipt({
    required this.requestId,
    required this.reference,
    required this.status,
    required this.createdAt,
  });

  factory PropertyRequestReceipt.fromJson(Map<String, dynamic> json) =>
      PropertyRequestReceipt(
        requestId: json['request_id'] as String,
        reference: json['reference'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String requestId;
  final String reference;
  final String status;
  final DateTime createdAt;
}
