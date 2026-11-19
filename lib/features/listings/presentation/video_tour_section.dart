import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/brand.dart';
import '../../analytics/analytics_tracker.dart';
import '../data/video_tour.dart';

/// "Video tour" on the listing page, when the listing has one.
///
/// A poster from YouTube's thumbnail with a play button that hands over to
/// the YouTube app or the browser, YouTube's own official player; nothing is
/// downloaded, re-hosted or played before the person presses play. If the
/// thumbnail cannot be loaded (a removed video), or YouTube cannot be
/// opened, a neutral panel offers the link instead.
class VideoTourSection extends StatefulWidget {
  const VideoTourSection({
    super.key,
    required this.slug,
    required this.title,
    this.listingId,
    this.posterImage,
    this.tour,
  });

  /// The tour when the page already has it (a development project's);
  /// otherwise it is fetched for the listing [slug].
  final Future<VideoTour?>? tour;

  /// For listing statistics (a play is counted as youtube_play_intent).
  final String? listingId;

  final String slug;
  final String title;

  /// Replaces the thumbnail from YouTube (tests have no network).
  @visibleForTesting
  final ImageProvider? posterImage;

  @override
  State<VideoTourSection> createState() => _VideoTourSectionState();
}

class _VideoTourSectionState extends State<VideoTourSection> {
  Future<VideoTour?>? _tour;
  bool _posterFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tour ??=
        widget.tour ??
        AppScope.of(context).listingDetails.videoTour(widget.slug);
  }

  Future<void> _open(Uri url) async {
    final opened = await AppScope.of(context).openLink(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube could not be opened on this phone.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoTour?>(
      future: _tour,
      builder: (context, snapshot) {
        final tour = snapshot.data;
        // No tour, or not loaded yet: the section is simply not there.
        if (tour == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('Video tour'),
              const SizedBox(height: Space.x3),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: _posterFailed
                      ? _Unavailable(onWatch: () => _open(tour.watchUrl))
                      : _Poster(
                          tour: tour,
                          title: widget.title,
                          image: widget.posterImage,
                          onPlay: () {
                            final id = widget.listingId;
                            if (id != null) {
                              AppScope.of(context).analytics.record(
                                AnalyticsEventType.videoPlayIntent,
                                id,
                              );
                            }
                            _open(tour.openUrl);
                          },
                          onFailed: () {
                            if (!_posterFailed && mounted) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() => _posterFailed = true);
                                }
                              });
                            }
                          },
                        ),
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                'Plays in the YouTube app or on youtube.com. YouTube may set cookies when you press play.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              TextButton(
                key: const Key('youtube-privacy'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _open(youtubePrivacyUrl),
                child: const Text('YouTube\'s privacy policy'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.tour,
    required this.title,
    required this.onPlay,
    required this.onFailed,
    this.image,
  });

  final VideoTour tour;
  final ImageProvider? image;
  final String title;
  final VoidCallback onPlay;
  final VoidCallback onFailed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.ink),
        Image(
          image: image ?? NetworkImage(tour.thumbnailUrl.toString()),
          fit: BoxFit.cover,
          semanticLabel: 'Video tour of $title',
          errorBuilder: (_, _, _) {
            onFailed();
            return const SizedBox.shrink();
          },
        ),
        Center(
          child: FilledButton.icon(
            key: const Key('play-video-tour'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: c.surface,
              foregroundColor: c.ink,
            ),
            onPressed: onPlay,
            icon: Icon(Icons.play_circle_fill, color: c.primary),
            label: const Text('Play the video tour (YouTube)'),
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onWatch});

  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: c.sunken,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.videocam_off_outlined, color: c.muted),
              ),
              const SizedBox(height: Space.x2),
              Text(
                'This video can\'t be shown here',
                style: text.titleSmall,
                textAlign: TextAlign.center,
              ),
              TextButton(
                key: const Key('watch-on-youtube'),
                onPressed: onWatch,
                child: const Text('Watch on YouTube'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
