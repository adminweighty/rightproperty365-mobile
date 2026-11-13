import '../../../core/api/api_client.dart';
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
}
