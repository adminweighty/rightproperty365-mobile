import 'dart:math';

import '../../../core/api/api_client.dart';
import 'property_request.dart';

abstract interface class PropertyRequestRepository {
  /// Saves the request through the RightProperty365 API. Throws [ApiFailure].
  Future<PropertyRequestReceipt> submit(PropertyRequestDraft draft);
}

/// Sends every customer request to POST /v1/property-requests (BR-022,
/// FR-059). Customer details never go straight to an agent or a push provider.
class ApiPropertyRequestRepository implements PropertyRequestRepository {
  ApiPropertyRequestRepository(this._api, {String Function()? newKey})
    : _newKey = newKey ?? _randomKey;

  final ApiClient _api;
  final String Function() _newKey;

  // One key per logical request. A retry of unchanged content reuses it, so
  // the API returns the first receipt instead of creating a second lead.
  String? _key;
  String? _keyFingerprint;

  static const _messages = {
    404: 'This listing could not be found.',
    409: 'We already received a different request with this reference. Please try again.',
    410: 'This listing is no longer available for enquiries.',
    429: 'Too many requests. Please wait a minute and try again.',
  };

  @override
  Future<PropertyRequestReceipt> submit(PropertyRequestDraft draft) async {
    if (_key == null || _keyFingerprint != draft.fingerprint) {
      _key = _newKey();
      _keyFingerprint = draft.fingerprint;
    }
    final key = _key!;

    try {
      final response = await _api.postJson(
        '/v1/property-requests',
        draft.toJson(key),
        headers: {'Idempotency-Key': key},
      );
      _key = null;
      _keyFingerprint = null;
      return PropertyRequestReceipt.fromJson(response.body);
    } on ApiFailure catch (failure) {
      // A conflict means this key is spent; the next attempt needs a new one.
      if (failure.status == 409) _key = null;
      final message = failure.fields.isEmpty ? _messages[failure.status] : null;
      if (message == null) rethrow;
      throw ApiFailure(
        status: failure.status,
        code: failure.code,
        message: message,
        traceId: failure.traceId,
      );
    }
  }

  static String _randomKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
