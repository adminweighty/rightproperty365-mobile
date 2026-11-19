import '../../../core/api/api_client.dart';
import '../../../core/api/idempotency.dart';
import '../../enquiries/data/enquiry.dart';
import 'profile.dart';

/// Body of POST /v1/business-enquiries: an enquiry to a directory profile,
/// or (API 0.44.0) about a development project, which reaches its developer.
class BusinessEnquiryDraft {
  const BusinessEnquiryDraft({
    this.recipient,
    this.development,
    required this.message,
    required this.contactMethod,
    required this.contact,
    required this.consentAccepted,
    required this.privacyVersion,
    this.service,
  });

  /// The profile, or null for a project's enquiry (the API sends it to
  /// the project's developer).
  final Profile? recipient;

  /// The project, and the unit type when the customer asked about one.
  final ({String market, String slug, String? unitTypeId})? development;

  /// One of the recipient's listed services, when the customer picked one.
  final String? service;
  final String message;
  final ContactMethod contactMethod;
  final EnquiryContact contact;
  final bool consentAccepted;
  final String privacyVersion;

  Map<String, dynamic> toJson(String idempotencyKey) => {
    if (recipient case final r?)
      'recipient': {'kind': r.kind.slug, 'slug': r.slug},
    if (development case final d?)
      'development': {
        'market': d.market,
        'slug': d.slug,
        'unit_type_id': ?d.unitTypeId,
      },
    'service': ?service,
    'message': message.trim(),
    'preferred_contact_method': contactMethod.wire,
    'idempotency_key': idempotencyKey,
    'guest_contact': ?contact.toJson(),
    'consent': {'privacy_version': privacyVersion, 'accepted': consentAccepted},
  };

  String get fingerprint => toJson('').toString();
}

abstract interface class BusinessEnquiryRepository {
  /// Saves the enquiry through the RightProperty365 API. Throws [ApiFailure].
  Future<EnquiryReceipt> submit(BusinessEnquiryDraft draft);
}

/// Profiles never show a phone number or email address. This endpoint is the
/// only way to reach them, so every enquiry is recorded by RightProperty365.
class ApiBusinessEnquiryRepository implements BusinessEnquiryRepository {
  ApiBusinessEnquiryRepository(this._api, {String Function()? newKey})
    : _keys = IdempotencyKeys(newKey);

  final ApiClient _api;
  final IdempotencyKeys _keys;

  static const _messages = {
    // Also what the API answers while the endpoint is not deployed yet.
    404: 'Enquiries to this profile are not available yet. Please try again later.',
    409: 'We already received a different enquiry with this reference. Please try again.',
    410: 'This profile is no longer accepting enquiries.',
    429: 'Too many requests. Please wait a minute and try again.',
  };

  @override
  Future<EnquiryReceipt> submit(BusinessEnquiryDraft draft) async {
    final key = _keys.keyFor(draft.fingerprint);
    try {
      final response = await _api.postJson(
        '/v1/business-enquiries',
        draft.toJson(key),
        headers: {'Idempotency-Key': key},
      );
      _keys.reset();
      return EnquiryReceipt.fromJson(response.body, 'enquiry_id');
    } on ApiFailure catch (failure) {
      if (failure.status == 409) _keys.reset();
      if (failure.code == 'DEVELOPMENT_NOT_FOUND') {
        throw failure.withMessage(
          'This project is no longer taking enquiries. It may have been taken '
          'down.',
        );
      }
      final message = failure.fields.isEmpty ? _messages[failure.status] : null;
      if (message == null) rethrow;
      throw failure.withMessage(message);
    }
  }
}
