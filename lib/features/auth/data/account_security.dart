/// Account security while signed in (API 0.50.0): change the password, see
/// and end signed-in sessions, change the email address.
library;

import '../../../core/api/api_client.dart';
import 'auth_models.dart';

/// One signed-in session of the account (`GET /v1/me/sessions`).
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.client,
    required this.current,
    this.createdAt,
    this.lastSeenAt,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
    id: json['id'] as String,
    client: switch (json['client']) {
      final String s when s.trim().isNotEmpty => s,
      _ => 'Unknown device',
    },
    current: json['current'] == true,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
  );

  final String id;

  /// "Chrome on Windows", "RightProperty365 app on Android" or "Unknown
  /// device", as recorded at sign-in. No IP address is kept.
  final String client;

  /// This phone's own session.
  final bool current;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
}

class AccountSecurityRepository {
  AccountSecurityRepository(this._api);

  final ApiClient _api;

  /// Sets a new password. Every other session is signed out; this one stays.
  /// A wrong current password is `400` with `fields.current_password`.
  Future<void> changePassword({
    required String current,
    required String next,
  }) => _api.postJson('/v1/me/password', {
    'current_password': current,
    'new_password': next,
  });

  /// Active sessions, newest first.
  Future<List<DeviceSession>> sessions() async {
    final body = (await _api.get('/v1/me/sessions')).body;
    return [
      for (final s in (body['items'] as List?) ?? const [])
        DeviceSession.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Signs another device out. (This device signs out through the normal
  /// sign-out, which also removes its push token.)
  Future<void> signOutSession(String id) async {
    try {
      await _api.delete('/v1/me/sessions/${Uri.encodeComponent(id)}');
    } on ApiFailure catch (failure) {
      throw failure.code == 'SESSION_NOT_FOUND'
          ? failure.withMessage('That device is already signed out.')
          : failure;
    }
  }

  /// Signs out every session but this one; returns how many ended.
  Future<int> signOutOthers() async {
    final body = (await _api.postJson(
      '/v1/me/sessions/revoke-others',
      const {},
    )).body;
    return (body['revoked'] as num?)?.toInt() ?? 0;
  }

  /// Emails a confirmation link to [newEmail] (`202`). The API answers the
  /// same for an address another account uses, so it never says whether one
  /// exists.
  Future<void> changeEmail({
    required String newEmail,
    required String password,
  }) => _api.postJson('/v1/me/email', {
    'new_email': newEmail.trim(),
    'current_password': password,
  });

  /// Confirms the change from the emailed link; works signed out too.
  Future<User> confirmEmailChange(String token) async {
    try {
      final body = (await _api.postJson('/v1/auth/email-change/confirm', {
        'token': token,
      })).body;
      return User.fromJson(body['user'] as Map<String, dynamic>);
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'INVALID_TOKEN' => failure.withMessage(
          'This link has expired or was already used. Ask for a new one from '
          'Account security.',
        ),
        'EMAIL_TAKEN' => failure.withMessage(
          'Another account now uses this address, so it cannot be yours. '
          'Choose another address.',
        ),
        _ => failure,
      };
    }
  }
}
