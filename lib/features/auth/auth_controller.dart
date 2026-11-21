import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import 'data/auth_models.dart';
import 'data/auth_repository.dart';
import 'data/token_store.dart';

/// Holds the signed-in user and keeps the API client's bearer token in step
/// with secure storage. Screens listen to it.
class AuthController extends ChangeNotifier {
  AuthController({
    required this._repository,
    required this._tokens,
    required this._api,
  });

  final AuthRepository _repository;
  final TokenStore _tokens;
  final ApiClient _api;

  User? _user;
  User? get user => _user;
  bool get signedIn => _user != null;

  AuthRepository get repository => _repository;

  /// This phone's push token, sent with the logout so the API stops push to
  /// it along with the session (FR-045).
  Future<String?> Function()? deviceTokenForSignOut;

  /// Restores a saved session at launch. A token the API no longer accepts is
  /// forgotten; if the API cannot be reached the token is kept for next time.
  Future<void> restore() async {
    final String? token;
    try {
      token = await _tokens.read();
    } on Exception {
      return; // Secure storage unavailable: start signed out.
    }
    if (token == null) return;

    _api.bearerToken = token;
    try {
      _user = await _repository.me();
      notifyListeners();
    } on ApiFailure catch (failure) {
      _api.bearerToken = null;
      if (failure.status == 401) await _tokens.clear();
    }
  }

  /// Signing in, step 1. Returns the challenge when the API has emailed a
  /// code, which the person then enters for [verifyCode]; returns null when
  /// the person is already signed in. Throws [ApiFailure] with a message fit
  /// to show.
  Future<SignInChallenge?> signIn(String email, String password) async {
    switch (await _repository.login(email, password)) {
      case CodeRequired(:final challenge):
        return challenge;
      case SignedIn(:final session):
        await _store(session);
        return null;
    }
  }

  /// Signing in, step 2: the emailed code. Throws [ApiFailure].
  Future<void> verifyCode(String challengeId, String code) =>
      _start(_repository.verifySignInCode(challengeId, code));

  /// Emails a new sign-in code. Throws [ApiFailure]; a 429 carries
  /// [ApiFailure.retryAfter].
  Future<SignInChallenge> resendCode(String challengeId) =>
      _repository.resendSignInCode(challengeId);

  /// Confirms an email address with the token from the email, which also
  /// signs the person in. Throws [ApiFailure].
  Future<void> confirmEmail(String token) =>
      _start(_repository.verifyEmail(token));

  Future<void> _start(Future<({User user, String token})> opening) async =>
      _store(await opening);

  Future<void> _store(({User user, String token}) session) async {
    await _tokens.write(session.token);
    _api.bearerToken = session.token;
    _user = session.user;
    notifyListeners();
  }

  /// Sets a new password. The API revokes every session of the account, so
  /// this device is signed out too and the person signs in again.
  Future<void> resetPassword(String token, String password) async {
    await _repository.confirmPasswordReset(token, password);
    await _forget();
  }

  /// Deletes the account. On success the API has already ended every
  /// session, so the token is only forgotten here. Throws [ApiFailure].
  Future<AccountDeletion> deleteAccount(String password) async {
    final result = await _repository.deleteAccount(password);
    await _forget();
    return result;
  }

  /// Always signs out locally, even if the server cannot be told.
  Future<void> signOut() async {
    try {
      String? deviceToken;
      try {
        deviceToken = await deviceTokenForSignOut?.call();
      } on Object {
        deviceToken = null;
      }
      await _repository.logout(deviceToken: deviceToken);
    } on ApiFailure {
      // The session expires on its own; the local token is removed below.
    }
    await _forget();
  }

  /// The account changed elsewhere (a confirmed email change): the signed-in
  /// person sees it at once. Ignored for another account or when signed out.
  void userChanged(User user) {
    if (_user?.id != user.id) return;
    _user = user;
    notifyListeners();
  }

  Future<void> _forget() async {
    _api.bearerToken = null;
    await _tokens.clear();
    _user = null;
    notifyListeners();
  }
}
