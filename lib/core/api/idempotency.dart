import 'dart:math';

/// Hands out one idempotency key per logical request.
///
/// A retry of unchanged content reuses the key, so the API returns the first
/// receipt instead of saving a duplicate. Changed content, a success, or a
/// conflict starts a new key.
class IdempotencyKeys {
  IdempotencyKeys([String Function()? newKey]) : _newKey = newKey ?? randomKey;

  final String Function() _newKey;
  String? _key;
  String? _fingerprint;

  /// The key for content identified by [fingerprint].
  String keyFor(String fingerprint) {
    if (_key == null || _fingerprint != fingerprint) {
      _key = _newKey();
      _fingerprint = fingerprint;
    }
    return _key!;
  }

  /// Call after a success or a 409, when the current key is spent.
  void reset() => _key = null;

  static String randomKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
