import '../../../core/api/api_client.dart';

/// Where a published listing is in its publication period (API 0.45.0,
/// `expiry` on the managed listing and on list rows).
enum ExpiryState {
  active('ACTIVE'),
  expiringSoon('EXPIRING_SOON'),
  expired('EXPIRED');

  const ExpiryState(this.wire);
  final String wire;

  static ExpiryState from(Object? wire) => values.firstWhere(
    (s) => s.wire == wire,
    orElse: () => ExpiryState.active,
  );
}

/// A listing's publication period. Null on a listing never published.
class ListingExpiry {
  const ListingExpiry({
    required this.expiresAt,
    required this.daysLeft,
    required this.state,
    required this.relistNo,
  });

  static ListingExpiry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(json['expires_at'] as String? ?? '');
    if (at == null) return null;
    return ListingExpiry(
      expiresAt: at,
      daysLeft: (json['days_left'] as num?)?.toInt() ?? 0,
      state: ExpiryState.from(json['state']),
      relistNo: (json['relist_no'] as num?)?.toInt() ?? 1,
    );
  }

  final DateTime expiresAt;

  /// Whole days left, rounded up; 0 once expired.
  final int daysLeft;
  final ExpiryState state;

  /// The publication cycle: 1 for the first publication.
  final int relistNo;
}

/// "Published" from "PUBLISHED", as the API labels statuses.
String listingStatusLabel(String status) {
  if (status.isEmpty) return '';
  final words = status.toLowerCase().replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

/// One of the caller's listings in their list (`GET /v1/me/listings`).
class MyListing {
  const MyListing({
    required this.id,
    required this.slug,
    required this.reference,
    required this.title,
    required this.status,
    this.city,
    this.expiry,
    this.canEdit = true,
  });

  factory MyListing.fromJson(Map<String, dynamic> json) => MyListing(
    id: json['id'] as String,
    slug: json['slug'] as String? ?? '',
    reference: json['reference'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled listing',
    status: json['status'] as String? ?? '',
    city: switch (json['city']) {
      final String s => s,
      {'name': final String s} => s,
      _ => null,
    },
    expiry: ListingExpiry.fromJson(json['expiry']),
    canEdit: json['can_edit'] != false,
  );

  final String id;
  final String slug;
  final String reference;
  final String title;
  final String status;
  final String? city;
  final ListingExpiry? expiry;
  final bool canEdit;

  String get statusLabel => listingStatusLabel(status);
}

/// One listing as its advertiser manages it (`GET /v1/me/listings/{id}`).
/// Editing stays on the website; the app shows the state and offers relist.
class ManagedListing {
  const ManagedListing({
    required this.id,
    required this.slug,
    required this.reference,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.public,
    required this.actions,
    this.expiry,
    this.publishedAt,
  });

  factory ManagedListing.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ?? const {};
    final status = json['status'] as String? ?? '';
    return ManagedListing(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      title: content['title'] as String? ?? 'Untitled listing',
      status: status,
      statusLabel:
          json['status_label'] as String? ?? listingStatusLabel(status),
      public: json['public'] == true,
      actions: {
        for (final a in (json['actions'] as List?) ?? const []) a as String,
      },
      expiry: ListingExpiry.fromJson(json['expiry']),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }

  final String id;
  final String slug;
  final String reference;
  final String title;
  final String status;
  final String statusLabel;

  /// The public sees the listing now.
  final bool public;

  /// What the caller may do now, for example `relist`.
  final Set<String> actions;
  final ListingExpiry? expiry;
  final DateTime? publishedAt;

  bool get canRelist => actions.contains('relist');

  /// A relist waiting for review: published before (the last cycle shows as
  /// expired) and now in review.
  bool get relistInReview =>
      status == 'PENDING_REVIEW' && expiry?.state == ExpiryState.expired;
}

/// The caller's listings (`/v1/me/listings`).
class MyListingsRepository {
  MyListingsRepository(this._api);

  final ApiClient _api;

  String _path(String id) => '/v1/me/listings/${Uri.encodeComponent(id)}';

  /// Null when the caller manages no listings (403). [expiry] filters to
  /// expiring or expired listings.
  Future<({List<MyListing> items, int total})?> list({
    ExpiryState? expiry,
  }) async {
    try {
      final query = {'page_size': '50', 'expiry': ?expiry?.wire};
      final body = (await _api.get(
        Uri(path: '/v1/me/listings', queryParameters: query).toString(),
      )).body;
      return (
        items: [
          for (final item in (body['items'] as List?) ?? const [])
            MyListing.fromJson(item as Map<String, dynamic>),
        ],
        total: (body['total'] as num?)?.toInt() ?? 0,
      );
    } on ApiFailure catch (failure) {
      if (failure.status == 403) return null;
      rethrow;
    }
  }

  Future<ManagedListing> get(String id) async {
    try {
      return ManagedListing.fromJson(
        (await _api.get(_path(id))).body['listing'] as Map<String, dynamic>,
      );
    } on ApiFailure catch (failure) {
      throw failure.status == 404
          ? failure.withMessage(
              'This listing is not in your listings. It may have been deleted '
              'or moved to another account.',
            )
          : failure;
    }
  }

  /// Sends an expired listing for review; once approved it is live again.
  Future<ManagedListing> relist(String id) async => ManagedListing.fromJson(
    (await _api.postJson('${_path(id)}/relist', const {})).body['listing']
        as Map<String, dynamic>,
  );
}
