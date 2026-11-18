import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/terminology.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../../saved/saved_widgets.dart';
import '../../applications/received_applications.dart' show ApplySection;
import '../../venues/venue_screens.dart' show HourlyBookingSection;
import 'listing_map_section.dart';
import 'video_tour_section.dart';
import '../../analytics/analytics_tracker.dart';
import '../../directory/data/profile.dart';
import '../../directory/presentation/widgets/profile_widgets.dart';
import '../data/listing.dart';
import 'widgets/listing_card.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.slug,
    this.heroScope = 'list',
  });

  final String slug;

  /// The row the listing was opened from, so its photo can fly across.
  final String heroScope;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Future<Listing?>? _listing;
  bool _viewCounted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listing ??= AppScope.of(context).listings.bySlug(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Listing?>(
      future: _listing!,
      onRetry: () => setState(() {
        _listing = AppScope.of(context).listings.bySlug(widget.slug);
      }),
      builder: (context, listing) {
        if (listing != null && !_viewCounted) {
          // Once per listing page; the API also drops a repeat within 30 min.
          _viewCounted = true;
          AppScope.of(context).analytics
              .record(AnalyticsEventType.detailView, listing.id);
        }
        if (listing == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const MessageView(
              icon: Icons.home_outlined,
              title: 'This listing is no longer available',
              body: 'It may have expired or been removed. Current listings are a search away.',
            ),
          );
        }
        return _Detail(listing, widget.heroScope);
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.listing, this.heroScope);

  final Listing listing;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final isAgency = listing.advertiser.kind == AdvertiserKind.agency;
    final profiles = AppScope.of(context).directory.profilesFor(listing);

    return Scaffold(
      appBar: AppBar(
        title: Text(listing.suburb),
        actions: [SaveHeart(listingId: listing.id, title: listing.title)],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x2,
            Space.x4,
            Space.x3,
          ),
          child: FilledButton(
            onPressed: () => context.push(Routes.request(listing.slug)),
            child: Text('Contact the ${listing.contactTitle}'),
          ),
        ),
      ),
      body: ListView(
        children: [
          ListingPhoto(
            listing: listing,
            aspectRatio: 16 / 10,
            heroScope: heroScope,
          ),
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    AppBadge(listing.deal.label, tone: BadgeTone.primary),
                    AppBadge(listing.category.label),
                    AppBadge(listing.propertyType),
                  ],
                ),
                const SizedBox(height: Space.x4),
                Semantics(
                  header: true,
                  child: Text(listing.title, style: text.headlineMedium),
                ),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: c.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        listing.location,
                        style: text.bodyLarge?.copyWith(color: c.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x5),
                ListingPrice(listing, size: 30),
                const SizedBox(height: Space.x4),
                const Divider(),
                const SizedBox(height: Space.x3),
                ListingFacts(listing),
                const SizedBox(height: Space.x3),
                const Divider(),
                const SizedBox(height: Space.x6),
                const SectionHeading('About this property'),
                const SizedBox(height: Space.x3),
                Text(
                  listing.description,
                  style: text.bodyLarge?.copyWith(color: c.muted),
                ),
                const SizedBox(height: Space.x6),
                HourlyBookingSection(
                  listingId: listing.id,
                  slug: listing.slug,
                  title: listing.title,
                ),
                ApplySection(slug: listing.slug),
                ListingMapSection(listing: listing),
                VideoTourSection(
                  slug: listing.slug,
                  title: listing.title,
                  listingId: listing.id,
                ),
                const SectionHeading('Features'),
                const SizedBox(height: Space.x3),
                for (final feature in listing.features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x1),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.check,
                            size: 18,
                            color: c.primaryInk,
                          ),
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(child: Text(feature, style: text.bodyLarge)),
                      ],
                    ),
                  ),
                const SizedBox(height: Space.x6),
                SectionHeading(isAgency ? 'Listed by' : 'Offered by the owner'),
                const SizedBox(height: Space.x3),
                _ListedBy(
                  name: listing.listedBy,
                  detail: listing.contactTitle,
                  verified: !isAgency && listing.advertiser.verified,
                  profile: profiles.agent,
                ),
                if (isAgency) ...[
                  const SizedBox(height: Space.x3),
                  _ListedBy(
                    name: listing.advertiser.name,
                    detail: Terms.agency,
                    verified: listing.advertiser.verified,
                    profile: profiles.agency,
                  ),
                ],
                const SizedBox(height: Space.x4),
                Text(
                  'Listed ${DateFormat('d MMMM y').format(listing.publishedAt.toLocal())}'
                  ' · Reference ${listing.reference}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The agent, agency or owner behind a listing. Links to the directory
/// profile when one exists. Never shows a phone number or email address.
class _ListedBy extends StatelessWidget {
  const _ListedBy({
    required this.name,
    required this.detail,
    required this.verified,
    required this.profile,
  });

  final String name;
  final String detail;
  final bool verified;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final profile = this.profile;
    return BrandCard(
      onTap: profile == null
          ? null
          : () => context.push(Routes.profile(profile)),
      semanticLabel: profile == null ? null : '$name, $detail. View profile',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          children: [
            if (profile != null) ...[
              ProfileAvatar(profile, size: 44),
              const SizedBox(width: Space.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.titleMedium),
                  Text(detail, style: text.bodyMedium),
                ],
              ),
            ),
            if (verified || (profile?.verified ?? false)) const VerifiedBadge(),
            if (profile != null) Icon(Icons.chevron_right, color: c.subtle),
          ],
        ),
      ),
    );
  }
}
