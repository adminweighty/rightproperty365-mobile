import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the API could be reached at the last attempt. Any answer from
/// the API (even an error) means online; a request that could not get
/// through means offline.
class Connectivity extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;

  /// When the oldest answer shown from this phone's copy was saved, while
  /// offline.
  DateTime? _showingFrom;
  DateTime? get showingFrom => _showingFrom;

  /// Asks the API whether it answers (set by bootstrap: the API's ping).
  Future<bool> Function()? probe;

  /// "Try again": online again as soon as the API answers.
  Future<void> retry() async {
    final ping = probe;
    if (ping != null && await ping()) reachable();
  }

  void reachable() {
    if (_online && _showingFrom == null) return;
    _online = true;
    _showingFrom = null;
    notifyListeners();
  }

  void unreachable() {
    if (!_online) return;
    _online = false;
    notifyListeners();
  }

  /// An answer was shown from this phone's copy, saved at [at].
  void servedFromCopy(DateTime at) {
    if (_showingFrom != null && !at.isBefore(_showingFrom!)) return;
    _showingFrom = at;
    notifyListeners();
  }
}

/// The last answers to the requests the app may show offline: listings,
/// and the person's own account, saved properties and activity. Never other
/// people's details (contacts, inboxes, books). Emptied at sign-out.
abstract interface class ResponseCache {
  ({String body, DateTime savedAt})? read(String key);
  Future<void> write(String key, String body);
  Future<void> clear();
}

/// Empties [cache] when the person signs out: nothing tied to the account
/// stays on the phone.
void forgetAtSignOut(
  Listenable auth,
  bool Function() signedIn,
  ResponseCache cache,
) {
  var was = signedIn();
  auth.addListener(() {
    final now = signedIn();
    if (was && !now) cache.clear();
    was = now;
  });
}

/// GET paths whose answers are kept for offline use.
const offlinePaths = [
  '/v1/listings',
  '/v1/me',
  '/v1/me/saved-listings',
  '/v1/me/property-requests',
  '/v1/me/appointments',
  '/v1/me/applications',
  '/v1/me/venue-bookings',
  '/v1/me/tenancies',
  '/v1/me/notifications',
];

bool keptOffline(String path) {
  final p = path.split('?').first;
  for (final allowed in offlinePaths) {
    if (allowed == '/v1/me'
        ? p == allowed
        : p == allowed || p.startsWith('$allowed/')) {
      return true;
    }
  }
  return false;
}

class MemoryResponseCache implements ResponseCache {
  final entries = <String, ({String body, DateTime savedAt})>{};

  @override
  ({String body, DateTime savedAt})? read(String key) => entries[key];

  @override
  Future<void> write(String key, String body) async =>
      entries[key] = (body: body, savedAt: DateTime.now());

  @override
  Future<void> clear() async => entries.clear();
}

/// Kept in shared preferences, the most recent [limit] answers.
class PreferencesResponseCache implements ResponseCache {
  PreferencesResponseCache(this._preferences, {this.limit = 80});

  final SharedPreferences _preferences;
  final int limit;

  static const _prefix = 'offline.';
  static const _index = 'offline.index';

  List<String> get _keys => _preferences.getStringList(_index) ?? const [];

  @override
  ({String body, DateTime savedAt})? read(String key) {
    final raw = _preferences.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        body: json['body'] as String,
        savedAt: DateTime.parse(json['saved_at'] as String),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, String body) async {
    await _preferences.setString(
      '$_prefix$key',
      jsonEncode({'body': body, 'saved_at': DateTime.now().toIso8601String()}),
    );
    final keys = [..._keys.where((k) => k != key), key];
    while (keys.length > limit) {
      await _preferences.remove('$_prefix${keys.removeAt(0)}');
    }
    await _preferences.setStringList(_index, keys);
  }

  @override
  Future<void> clear() async {
    for (final key in _keys) {
      await _preferences.remove('$_prefix$key');
    }
    await _preferences.remove(_index);
  }
}
