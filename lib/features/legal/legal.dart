/// Legal documents and their re-acceptance (API 0.43.0). The API lists on
/// `/v1/me` the documents whose current version asks to be accepted again;
/// nothing is blocked while they wait. The text comes from the public
/// `/v1/legal` routes. No text here is final: the lawyers' versions are
/// published by the business, and staging's seeded ones say they are drafts.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../auth/auth_controller.dart';

/// A document version waiting for the person's acceptance.
class PendingLegal {
  const PendingLegal({
    required this.kind,
    required this.title,
    required this.version,
    required this.marketCode,
    this.effectiveFrom,
    this.summaryOfChanges,
  });

  factory PendingLegal.fromJson(Map<String, dynamic> json) => PendingLegal(
    kind: json['kind'] as String,
    title: json['title'] as String? ?? json['kind'] as String,
    version: json['version'] as String,
    marketCode: json['market_code'] as String? ?? 'GLOBAL',
    effectiveFrom: DateTime.tryParse(json['effective_from'] as String? ?? ''),
    summaryOfChanges: json['summary_of_changes'] as String?,
  );

  final String kind;
  final String title;
  final String version;
  final String marketCode;
  final DateTime? effectiveFrom;
  final String? summaryOfChanges;
}

/// One version of a legal document, with its text.
class LegalDocument {
  const LegalDocument({
    required this.kind,
    required this.title,
    required this.version,
    required this.marketCode,
    required this.body,
    required this.draftNotice,
    this.effectiveFrom,
    this.summaryOfChanges,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) => LegalDocument(
    kind: json['kind'] as String,
    title: json['title'] as String? ?? json['kind'] as String,
    version: json['version'] as String,
    marketCode: json['market_code'] as String? ?? 'GLOBAL',
    body: json['body_markdown'] as String? ?? '',
    // Shown as a draft unless the API says the text was reviewed.
    draftNotice: json['draft_notice'] as bool? ?? true,
    effectiveFrom: DateTime.tryParse(json['effective_from'] as String? ?? ''),
    summaryOfChanges: json['summary_of_changes'] as String?,
  );

  final String kind;
  final String title;
  final String version;
  final String marketCode;

  /// Markdown from the API: untrusted, shown as plain styled text.
  final String body;
  final bool draftNotice;
  final DateTime? effectiveFrom;
  final String? summaryOfChanges;
}

class LegalRepository {
  LegalRepository(this._api);

  final ApiClient _api;

  /// What `/v1/me` lists as waiting (an empty list from an API before
  /// 0.43.0, which has no such field).
  Future<List<PendingLegal>> pending() async {
    final body = (await _api.get('/v1/me')).body;
    return [
      for (final p in body['pending_legal_acceptances'] as List? ?? const [])
        PendingLegal.fromJson(p as Map<String, dynamic>),
    ];
  }

  /// That version of the document, for its market (or GLOBAL's).
  Future<LegalDocument> document(PendingLegal item) async {
    final query = Uri(
      queryParameters: {'version': item.version, 'market': item.marketCode},
    ).query;
    final body = (await _api.get(
      '/v1/legal/${Uri.encodeComponent(item.kind.toLowerCase())}?$query',
    )).body;
    return LegalDocument.fromJson(body['document'] as Map<String, dynamic>);
  }

  /// Records the acceptance (accepting twice is fine).
  Future<void> accept(PendingLegal item) async {
    try {
      await _api.postJson('/v1/me/legal-acceptances', {
        'kind': item.kind,
        'version': item.version,
        'market_code': item.marketCode,
      });
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'LEGAL_DOCUMENT_NOT_FOUND' => failure.withMessage(
          'This version is no longer available. The list has been '
          'refreshed.',
        ),
        'LEGAL_VERSION_NOT_ACCEPTABLE' => failure.withMessage(
          'This version cannot be accepted now: it has been replaced or is '
          'not in effect yet. The list has been refreshed.',
        ),
        _ => failure,
      };
    }
  }
}

/// The documents waiting for the signed-in person. Emptied on sign-out.
class LegalCentre extends ChangeNotifier {
  LegalCentre({required this.repository, required this.auth}) {
    auth.addListener(_authChanged);
    _signedIn = auth.signedIn;
    if (_signedIn) unawaited(refresh());
  }

  final LegalRepository repository;
  final AuthController auth;

  late bool _signedIn;
  List<PendingLegal> _pending = const [];
  bool _later = false;

  List<PendingLegal> get pending => _pending;

  /// The banner shows: something waits and the person has not said "Later"
  /// since the app started.
  bool get showBanner => _pending.isNotEmpty && !_later;

  Future<void> refresh() async {
    if (!auth.signedIn) return _set(const []);
    try {
      _set(await repository.pending());
    } on ApiFailure {
      // Kept as it was; asked again on the next refresh.
    }
  }

  /// Hides the banner until the app is started again. Nothing is blocked
  /// either way.
  void later() {
    _later = true;
    notifyListeners();
  }

  /// Accepts, then refreshes the list. Throws [ApiFailure] (the list is
  /// refreshed then too).
  Future<void> accept(PendingLegal item) async {
    try {
      await repository.accept(item);
      _set([
        for (final p in _pending)
          if (p.kind != item.kind || p.version != item.version) p,
      ]);
    } finally {
      await refresh();
    }
  }

  void _set(List<PendingLegal> pending) {
    _pending = pending;
    notifyListeners();
  }

  void _authChanged() {
    if (auth.signedIn == _signedIn) return;
    _signedIn = auth.signedIn;
    _later = false;
    if (_signedIn) {
      unawaited(refresh());
    } else {
      _set(const []);
    }
  }

  @override
  void dispose() {
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
