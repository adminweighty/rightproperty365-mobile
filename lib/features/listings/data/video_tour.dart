import '../../../core/api/api_client.dart';

/// YouTube's privacy policy, linked next to every video tour.
final youtubePrivacyUrl = Uri.parse('https://policies.google.com/privacy');

/// A listing's YouTube video tour (`ListingVideo`, API 0.28.0). The API
/// never checks the video with YouTube, so it may be removed, private or not
/// embeddable: the app shows the poster and falls back to a link.
class VideoTour {
  const VideoTour({
    required this.id,
    required this.watchUrl,
    required this.thumbnailUrl,
    this.startSeconds,
  });

  factory VideoTour.fromJson(Map<String, dynamic> json) => VideoTour(
    id: json['id'] as String,
    startSeconds: json['start_seconds'] as int?,
    watchUrl: Uri.parse(json['watch_url'] as String),
    thumbnailUrl: Uri.parse(json['thumbnail_url'] as String),
  );

  final String id;
  final int? startSeconds;
  final Uri watchUrl;
  final Uri thumbnailUrl;

  /// Where the person is sent to watch: YouTube's own app or site, at the
  /// start time the advertiser chose. Nothing is downloaded or re-hosted.
  Uri get openUrl {
    final start = startSeconds;
    if (start == null || start == 0) return watchUrl;
    return watchUrl.replace(
      queryParameters: {...watchUrl.queryParameters, 't': '${start}s'},
    );
  }
}

/// The parts of the public listing (`GET /v1/listings/{slug}`) that the
/// bundled sample listings do not carry yet: the video tour.
abstract interface class ListingDetailsRepository {
  /// The listing's video tour, or null when it has none, is no longer
  /// public, or the API cannot be reached (the listing page works without).
  Future<VideoTour?> videoTour(String slug);
}

class ApiListingDetailsRepository implements ListingDetailsRepository {
  ApiListingDetailsRepository(this._api);

  final ApiClient _api;

  @override
  Future<VideoTour?> videoTour(String slug) async {
    try {
      final body = (await _api.get('/v1/listings/${Uri.encodeComponent(slug)}'))
          .body;
      final listing = body['listing'] ?? body;
      final video = (listing as Map<String, dynamic>)['video'];
      return video is Map<String, dynamic> && video['provider'] == 'YOUTUBE'
          ? VideoTour.fromJson(video)
          : null;
    } on ApiFailure {
      return null;
    }
  }
}
