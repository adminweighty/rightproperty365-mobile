import '../../../core/api/api_client.dart';
import '../../../core/terminology.dart';
import 'auth_models.dart';

abstract interface class AuthRepository {
  /// Signs in and returns the user with a bearer session token.
  Future<({User user, String token})> login(String email, String password);

  /// The user for the token currently set on the API client.
  Future<User> me();

  /// Creates an account. The API always answers "verification sent"; the
  /// person confirms by the link in the email before they can sign in.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required List<String> roles,
    required bool consentAccepted,
    required String privacyVersion,
  });

  /// Revokes the current session on the server.
  Future<void> logout();

  /// The roles a person may choose at sign-up today, with the API's label
  /// and group heading for each (GET /v1/reference/account_roles), in
  /// display order.
  Future<List<SelectableRole>> selectableRoles();

  /// Confirms an email address with the single-use token from the email and
  /// starts a session.
  Future<({User user, String token})> verifyEmail(String token);

  /// Sends the confirmation email again. The API answers the same way
  /// whether or not the address has an unconfirmed account.
  Future<void> resendVerification(String email);

  /// Asks for a password-reset email. The API answers the same way whether
  /// or not an account exists.
  Future<void> requestPasswordReset(String email);

  /// Sets a new password with the single-use token from the reset email.
  /// Every session of that account is revoked.
  Future<void> confirmPasswordReset(String token, String password);
}

/// The token from what someone pasted: the whole link from the email
/// (`.../verify-email?token=abc`) or the token on its own.
String? extractEmailToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final fromLink = Uri.tryParse(text)?.queryParameters['token'];
  if (fromLink != null) return fromLink.isEmpty ? null : fromLink;
  // A bare token has no spaces and no URL punctuation.
  return RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(text) ? text : null;
}

/// Identity endpoints of the Go API (api/openapi.yaml in the backend).
///
/// Mobile sessions use `token_delivery: "bearer"`: the token comes back in the
/// body and is sent as `Authorization: Bearer`. No cookie is involved.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<({User user, String token})> login(
    String email,
    String password,
  ) async {
    final ApiResponse response;
    try {
      response = await _api.postJson('/v1/auth/login', {
        'email': email.trim(),
        'password': password,
        'token_delivery': 'bearer',
      });
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'INVALID_CREDENTIALS' => failure.withMessage(
          'That email and password do not match an account.',
        ),
        'EMAIL_NOT_VERIFIED' => failure.withMessage(
          'Confirm your email address first. Use the link we sent when you registered.',
        ),
        _ when failure.status == 429 => failure.withMessage(
          'Too many attempts. Please wait a minute and try again.',
        ),
        _ => failure,
      };
    }

    return _session(response);
  }

  ({User user, String token}) _session(ApiResponse response) {
    final token = response.body['access_token'];
    final user = response.body['user'];
    if (token is! String || user is! Map<String, dynamic>) {
      // The API answered 200 without a session (for example an administrator
      // account, which cannot sign in to the app).
      throw const ApiFailure(
        status: 200,
        code: 'NO_SESSION',
        message: 'This account cannot sign in to the app.',
      );
    }
    return (user: User.fromJson(user), token: token);
  }

  static const _invalidLink =
      'That link is not valid any more. It may have expired or already been used. Ask for a new one.';

  ApiFailure _linkFailure(ApiFailure failure) => switch (failure.code) {
    'INVALID_TOKEN' => failure.withMessage(_invalidLink),
    _ when failure.status == 429 => failure.withMessage(
      'Too many attempts. Please wait a minute and try again.',
    ),
    _ => failure,
  };

  @override
  Future<({User user, String token})> verifyEmail(String token) async {
    try {
      return _session(
        await _api.postJson('/v1/auth/verify-email', {
          'token': token,
          'token_delivery': 'bearer',
        }),
      );
    } on ApiFailure catch (failure) {
      throw _linkFailure(failure);
    }
  }

  @override
  Future<void> resendVerification(String email) async {
    await _api.postJson('/v1/auth/resend-verification', {
      'email': email.trim(),
    });
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await _api.postJson('/v1/auth/password-reset/request', {
      'email': email.trim(),
    });
  }

  @override
  Future<void> confirmPasswordReset(String token, String password) async {
    try {
      await _api.postJson('/v1/auth/password-reset/confirm', {
        'token': token,
        'password': password,
      });
    } on ApiFailure catch (failure) {
      throw _linkFailure(failure);
    }
  }

  @override
  Future<User> me() async {
    final response = await _api.get('/v1/me');
    return User.fromJson(response.body['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required List<String> roles,
    required bool consentAccepted,
    required String privacyVersion,
  }) async {
    await _api.postJson('/v1/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'roles': roles,
      'consent': {
        'privacy_version': privacyVersion,
        'accepted': consentAccepted,
      },
    });
  }

  @override
  Future<void> logout() async {
    await _api.postJson('/v1/auth/logout', const {});
  }

  @override
  Future<List<SelectableRole>> selectableRoles() async {
    final response = await _api.get('/v1/reference/account_roles');
    return [
      for (final item in (response.body['items'] as List?) ?? const [])
        SelectableRole(
          item['code'] as String,
          item['label'] as String,
          (item['group'] as Map?)?['label'] as String?,
        ),
    ];
  }
}
