import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enquiries/data/enquiry.dart';

/// Simple string storage, so the activity store can be tested without a
/// device.
abstract interface class KeyValueStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStore implements KeyValueStore {
  const PreferencesStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A request sent from this phone. It records what was sent and the receipt,
/// never the customer's contact details or message.
class SentRequest {
  const SentRequest({
    required this.reference,
    required this.status,
    required this.sentAt,
    required this.title,
    required this.recipient,
    required this.route,
  });

  factory SentRequest.fromJson(Map<String, dynamic> json) => SentRequest(
    reference: json['reference'] as String,
    status: json['status'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String),
    title: json['title'] as String,
    recipient: json['recipient'] as String,
    route: json['route'] as String,
  );

  final String reference;

  /// The status on the receipt (RECEIVED). It is not refreshed afterwards.
  final String status;
  final DateTime sentAt;

  /// The listing title or the profile name.
  final String title;
  final String recipient;

  /// Where tapping the entry goes: the listing or the profile.
  final String route;

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'status': status,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'title': title,
    'recipient': recipient,
    'route': route,
  };
}

/// Saved properties and the requests sent from this phone.
///
/// This is kept on the device only. The API has no endpoint yet for a
/// customer's own activity, so nothing here follows the account to another
/// device and request statuses are not updated after sending.
class ActivityStore extends ChangeNotifier {
  ActivityStore(this._store) {
    _saved.addAll(_readList(_savedKey).cast<String>());
    _requests.addAll(
      _readList(_requestsKey)
          .map((json) => SentRequest.fromJson(json as Map<String, dynamic>)),
    );
  }

  static const _savedKey = 'activity.saved_listings';
  static const _requestsKey = 'activity.sent_requests';

  /// Oldest entries are dropped beyond this, so storage stays small.
  static const maxRequests = 200;

  final KeyValueStore _store;
  final _saved = <String>[];
  final _requests = <SentRequest>[];

  /// Slugs of saved listings, most recently saved first.
  List<String> get savedSlugs => List.unmodifiable(_saved);

  /// Requests sent from this phone, newest first.
  List<SentRequest> get requests => List.unmodifiable(_requests);

  bool isSaved(String slug) => _saved.contains(slug);

  Future<void> toggleSaved(String slug) async {
    if (!_saved.remove(slug)) _saved.insert(0, slug);
    notifyListeners();
    await _store.write(_savedKey, jsonEncode(_saved));
  }

  Future<void> recordRequest({
    required EnquiryReceipt receipt,
    required String title,
    required String recipient,
    required String route,
  }) async {
    // An idempotent replay returns the same receipt; keep one entry for it.
    _requests.removeWhere((request) => request.reference == receipt.reference);
    _requests.insert(
      0,
      SentRequest(
        reference: receipt.reference,
        status: receipt.status,
        sentAt: receipt.createdAt,
        title: title,
        recipient: recipient,
        route: route,
      ),
    );
    if (_requests.length > maxRequests) {
      _requests.removeRange(maxRequests, _requests.length);
    }
    notifyListeners();
    await _persistRequests();
  }

  Future<void> clearRequests() async {
    _requests.clear();
    notifyListeners();
    await _persistRequests();
  }

  Future<void> _persistRequests() => _store.write(
    _requestsKey,
    jsonEncode([for (final r in _requests) r.toJson()]),
  );

  List<dynamic> _readList(String key) {
    try {
      final value = jsonDecode(_store.read(key) ?? '[]');
      return value is List ? value : const [];
    } on FormatException {
      return const []; // Unreadable data is treated as empty, not as a crash.
    }
  }
}
