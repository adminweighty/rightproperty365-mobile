import '../../../core/api/api_client.dart';

/// Reviews of service providers (API 0.36.4). Only `service-providers`
/// profiles are reviewed. A book (organisation, or a direct owner) reviews
/// a finished maintenance job; a person reviews an enquiry that is at least
/// 14 days old and marked replied. New reviews wait for moderation.

class Rating {
  const Rating({this.average, this.count = 0});

  factory Rating.fromJson(Map<String, dynamic>? json) => Rating(
    average: json?['average'] as String?,
    count: json?['count'] as int? ?? 0,
  );

  /// One decimal, for example "4.5"; null with no published reviews.
  final String? average;
  final int count;
}

class ReviewReply {
  const ReviewReply(this.text, this.repliedAt);

  factory ReviewReply.fromJson(Map<String, dynamic> json) => ReviewReply(
    json['text'] as String? ?? '',
    DateTime.parse(json['replied_at'] as String).toLocal(),
  );

  final String text;
  final DateTime repliedAt;
}

/// A review as the public, the reviewer or the provider sees it.
class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.text,
    required this.reviewerName,
    this.reviewerKind = 'CUSTOMER',
    this.profileName,
    this.profileSlug,
    this.basisKind,
    this.basisReference,
    this.status,
    this.statusLabel,
    this.moderationReason,
    this.publishedAt,
    this.createdAt,
    this.reply,
    this.replyRemoved = false,
    this.canReply = false,
    this.canEdit = false,
    this.canDelete = false,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    final reviewer = json['reviewer'] as Map<String, dynamic>? ?? const {};
    final profile = json['profile'] as Map<String, dynamic>?;
    final basis = json['basis'] as Map<String, dynamic>?;
    final moderation = json['moderation'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    DateTime? at(String key) => switch (json[key]) {
      final String s => DateTime.parse(s).toLocal(),
      _ => null,
    };
    return Review(
      id: json['id'] as String,
      rating: json['rating'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      reviewerName: reviewer['name'] as String? ?? '',
      reviewerKind: reviewer['kind'] as String? ?? 'CUSTOMER',
      profileName: profile?['name'] as String?,
      profileSlug: profile?['slug'] as String?,
      basisKind: basis?['kind'] as String? ?? json['basis_kind'] as String?,
      basisReference: basis?['reference'] as String?,
      status: json['status'] as String?,
      statusLabel: json['status_label'] as String?,
      moderationReason: moderation?['reason'] as String?,
      publishedAt: at('published_at'),
      createdAt: at('created_at'),
      reply: switch (json['reply']) {
        final Map<String, dynamic> r => ReviewReply.fromJson(r),
        _ => null,
      },
      replyRemoved: json['reply_removed'] == true,
      canReply: can['reply'] as bool? ?? false,
      canEdit: can['edit'] as bool? ?? false,
      canDelete: can['delete'] as bool? ?? false,
    );
  }

  final String id;

  /// 1 to 5.
  final int rating;
  final String text;

  /// "Casey C.", an organisation's name, or "Former customer".
  final String reviewerName;
  final String reviewerKind;
  final String? profileName;
  final String? profileSlug;

  /// MAINTENANCE or ENQUIRY.
  final String? basisKind;
  final String? basisReference;

  /// The reviewer's own view: PENDING, PUBLISHED, HIDDEN or REJECTED.
  final String? status;
  final String? statusLabel;
  final String? moderationReason;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final ReviewReply? reply;
  final bool replyRemoved;
  final bool canReply;
  final bool canEdit;
  final bool canDelete;
}

class ProfileReviews {
  const ProfileReviews({
    required this.rating,
    required this.items,
    required this.total,
  });

  final Rating rating;
  final List<Review> items;
  final int total;
}

/// What a review can be written on: a finished job or a replied enquiry.
class ReviewBasis {
  const ReviewBasis({
    required this.kind,
    required this.id,
    required this.label,
    this.book,
  });

  factory ReviewBasis.fromJson(Map<String, dynamic> json, {String? book}) =>
      ReviewBasis(
        kind: json['kind'] as String,
        id: json['id'] as String,
        label: json['label'] as String? ?? json['reference'] as String? ?? '',
        book: book,
      );

  /// MAINTENANCE (a book's job) or ENQUIRY (the person's own).
  final String kind;
  final String id;
  final String label;

  /// The book a MAINTENANCE basis belongs to; null for the person's own.
  final String? book;
}

class UpcomingBasis {
  const UpcomingBasis(this.basis, this.reason, this.eligibleFrom);

  final ReviewBasis basis;

  /// NOT_COMPLETED, TOO_RECENT or NOT_REPLIED.
  final String reason;
  final DateTime? eligibleFrom;
}

class Eligibility {
  const Eligibility({
    required this.profileId,
    required this.reviewable,
    required this.bases,
    required this.upcoming,
    required this.reviewedCount,
  });

