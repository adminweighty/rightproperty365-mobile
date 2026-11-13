import '../../../core/api/api_client.dart';
import '../../../core/api/idempotency.dart';
import '../../enquiries/data/enquiry.dart';
import 'property_request.dart';

abstract interface class PropertyRequestRepository {
  /// Saves the request through the RightProperty365 API. Throws [ApiFailure].
  Future<EnquiryReceipt> submit(PropertyRequestDraft draft);
}

/// Sends every customer request to POST /v1/property-requests (BR-022,
/// FR-059). Customer details never go straight to an agent or a push provider.
class ApiPropertyRequestRepository implements PropertyRequestRepository {
  ApiPropertyRequestRepository(this._api, {String Function()? newKey})
    : _keys = IdempotencyKeys(newKey);

  final ApiClient _api;
  final IdempotencyKeys _keys;

  static const _messages = {
    404: 'This listing could not be found.',
    409: 'We already received a different request with this reference. Please try again.',
    410: 'This listing is no longer available for enquiries.',
    429: 'Too many requests. Please wait a minute and try again.',
  };

  @override
  Future<EnquiryReceipt> submit(PropertyRequestDraft draft) async {
    final key = _keys.keyFor(draft.fingerprint);
    try {
      final response = await _api.postJson(
        '/v1/property-requests',
        draft.toJson(key),
        headers: {'Idempotency-Key': key},
      );
      _keys.reset();
      return EnquiryReceipt.fromJson(response.body, 'request_id');
    } on ApiFailure catch (failure) {
      if (failure.status == 409) _keys.reset();
      final message = failure.fields.isEmpty ? _messages[failure.status] : null;
      if (message == null) rethrow;
      throw failure.withMessage(message);
    }
  }
}
