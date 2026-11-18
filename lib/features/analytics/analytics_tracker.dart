import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../activity/activity_store.dart' show KeyValueStore;

/// The listing events the app may send (API 0.30.0). Saves, enquiries,
/// viewing requests and confirmations are recorded by the API itself and
/// must never be sent from here.
enum AnalyticsEventType {
  impression('property_card_impression'),
  detailView('listing_detail_view'),
  contactClick('contact_click'),
  videoPlayIntent('youtube_play_intent');

  const AnalyticsEventType(this.wire);
  final String wire;
}

/// Where an impression was seen.
enum AnalyticsPlacement { search, rail, similar, home, saved }

/// A random UUID (version 4) from a secure source, for `event_id`.
String newEventId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      [for (final v in b.sublist(from, to)) v.toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// First-party listing statistics (`POST /v1/analytics/events`).
///
/// - Events are batched (at most 50 a request), sent every 15 seconds, when
///   20 are waiting, and when the app goes to the background.
/// - Each has a client-chosen `event_id`, so a retry is never counted twice.
/// - The session is an opaque random pseudonym kept in memory only. It
///   rotates at local midnight, after 24 hours and when the app restarts;
///   nothing identifies the person or the phone.
/// - A listing's detail view is sent once per listing page; impressions once
///   per card per screen.
/// - Phones send no Do Not Track or GPC signal, so the app offers its own
///   switch (Account, "Count my visits anonymously"). Off means nothing is
///   sent at all, as the website does for Do Not Track.
class AnalyticsTracker {
  AnalyticsTracker(
    this._api, {
    required this._store,
    DateTime Function()? clock,
    Random? random,
    this.device = 'mobile',
    Duration interval = const Duration(seconds: 15),
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure() {
    if (interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) => flush());
    }
  }

  static const _optOutKey = 'analytics.opted_out';
  static const maxBatch = 50;
  static const sendAt = 20;
  static const maxQueued = 200;

  final ApiClient _api;
  final KeyValueStore _store;
  final DateTime Function() _clock;
  final Random _random;
  Timer? _timer;

  /// `mobile` or `tablet`, set from the screen size at start-up.
  String device;

  final List<Map<String, dynamic>> _queue = [];
  bool _sending = false;
  DateTime? _pausedUntil;

  String? _session;
  DateTime? _sessionStarted;

  /// Whether the person turned counting off on this phone.
  bool get optedOut => _store.read(_optOutKey) == 'true';

  Future<void> setOptedOut(bool value) async {
    await _store.write(_optOutKey, '$value');
    if (value) _queue.clear();
  }

  @visibleForTesting
  List<Map<String, dynamic>> get queued => List.unmodifiable(_queue);

  String _currentSession() {
    final now = _clock();
    final started = _sessionStarted;
    final rotate =
        started == null ||
        now.difference(started) >= const Duration(hours: 24) ||
        now.year != started.year ||
        now.month != started.month ||
        now.day != started.day;
    if (rotate) {
      final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
      _session = base64Url.encode(bytes).replaceAll('=', '');
      _sessionStarted = now;
    }
    return _session!;
  }

  /// Records an event for [listingId]. Nothing happens when counting is off.
  void record(
    AnalyticsEventType type,
    String listingId, {
    AnalyticsPlacement? placement,
    int? rank,
    String source = 'internal',
  }) {
    if (optedOut) return;
    _queue.add({
      'event_id': newEventId(_random),
      'type': type.wire,
      'occurred_at': _clock().toUtc().toIso8601String(),
      'listing_id': listingId,
      if (type == AnalyticsEventType.impression && placement != null)
        'placement': placement.name,
      if (type == AnalyticsEventType.impression && rank != null) 'rank': rank,
      'source': source,
      'device': device,
      'session': _currentSession(),
      'consent': {'analytics': true},
    });
    if (_queue.length > maxQueued) {
      _queue.removeRange(0, _queue.length - maxQueued);
    }
    if (_queue.length >= sendAt) flush();
  }

  /// Sends what is waiting. Events stay queued on a network failure or a
  /// rate limit, and are dropped once the API would refuse them for age
  /// (24 hours) or when it refuses the batch itself.
  Future<void> flush() async {
    if (_sending || _queue.isEmpty || optedOut) return;
    final paused = _pausedUntil;
    if (paused != null && _clock().isBefore(paused)) return;
    _sending = true;
    try {
      final oldest = _clock().toUtc().subtract(const Duration(hours: 23));
      _queue.removeWhere(
        (e) => DateTime.parse(e['occurred_at'] as String).isBefore(oldest),
      );
      while (_queue.isNotEmpty) {
        final batch = _queue.take(maxBatch).toList();
        try {
          await _api.postJson('/v1/analytics/events', {
            'schema': 1,
            'events': batch,
          });
        } on ApiFailure catch (failure) {
          if (failure.isNetwork) return;
          if (failure.status == 429) {
            _pausedUntil = _clock().add(
              failure.retryAfter ?? const Duration(minutes: 1),
            );
            return;
          }
          // Anything else is refused for good: do not send it again.
        }
        _queue.removeRange(0, batch.length);
      }
    } finally {
      _sending = false;
    }
  }

  void dispose() => _timer?.cancel();
}
