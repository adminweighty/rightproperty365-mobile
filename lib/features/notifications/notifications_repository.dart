import '../../core/api/api_client.dart';

/// One item in the in-app notification centre (API 0.35.0). Title and body
/// are the server's safe text: never a customer's name, phone, email or
/// message.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.createdAt,
    this.reference,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        link: json['link'] as String? ?? '',
        reference: json['reference'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: switch (json['read_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
      );

  final String id;
  final String type;
  final String title;
  final String body;

  /// A relative website path, for example `/agent/requests/{id}`.
  final String link;
  final String? reference;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: [
          for (final item in json['items'] as List? ?? const [])
            AppNotification.fromJson(item as Map<String, dynamic>),
        ],
        unreadCount: json['unread_count'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        pageSize: json['page_size'] as int? ?? 20,
        total: json['total'] as int? ?? 0,
      );

  final List<AppNotification> items;
  final int unreadCount;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}

/// One notification type's channels. In-app is always on; essential types
/// cannot be switched off at all.
class NotificationPreference {
  const NotificationPreference({
    required this.type,
    required this.label,
    required this.essential,
    required this.email,
    required this.push,
    this.essentialReason,
    this.changedAt,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) =>
      NotificationPreference(
        type: json['type'] as String,
        label: json['label'] as String? ?? json['type'] as String,
        essential: json['essential'] as bool? ?? false,
        essentialReason: json['essential_reason'] as String?,
        email: json['email'] as bool? ?? true,
        push: json['push'] as bool? ?? true,
        changedAt: switch (json['changed_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
      );

  final String type;
  final String label;
  final bool essential;
  final String? essentialReason;
  final bool email;
  final bool push;
  final DateTime? changedAt;
}

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  /// Recorded by the API as the source of a preference change.
  static const _client = {'X-Client': 'app'};

  Future<NotificationPage> list({int page = 1, bool unreadOnly = false}) async {
    final query = Uri(
      queryParameters: {'page': '$page', if (unreadOnly) 'unread': 'true'},
    ).query;
    return NotificationPage.fromJson(
      (await _api.get('/v1/me/notifications?$query')).body,
    );
  }

  Future<int> unreadCount() async =>
      (await _api.get('/v1/me/notifications/unread-count')).body['unread_count']
          as int? ??
      0;

  /// Marks one item read; returns it and the new unread count.
  Future<({AppNotification notification, int unreadCount})> markRead(
    String id,
  ) async {
    final body = (await _api.post(
      '/v1/me/notifications/${Uri.encodeComponent(id)}/read',
    )).body;
    return (
      notification: AppNotification.fromJson(
        body['notification'] as Map<String, dynamic>,
      ),
      unreadCount: body['unread_count'] as int? ?? 0,
    );
  }

  /// Returns the new unread count (0).
  Future<int> markAllRead() async =>
      (await _api.post('/v1/me/notifications/read-all')).body['unread_count']
          as int? ??
      0;

  Future<List<NotificationPreference>> preferences() async =>
      _preferences((await _api.get('/v1/me/notification-preferences')).body);

  /// Changes one type's email or push. Returns every type as saved.
  Future<List<NotificationPreference>> setPreference(
    String type, {
    bool? email,
    bool? push,
  }) async => _preferences(
    (await _api.putJson('/v1/me/notification-preferences', {
      'items': [
        {'type': type, 'email': ?email, 'push': ?push},
      ],
    }, headers: _client)).body,
  );

  static List<NotificationPreference> _preferences(Map<String, dynamic> body) =>
      [
        for (final item in body['items'] as List? ?? const [])
          NotificationPreference.fromJson(item as Map<String, dynamic>),
      ];

  /// Registers (or refreshes) this phone's push token for the signed-in
  /// account. Returns the device ID.
  Future<String> registerDevice({
    required String token,
    required String platform,
    required String appVersion,
    String? locale,
  }) async =>
      (await _api.postJson('/v1/me/devices', {
            'token': token,
            'platform': platform,
            'app_version': appVersion,
            if (locale != null && locale.isNotEmpty && locale.length <= 35)
              'locale': locale,
            'push_consent': true,
          })).body['device_id']
          as String? ??
      '';

  /// Stops push to this phone for the account. A token the API does not
  /// have is already gone.
  Future<void> removeDevice(String token) async {
    try {
      await _api.delete(
        '/v1/me/devices?${Uri(queryParameters: {'token': token}).query}',
      );
    } on ApiFailure catch (failure) {
      if (failure.code != 'DEVICE_NOT_FOUND') rethrow;
    }
  }
}
