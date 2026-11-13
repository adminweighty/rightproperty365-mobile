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

  /// Throws [ApiFailure] with a message fit to show.
  Future<void> signIn(String email, String password) async {
    final session = await _repository.login(email, password);
    await _tokens.write(session.token);
    _api.bearerToken = session.token;
    _user = session.user;
    notifyListeners();
  }

  /// Always signs out locally, even if the server cannot be told.
  Future<void> signOut() async {
    try {
      await _repository.logout();
    } on ApiFailure {
      // The session expires on its own; the local token is removed below.
    }
    _api.bearerToken = null;
    await _tokens.clear();
    _user = null;
    notifyListeners();
  }
}
