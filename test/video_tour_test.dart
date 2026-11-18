import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/features/listings/data/video_tour.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';
import 'package:rightproperty365/features/listings/presentation/video_tour_section.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show serve, settle, stampPng;

Map<String, dynamic> video({int? start = 30}) => {
  'provider': 'YOUTUBE',
  'id': 'aqz-KE-bpKQ',
  'start_seconds': start,
  'embed_url': 'https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ?rel=0&modestbranding=1',
  'watch_url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
  'thumbnail_url': 'https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg',
};

void main() {
  group('video tours API', () {
    test('reads the tour, or nothing when there is none', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/listings/with-video': (_) => {
          'listing': {
            'slug': 'with-video',
            'video': video(),
            'has_video': true,
          },
        },
        'GET /v1/listings/no-video': (_) => {
          'listing': {'slug': 'no-video', 'video': null, 'has_video': false},
        },
        'GET /v1/listings/gone': (_) => apiError(404, 'LISTING_NOT_FOUND'),
      });
      final details = ApiListingDetailsRepository(api);

      final tour = (await details.videoTour('with-video'))!;
      expect(tour.id, 'aqz-KE-bpKQ');
      expect(
        tour.openUrl.toString(),
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=30s',
      );
      expect(VideoTour.fromJson(video(start: null)).openUrl, tour.watchUrl);
      expect(await details.videoTour('no-video'), isNull);
      expect(await details.videoTour('gone'), isNull);
      expect(requests.first.url.path, '/v1/listings/with-video');
    });
  });

  group('the listing page', () {
    testWidgets('shows no tour section without a video', (tester) async {
      final test = TestServices();
      final listing = test.listings.listings[0];
      await pumpInApp(tester, test, ListingDetailScreen(slug: listing.slug));
      await settle(tester);
      expect(find.text('Video tour'), findsNothing);
    });

    testWidgets('falls back to a link when the poster cannot load, and opens '
        'YouTube', (tester) async {
      final test = TestServices();
      final listing = test.listings.listings[0];
      serve(test, {
        'GET /v1/listings/${listing.slug}': (_) => {
          'listing': {'slug': listing.slug, 'video': video()},
        },
      });
      await pumpInApp(tester, test, ListingDetailScreen(slug: listing.slug));
      await settle(tester);
      expect(find.text('Video tour'), findsOneWidget);
      expect(
        find.textContaining('YouTube may set cookies when you press play'),
        findsOneWidget,
      );

      // Tests have no network, so the thumbnail fails as for a removed video.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await settle(tester);
      expect(find.text('This video can\'t be shown here'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('watch-on-youtube')));
      await tester.tap(find.byKey(const Key('watch-on-youtube')));
      await settle(tester);
      expect(
        test.opened.single.toString(),
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
      );

      test.canOpenLinks = false;
      await tester.ensureVisible(find.byKey(const Key('youtube-privacy')));
      await tester.tap(find.byKey(const Key('youtube-privacy')));
      await settle(tester);
      expect(test.opened.last, youtubePrivacyUrl);
      expect(
        find.text('YouTube could not be opened on this phone.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('play hands over to YouTube at the start time', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/listings/with-video': (_) => {
          'listing': {'slug': 'with-video', 'video': video()},
        },
      });
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: VideoTourSection(
            slug: 'with-video',
            title: 'Garden cottage',
            posterImage: MemoryImage(stampPng),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.bySemanticsLabel('Video tour of Garden cottage'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('play-video-tour')));
      await tester.pump();
      expect(
        test.opened.single.toString(),
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=30s',
      );
    });
  });
}
