import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/push/push_messaging.dart';
import '../activity/activity_store.dart' show KeyValueStore;
import '../auth/auth_controller.dart';
import 'notifications_repository.dart';

/// The unread count, and push on this phone for the signed-in account.
///
/// The in-app centre is the durable record: everything works from it when
/// no push ever arrives (the server has no FCM key yet, Firebase did not
/// start, or the person said no). Push is only turned on when the person
/// asks for it, never at first launch, and the token is removed from the
/// account on sign-out (with the logout call) and on account deletion
/// (by the API).
class NotificationCentre extends ChangeNotifier {
  NotificationCentre({
    required this.repository,
    required this.auth,
    required this.push,
    required this.store,
    required this.platform,
    required this.appVersion,
    this.locale,
  }) {
    auth.addListener(_authChanged);
    _signedIn = auth.signedIn;
  }

  final NotificationsRepository repository;
  final AuthController auth;
  final PushMessaging push;

  /// Remembers only that the person turned push on, on this phone. Cleared
  /// on sign-out.
  final KeyValueStore store;

  /// `ANDROID` or `IOS`.
  final String platform;
  final String appVersion;
  final String Function()? locale;

  static const _optInKey = 'push.opted_in';

  late bool _signedIn;
  StreamSubscription<String>? _tokenChanges;

  int _unread = 0;
  int get unreadCount => _unread;

  PushState _pushState = PushState.unavailable;
  PushState get pushState => _pushState;

  /// The person turned push on in the app (and has not turned it off).
  bool get optedIn => store.read(_optInKey) == '1';

  /// Push reaches this phone as far as the app can tell. Nothing says a
  /// push was delivered or seen.
  bool get pushOn => optedIn && _pushState == PushState.allowed;

  /// At launch, after the session is restored.
  Future<void> start() async {
    await _tokenChanges?.cancel();
    _tokenChanges = push.tokenChanges.listen((_) => _register());
    await refreshPushState();
    if (auth.signedIn) {
      unawaited(refresh());
      unawaited(_register());
    }
  }

  Future<void> refreshPushState() async {
    final state = await push.state();
    if (state != _pushState) {
      _pushState = state;
      notifyListeners();
    }
  }

  /// Fetches the unread count; quietly keeps the last one offline.
  Future<void> refresh() async {
    if (!auth.signedIn) return setUnread(0);
    try {
      setUnread(await repository.unreadCount());
    } on ApiFailure {
      // Shown again on the next refresh.
    }
  }

  void setUnread(int count) {
    if (count == _unread) return;
    _unread = count;
    notifyListeners();
  }

  /// The person asked for push: the phone's prompt, then registration.
  Future<PushState> turnOnPush() async {
    _pushState = await push.requestPermission();
    if (_pushState == PushState.allowed) {
      await store.write(_optInKey, '1');
      await _register();
    }
    notifyListeners();
    return _pushState;
  }

  /// Stops push to this phone; the in-app centre carries on.
  Future<void> turnOffPush() async {
    await store.write(_optInKey, '');
    notifyListeners();
    final token = await push.token();
    if (token != null && auth.signedIn) {
      await repository.removeDevice(token);
    }
  }

  /// For the logout call, so the API drops this phone with the session.
  Future<String?> tokenForSignOut() async => optedIn ? push.token() : null;

  Future<void> _register() async {
    if (!auth.signedIn || !optedIn) return;
    final token = await push.token();
    if (token == null) return;
    try {
      await repository.registerDevice(
        token: token,
        platform: platform,
        appVersion: appVersion,
        locale: locale?.call(),
      );
    } on ApiFailure catch (failure) {
      debugPrint('Push token not registered (${failure.code})');
    }
  }

  void _authChanged() {
    if (auth.signedIn == _signedIn) return;
    _signedIn = auth.signedIn;
    if (_signedIn) {
      unawaited(refresh());
      unawaited(_register());
    } else {
      // FR-045: nothing tied to the account stays on the phone.
      unawaited(store.write(_optInKey, ''));
      unawaited(push.deleteToken());
      setUnread(0);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    auth.removeListener(_authChanged);
    _tokenChanges?.cancel();
    super.dispose();
  }
}
