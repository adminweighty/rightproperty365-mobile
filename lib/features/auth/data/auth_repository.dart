import '../../../core/api/api_client.dart';
import '../../../core/terminology.dart';
import 'auth_models.dart';

abstract interface class AuthRepository {
  /// Signing in, step 1: checks the email and password. The API then emails
  /// a code ([CodeRequired]); no session exists until the code is sent to
  /// [verifySignInCode].
  Future<SignInStep> login(String email, String password);

  /// Signing in, step 2: exchanges the emailed code for the session.
  Future<({User user, String token})> verifySignInCode(
    String challengeId,
    String code,
  );

  /// Emails a new code for the same challenge. The previous code stops working.
  Future<SignInChallenge> resendSignInCode(String challengeId);

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
    required String captchaId,
    required String captchaAnswer,
  });

  /// A new sign-up question. Each is single use and expires in ten minutes.
  Future<Captcha> captcha();

  /// Revokes the current session on the server.
  Future<void> logout();

  /// Deletes the signed-in account (DELETE /v1/me) after the person types
  /// their password again. The account is anonymised and every session ends.
  Future<AccountDeletion> deleteAccount(String password);

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
  Future<SignInStep> login(String email, String password) async {
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
          'That email and password do not match an account. '
          'Platform Administrators sign in on the website instead.',
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

    if (response.body['status'] == 'CODE_REQUIRED') {
      return CodeRequired(SignInChallenge.fromJson(response.body));
    }
    return SignedIn(_session(response));
  }

  static const _tooManyAttempts =
      'Too many attempts. Please wait a minute and try again.';

  @override
  Future<({User user, String token})> verifySignInCode(
    String challengeId,
    String code,
  ) async {
    try {
      return _session(
        await _api.postJson('/v1/auth/login/verify', {
          'challenge_id': challengeId,
          'code': code.trim(),
        }),
      );
    } on ApiFailure catch (failure) {
      throw failure.status == 429
          ? failure.withMessage(_tooManyAttempts)
          : failure;
    }
  }

  @override
  Future<SignInChallenge> resendSignInCode(String challengeId) async {
    final response = await _api.postJson('/v1/auth/login/resend', {
      'challenge_id': challengeId,
    });
    return SignInChallenge.fromJson(response.body);
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
    required String captchaId,
    required String captchaAnswer,
  }) async {
    await _api.postJson('/v1/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'roles': roles,
      // The answer goes as a string of digits, exactly as typed.
      'captcha': {'captcha_id': captchaId, 'answer': captchaAnswer.trim()},
      'consent': {
        'privacy_version': privacyVersion,
        'accepted': consentAccepted,
      },
    });
  }

  @override
  Future<Captcha> captcha() async =>
      Captcha.fromJson((await _api.get('/v1/auth/captcha')).body);

  @override
  Future<void> logout() async {
    await _api.postJson('/v1/auth/logout', const {});
  }

  @override
  Future<AccountDeletion> deleteAccount(String password) async {
    try {
      final response = await _api.deleteJson('/v1/me', {'password': password});
      return AccountDeletion.fromJson(response.body);
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'INVALID_PASSWORD' => ApiFailure(
          status: failure.status,
          code: failure.code,
          message: 'That password is not right.',
          fields: const {'password': 'That password is not right.'},
          traceId: failure.traceId,
        ),
        'SOLE_OWNER' => failure.withMessage(
          'You are the only owner of an organisation that still has members. '
          'Make another member an owner, or remove the members, on the website first.',
        ),
        'ADMIN_ACCOUNT_CANNOT_SELF_DELETE' => failure.withMessage(
          'An account with a platform role cannot be deleted here. Ask a Super Administrator.',
        ),
        _ when failure.status == 429 => failure.withMessage(_tooManyAttempts),
        _ => failure,
      };
    }
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
          item['requires_verification'] as bool?,
        ),
    ];
  }
}
