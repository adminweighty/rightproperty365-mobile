import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The Firebase project the app receives push messages through, from
/// `--dart-define` (see README, "Push notifications"). No
/// `google-services.json` or `GoogleService-Info.plist` is needed: without
/// these values push is simply off and the rest of the app is unchanged.
abstract final class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// iOS only: the iOS app's ID in the same project.
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions options(TargetPlatform platform) => FirebaseOptions(
    apiKey: apiKey,
    appId: platform == TargetPlatform.iOS && iosAppId.isNotEmpty
        ? iosAppId
        : appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}

/// What the device can do about push right now.
enum PushState {
  /// No Firebase project configured in this build.
  unavailable,

  /// Configured, but the person has not been asked yet.
  notAsked,

  /// The person allowed notifications.
  allowed,

  /// The person refused (or turned them off in the phone's settings).
  refused,
}

/// Push messaging on the device. The device token is handed to the API by
/// the notifications feature once its endpoint exists; nothing here calls
/// the API or asks for permission by itself.
abstract interface class PushMessaging {
  Future<PushState> state();

  /// Asks the phone's permission (the Android 13+ / iOS prompt). Call only
  /// from a screen that has just explained why.
  Future<PushState> requestPermission();

  /// The device's push identifier, or null when push is unavailable or refused.
  Future<String?> token();

  /// New identifiers as Firebase rotates them.
  Stream<String> get tokenChanges;

  /// Forgets the token on this device (sign-out and account deletion).
  Future<void> deleteToken();
}

/// Push is off: no Firebase project in this build, or in tests.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  Future<PushState> state() async => PushState.unavailable;

  @override
  Future<PushState> requestPermission() async => PushState.unavailable;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenChanges => const Stream.empty();

  @override
  Future<void> deleteToken() async {}
}

/// Firebase Cloud Messaging (Android, and iOS through APNs).
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Starts Firebase when this build is configured for it; otherwise, or if
  /// Firebase cannot start, push is off.
  static Future<PushMessaging> start() async {
    if (!PushConfig.configured) return const NoPushMessaging();
    try {
      await Firebase.initializeApp(
        options: PushConfig.options(defaultTargetPlatform),
      );
      return FirebasePushMessaging._();
    } on Exception catch (error) {
      debugPrint('Push is off: Firebase did not start ($error)');
      return const NoPushMessaging();
    }
  }

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static PushState _from(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushState.allowed,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => PushState.refused,
    AuthorizationStatus.notDetermined => PushState.notAsked,
  };

  @override
  Future<PushState> state() async =>
      _from((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushState> requestPermission() async =>
      _from((await _messaging.requestPermission()).authorizationStatus);

  @override
  Future<String?> token() async {
    if (await state() != PushState.allowed) return null;
    try {
      // firebase_messaging 17: registering answers with the installation ID
      // used as the send target. Which identifier the API stores is set by
      // its device-registration contract.
      final registered = _messaging.onRegistered.first;
      await _messaging.register();
      return await registered.timeout(const Duration(seconds: 20));
    } on Exception {
      return null; // For example no APNs key in the Firebase project yet.
    }
  }

  @override
  Stream<String> get tokenChanges => _messaging.onRegistered;

  @override
  Future<void> deleteToken() async {
    try {
      await _messaging.unregister();
    } on Exception {
      // Nothing to remove.
    }
  }
}
