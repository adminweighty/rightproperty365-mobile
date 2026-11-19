import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/push/push_messaging.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import 'notification_links.dart';
import 'notifications_repository.dart';

final _stamp = DateFormat('d MMM y, HH:mm');

/// The in-app notification centre: everything the API recorded for the
/// account, newest first, whether or not a push ever arrived.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _items = <AppNotification>[];
  Future<void>? _loading;
  NotificationPage? _last;
  bool _unreadOnly = false;
  bool _more = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<void> _load({bool next = false}) async {
    final services = AppScope.of(context);
    final page = next ? (_last?.page ?? 0) + 1 : 1;
    final result = await services.notifications.list(
      page: page,
      unreadOnly: _unreadOnly,
    );
    if (!mounted) return;
    setState(() {
      if (!next) _items.clear();
      _items.addAll(result.items);
      _last = result;
      _failure = null;
    });
    services.notificationCentre.setUnread(result.unreadCount);
  }

  void _reload() => setState(() {
    _loading = _load();
  });

  Future<void> _loadMore() async {
    setState(() => _more = true);
    try {
      await _load(next: true);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _more = false);
    }
  }

  Future<void> _open(AppNotification item) async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    if (item.unread) {
      try {
        final read = await services.notifications.markRead(item.id);
        services.notificationCentre.setUnread(read.unreadCount);
        final i = _items.indexWhere((n) => n.id == item.id);
        if (i >= 0 && mounted) setState(() => _items[i] = read.notification);
      } on ApiFailure {
        // Opening still works; it is marked read next time.
      }
    }
    if (item.link.isNotEmpty) {
      await openNotificationLink(router, services, item.link);
    }
  }

  Future<void> _readAll() async {
    final services = AppScope.of(context);
    try {
      services.notificationCentre.setUnread(
        await services.notifications.markAllRead(),
      );
      _reload();
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('open-notification-preferences'),
            tooltip: 'Notification settings',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push(Routes.notificationPreferences),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _loading;
        },
        child: FutureBuilder<void>(
          future: _loading,
          builder: (context, snapshot) {
            return ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                const PushCard(),
                const SizedBox(height: Space.x3),
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      key: const Key('notifications-unread-only'),
                      label: const Text('Unread only'),
                      selected: _unreadOnly,
                      onSelected: (on) {
                        _unreadOnly = on;
                        _reload();
                      },
                    ),
                    ListenableBuilder(
                      listenable: services.notificationCentre,
                      builder: (context, _) =>
                          services.notificationCentre.unreadCount == 0
                          ? const SizedBox.shrink()
                          : TextButton(
                              key: const Key('notifications-read-all'),
                              onPressed: _readAll,
                              child: const Text('Mark all as read'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                if (_failure != null) ...[
                  FailureBox(_failure!),
                  const SizedBox(height: Space.x3),
                ],
                if (snapshot.hasError)
                  MessageView(
                    icon: Icons.cloud_off_outlined,
                    title: 'We could not load your notifications',
                    body: 'Check your connection and try again.',
                    actionLabel: 'Try again',
                    onAction: _reload,
                  )
                else if (snapshot.connectionState != ConnectionState.done &&
                    _items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(Space.x6),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_items.isEmpty)
                  MessageView(
                    icon: Icons.notifications_none,
                    title: _unreadOnly
                        ? 'Nothing unread'
                        : 'No notifications yet',
                    body:
                        'New enquiries, viewings, applications and bookings '
                        'appear here.',
                  )
                else ...[
                  for (final item in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x3),
                      child: _NotificationCard(item, onTap: () => _open(item)),
                    ),
                  if (_last?.hasMore ?? false)
                    Center(
                      child: _more
                          ? const CircularProgressIndicator()
                          : TextButton(
                              key: const Key('notifications-more'),
                              onPressed: _loadMore,
                              child: const Text('Show more'),
                            ),
                    ),
                ],
                const SizedBox(height: Space.x4),
                Text(
                  'A notification shows only a reference and an area, never '
                  'anyone\'s contact details or message.',
                  style: text.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(this.item, {required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return BrandCard(
      key: Key('notification-${item.id}'),
      onTap: onTap,
      semanticLabel:
          '${item.unread ? 'Unread. ' : ''}${item.title}. ${item.body}. '
          '${_stamp.format(item.createdAt)}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Icon(
                item.unread ? Icons.circle : Icons.check_circle_outline,
                size: item.unread ? 12 : 18,
                color: item.unread ? c.primary : c.muted,
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: item.unread
                        ? text.titleMedium
                        : text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                  ),
                  if (item.body.isNotEmpty)
                    Text(item.body, style: text.bodyMedium),
                  Text(_stamp.format(item.createdAt), style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turning push on for this phone, asked only when the person chooses to.
/// Says plainly when push is not available; the centre works either way.
class PushCard extends StatelessWidget {
  const PushCard({super.key});

  @override
  Widget build(BuildContext context) {
    final centre = AppScope.of(context).notificationCentre;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return ListenableBuilder(
      listenable: centre,
      builder: (context, _) {
        final (
          String title,
          String body,
          Widget? action,
        ) = switch (centre.pushState) {
          PushState.unavailable => (
            'Push is not available on this phone',
            'Everything still appears here in the app.',
            null,
          ),
          PushState.refused => (
            'Push is off in your phone\'s settings',
            'Turn notifications on for RightProperty365 in Settings to '
                'get them on your lock screen. Everything still appears '
                'here.',
            null,
          ),
          _ when centre.pushOn => (
            'Push is on for this phone',
            'You choose which kinds in Notification settings.',
            TextButton(
              key: const Key('push-turn-off'),
              onPressed: centre.turnOffPush,
              child: const Text('Turn off on this phone'),
            ),
          ),
          _ => (
            'Get these on your lock screen',
            'Push shows a short notice such as "New property enquiry" '
                'with a reference, never names or messages. Everything '
                'also appears here.',
            FilledButton(
              key: const Key('push-turn-on'),
              onPressed: centre.turnOnPush,
              child: const Text('Turn on push'),
            ),
          ),
        };
        return Container(
          key: const Key('push-card'),
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: c.sunken,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: Space.x1),
              Text(body, style: text.bodyMedium),
              if (action != null) ...[const SizedBox(height: Space.x2), action],
            ],
          ),
        );
      },
    );
  }
}

/// Per type: email and push switches. In-app is always on; essential types
/// are locked with the API's reason.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  Future<List<NotificationPreference>>? _loading;
  List<NotificationPreference>? _items;
  String? _saving;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<List<NotificationPreference>> _get() =>
      AppScope.of(context).notifications
          .preferences()
          .then((items) => _items = items);

  Future<void> _set(NotificationPreference p, {bool? email, bool? push}) async {
    setState(() {
      _saving = p.type;
      _failure = null;
    });
    try {
      final saved = await AppScope.of(context).notifications
          .setPreference(p.type, email: email, push: push);
      if (mounted) setState(() => _items = saved);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: AsyncView<List<NotificationPreference>>(
        future: _loading!,
        onRetry: () => setState(() => _loading = _get()),
        builder: (context, _) {
          final items = _items ?? const [];
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              const PushCard(),
              const SizedBox(height: Space.x3),
              Text(
                'Every notification is kept in the app. Choose which also '
                'come by email or push. Changes apply from the next one.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.x3),
              if (_failure != null) ...[
                FailureBox(_failure!),
                const SizedBox(height: Space.x3),
              ],
              for (final p in items)
                _PreferenceTile(
                  p,
                  saving: _saving == p.type,
                  onEmail: (on) => _set(p, email: on),
                  onPush: (on) => _set(p, push: on),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile(
    this.p, {
    required this.saving,
    required this.onEmail,
    required this.onPush,
  });

  final NotificationPreference p;
  final bool saving;
  final ValueChanged<bool> onEmail;
  final ValueChanged<bool> onPush;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final locked = p.essential || saving;
    return Semantics(
      container: true,
      child: Padding(
        key: Key('preference-${p.type}'),
        padding: const EdgeInsets.only(bottom: Space.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.label, style: text.titleSmall),
            if (p.essential)
              Text(
                p.essentialReason ?? 'Always on: this cannot be turned off.',
                style: text.bodySmall,
              ),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                _Switch(
                  key: Key('preference-${p.type}-email'),
                  label: 'Email',
                  value: p.email,
                  alwaysOn: p.essential,
                  onChanged: locked ? null : onEmail,
                ),
                _Switch(
                  key: Key('preference-${p.type}-push'),
                  label: 'Push',
                  value: p.push,
                  alwaysOn: p.essential,
                  onChanged: locked ? null : onPush,
                ),
                const _Switch(label: 'In the app', value: true, alwaysOn: true),
              ],
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    super.key,
    required this.label,
    required this.value,
    this.alwaysOn = false,
    this.onChanged,
  });

  final bool alwaysOn;

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alwaysOn)
            // Locked on: a lock, not a greyed switch that reads as off.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.x2),
              child: Icon(Icons.lock_outline, size: 20),
            )
          else
            Switch(value: value, onChanged: onChanged),
          Flexible(child: Text(alwaysOn ? '$label: always on' : label)),
        ],
      ),
    ),
  );
}
