import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../core/push/push_messaging.dart';
import 'notification_links.dart';

/// The bell with the unread count; opens the notification centre.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final centre = AppScope.of(context).notificationCentre;
    return ListenableBuilder(
      listenable: centre,
      builder: (context, _) {
        final unread = centre.unreadCount;
        return IconButton(
          key: const Key('notification-bell'),
          tooltip: unread == 0
              ? 'Notifications'
              : 'Notifications, $unread unread',
          icon: unread == 0
              ? const Icon(Icons.notifications_outlined)
              : Badge.count(
                  count: unread,
                  child: const Icon(Icons.notifications_outlined),
                ),
          onPressed: () => context.push(Routes.notifications),
        );
      },
    );
  }
}

/// Handles pushes for the whole app: a tap (from the background or from
/// closed) opens the same screen as the in-app item; a push that arrives on
/// screen shows a short banner and updates the count. Everything also
/// works with no push at all.
class PushHandler {
  PushHandler({
    required this.services,
    required this.router,
    required this.messenger,
  });

  final AppServices services;
  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final _subscriptions = <StreamSubscription<PushMessage>>[];

  Future<void> start() async {
    _subscriptions
      ..add(services.push.opened.listen(open))
      ..add(services.push.received.listen(_show));
    final launch = await services.push.launchMessage();
    if (launch != null) await open(launch);
  }

  Future<void> open(PushMessage message) async {
    final centre = services.notificationCentre;
    if (!services.auth.signedIn) {
      router.push(Routes.signIn);
      return;
    }
    final id = message.notificationId;
    if (id != null) {
      unawaited(
        services.notifications
            .markRead(id)
            .then((r) => centre.setUnread(r.unreadCount))
            .catchError((Object _) {}),
      );
    }
    final link = message.link;
    if (link == null || message.type == 'SUMMARY') {
      router.push(Routes.notifications);
    } else {
      await openNotificationLink(router, services, link);
    }
  }

  void _show(PushMessage message) {
    unawaited(services.notificationCentre.refresh());
    final title = message.title;
    if (title == null) return;
    messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text([title, ?message.body].join('\n')),
        action: SnackBarAction(label: 'Open', onPressed: () => open(message)),
      ),
    );
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
  }
}
