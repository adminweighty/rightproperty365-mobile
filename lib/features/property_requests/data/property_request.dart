import '../../enquiries/data/enquiry.dart';

enum RequestType {
  enquiry('ENQUIRY', 'General enquiry'),
  propertyInformation('PROPERTY_INFORMATION', 'More information'),
  viewingRequest('VIEWING_REQUEST', 'Book a viewing'),
  consultationRequest('CONSULTATION_REQUEST', 'Request a consultation');

  const RequestType(this.wire, this.label);
  final String wire;
  final String label;

  /// Only these types may carry a preferred slot.
  bool get allowsSlot => this == viewingRequest || this == consultationRequest;
}

/// Body of POST /v1/property-requests.
class PropertyRequestDraft {
  const PropertyRequestDraft({
    required this.listingId,
    required this.requestType,
    required this.message,
    required this.contactMethod,
    required this.contact,
    required this.consentAccepted,
    required this.privacyVersion,
    this.preferredSlot,
  });

  final String listingId;
  final RequestType requestType;
  final String message;
  final ContactMethod contactMethod;
  final EnquiryContact contact;
  final bool consentAccepted;
  final String privacyVersion;

  /// Any time zone; it is sent as UTC.
  final DateTime? preferredSlot;

  Map<String, dynamic> toJson(String idempotencyKey) => {
    'listing_id': listingId,
    'request_type': requestType.wire,
    'message': message.trim(),
    'preferred_contact_method': contactMethod.wire,
    if (preferredSlot != null && requestType.allowsSlot)
      'preferred_slot_utc': preferredSlot!.toUtc().toIso8601String(),
    'idempotency_key': idempotencyKey,
    'guest_contact': ?contact.toJson(),
    'consent': {'privacy_version': privacyVersion, 'accepted': consentAccepted},
  };

  /// Identifies the content, so a retry can tell whether anything changed.
  String get fingerprint => toJson('').toString();
}