  factory Eligibility.fromJson(Map<String, dynamic> json, {String? book}) {
    final profile = json['profile'] as Map<String, dynamic>? ?? const {};
    return Eligibility(
      profileId: profile['id'] as String? ?? '',
      reviewable: json['reviewable'] as bool? ?? false,
      bases: [
        for (final b in json['bases'] as List? ?? const [])
          ReviewBasis.fromJson(b as Map<String, dynamic>, book: book),
      ],
      upcoming: [
        for (final u in json['upcoming'] as List? ?? const [])
          UpcomingBasis(
            ReviewBasis.fromJson(
              (u as Map<String, dynamic>)['basis'] as Map<String, dynamic>,
              book: book,
            ),
            u['reason'] as String? ?? '',
            switch (u['eligible_from']) {
              final String s => DateTime.parse(s).toLocal(),
              _ => null,
            },
          ),
      ],
      reviewedCount: (json['reviewed'] as List? ?? const []).length,
    );
  }

  final String profileId;

  /// False for other kinds and for the person's own organisation.
  final bool reviewable;
  final List<ReviewBasis> bases;
  final List<UpcomingBasis> upcoming;
  final int reviewedCount;

  bool get eligible => bases.isNotEmpty;
}

class ReviewsRepository {
  ReviewsRepository(this._api);

  final ApiClient _api;

  String _org(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}';

  Never _explain(ApiFailure failure) => throw switch (failure.code) {
    'REVIEW_EXISTS' => failure.withMessage(
      'A review has already been written for this job or enquiry.',
    ),
    'REVIEW_NOT_ELIGIBLE' => failure.withMessage(
      'This job or enquiry cannot be reviewed yet.',
    ),
    'REVIEW_ALREADY_REPORTED' => failure.withMessage(
      'You have already reported this review. A moderator will look at it.',
    ),
    'REVIEW_REPLY_EXISTS' => failure.withMessage(
      'This review already has your reply.',
    ),
    'REVIEW_REPLY_LOCKED' => failure.withMessage(
      'This reply can no longer be changed.',
    ),
    'REVIEW_LOCKED' => failure.withMessage(
      'Only a review awaiting moderation can be changed.',
    ),
    _ => failure,
  };

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiFailure catch (failure) {
      _explain(failure);
    }
  }

  /// Published reviews of a profile, with its rating. Public.
  Future<ProfileReviews> published(
    String kind,
    String slug, {
    int page = 1,
  }) async {
    final body = (await _api.get(
      '/v1/directory/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(slug)}/reviews?page=$page',
    )).body;
    return ProfileReviews(
      rating: Rating.fromJson(body['rating'] as Map<String, dynamic>?),
      items: [
        for (final r in body['items'] as List? ?? const [])
          Review.fromJson(r as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
    );
  }

  /// What the signed-in person (enquiries) or a book (maintenance jobs)
  /// may review on this profile.
  Future<Eligibility> eligibility(
    String kind,
    String slug, {
    String? book,
  }) async {
    final query = Uri(queryParameters: {'kind': kind, 'slug': slug}).query;
    final path = book == null
        ? '/v1/me/reviews/eligibility?$query'
        : '${_org(book)}/reviews/eligibility?$query';
    return Eligibility.fromJson((await _api.get(path)).body, book: book);
  }

  /// A new review waits for moderation ("Awaiting moderation").
  Future<Review> write({
    required String profileId,
    required ReviewBasis basis,
    required int rating,
    required String text,
  }) => _run(() async {
    final path = basis.book == null
        ? '/v1/me/reviews'
        : '${_org(basis.book!)}/reviews';
    return Review.fromJson(
      (await _api.postJson(path, {
            'directory_profile_id': profileId,
            'basis': {'kind': basis.kind, 'id': basis.id},
            'rating': rating,
            'text': text.trim(),
          })).body['review']
          as Map<String, dynamic>,
    );
  });

  /// The person's own reviews, or a book's.
  Future<List<Review>> written({String? book}) async => [
    for (final r
        in (await _api.get(
                  book == null ? '/v1/me/reviews' : '${_org(book)}/reviews',
                )).body['items']
                as List? ??
            const [])
      Review.fromJson(r as Map<String, dynamic>),
  ];

  Future<void> delete(String id, {String? book}) => _run(
    () => _api.delete(
      book == null
          ? '/v1/me/reviews/${Uri.encodeComponent(id)}'
          : '${_org(book)}/reviews/${Uri.encodeComponent(id)}',
    ),
  );

  /// The provider's published reviews, with whether replying is allowed.
  Future<({List<Review> items, bool canReply})> received(String book) async {
    final body = (await _api.get('${_org(book)}/reviews/received')).body;
    return (
      items: [
        for (final r in body['items'] as List? ?? const [])
          Review.fromJson(r as Map<String, dynamic>),
      ],
      canReply:
          (body['permissions'] as Map<String, dynamic>?)?['reply'] as bool? ??
          false,
    );
  }

  /// One reply per review, published at once.
  Future<Review> reply(String book, String id, String text) => _run(
    () async => Review.fromJson(
      (await _api.postJson(
            '${_org(book)}/reviews/${Uri.encodeComponent(id)}/reply',
            {'text': text.trim()},
          )).body['review']
          as Map<String, dynamic>,
    ),
  );

  /// Anyone signed in; one open report per person and review.
  Future<void> report(String id, String reason) => _run(
    () => _api.postJson('/v1/reviews/${Uri.encodeComponent(id)}/report', {
      'reason': reason.trim(),
    }),
  );

  /// The provider marks a business enquiry replied (needed before the
  /// customer may review it). Repeating changes nothing.
  Future<void> markReplied(String enquiryId) => _run(
    () => _api.post(
      '/v1/inbox/business-enquiries/${Uri.encodeComponent(enquiryId)}/replied',
    ),
  );
}
