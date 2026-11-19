import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// What the device can do about push right now.
enum PushState {
  /// Firebase did not start on this phone (or in tests). The notification
  /// centre in the app still works.
  unavailable,

  /// Available, but the person has not been asked yet.
  notAsked,

  /// The person allowed notifications.
  allowed,

  /// The person refused (or turned them off in the phone's settings).
  refused,
}

/// A push as the app sees it: the server's safe text and where it leads.
/// The text is shown as sent; the app never adds names or message text.
class PushMessage {
  const PushMessage({
    this.title,
    this.body,
    this.type,
    this.link,
    this.notificationId,
  });

  factory PushMessage.fromRemote(RemoteMessage message) {
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    return PushMessage(
      title: message.notification?.title,
      body: message.notification?.body,
      type: text(message.data['type']),
      link: text(message.data['link']),
      notificationId: text(message.data['notification_id']),
    );
  }

  final String? title;
  final String? body;

  /// For example `NEW_LEAD`, or `SUMMARY` for a collapsed burst.
  final String? type;

  /// A relative website path such as `/agent/requests/{id}`.
  final String? link;

  /// Empty for a summary push.
  final String? notificationId;
}

/// Push messaging on the device. Nothing here calls the API or asks for
/// permission by itself: the notification centre does, when the person
/// turns push on.
abstract interface class PushMessaging {
  Future<PushState> state();

  /// Asks the phone's permission (the Android 13+ / iOS prompt). Call only
  /// from a screen that has just explained why.
  Future<PushState> requestPermission();

  /// The device's FCM registration token, or null when push is unavailable
  /// or refused.
  Future<String?> token();

  /// New tokens as Firebase rotates them.
  Stream<String> get tokenChanges;

  /// Forgets the token on this device (sign-out and account deletion).
  Future<void> deleteToken();

  /// Pushes that arrive while the app is on screen. The phone shows none of
  /// these by itself, so the app does.
  Stream<PushMessage> get received;

  /// Pushes tapped while the app was in the background.
  Stream<PushMessage> get opened;

  /// The push whose tap launched the app from closed, once.
  Future<PushMessage?> launchMessage();
}

/// Push is off: Firebase did not start, or in tests.
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

  @override
  Stream<PushMessage> get received => const Stream.empty();

  @override
  Stream<PushMessage> get opened => const Stream.empty();

  @override
  Future<PushMessage?> launchMessage() async => null;
}

/// Firebase Cloud Messaging (Android, and iOS through APNs), configured by
/// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Starts Firebase; if it cannot start, push is off and the rest of the
  /// app is unchanged.
  static Future<PushMessaging> start() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      // iOS: the app shows its own banner in the foreground; the badge is
      // the server's unread count.
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(badge: true);
      } on Object {
        // Not iOS, or not ready: nothing to set.
      }
      return FirebasePushMessaging._();
    } on Object catch (error) {
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
  Future<PushState> state() async {
    try {
      return _from(
        (await _messaging.getNotificationSettings()).authorizationStatus,
      );
    } on Object {
      return PushState.unavailable;
    }
  }

  @override
  Future<PushState> requestPermission() async {
    try {
      return _from((await _messaging.requestPermission()).authorizationStatus);
    } on Object {
      return PushState.unavailable;
    }
  }

  // The API sends with FCM HTTP v1 `message.token`, the registration token.
  // firebase_messaging 17 deprecates getToken in favour of installation IDs;
  // switch when the API sends to those.
  @override
  Future<String?> token() async {
    if (await state() != PushState.allowed) return null;
    try {
      // ignore: deprecated_member_use
      return await _messaging.getToken().timeout(const Duration(seconds: 20));
    } on Object {
      return null; // For example no APNs key in the Firebase project yet.
    }
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() async {
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } on Object {
      // Nothing to remove.
    }
  }

  @override
  Stream<PushMessage> get received =>
      FirebaseMessaging.onMessage.map(PushMessage.fromRemote);

  @override
  Stream<PushMessage> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(PushMessage.fromRemote);

  @override
  Future<PushMessage?> launchMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      return message == null ? null : PushMessage.fromRemote(message);
    } on Object {
      return null;
    }
  }
}
