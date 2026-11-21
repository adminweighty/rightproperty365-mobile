import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/format.dart';
import '../../../../core/widgets/badge.dart';
import '../../../../core/widgets/brand.dart';
import '../../../saved/saved_widgets.dart';
import '../../../analytics/analytics_tracker.dart';
import '../../../analytics/impressions.dart';
import '../../data/listing.dart';

/// A listing photo cropped to [aspectRatio]. Wrapped in a [Hero] so it flies
/// between a card and the detail screen.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({
    super.key,
    required this.listing,
    this.aspectRatio = 16 / 10,
    this.heroScope = 'list',
    this.decorative = false,
  });

  final Listing listing;
  final double aspectRatio;

  /// Distinguishes heroes when the same listing appears in several rows.
  final String heroScope;

  /// True when surrounding text already describes the listing.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Hero(
        tag: 'listing-photo-$heroScope-${listing.id}',
        child: Image(
          image: listing.image.asset.isEmpty && listing.image.url != null
              ? ResizeImage(NetworkImage(listing.image.url!), width: 900)
              // Decode near display size; the bundled photos are much larger.
              : ResizeImage(AssetImage(listing.image.asset), width: 900),
          fit: BoxFit.cover,
          semanticLabel: decorative ? null : listing.image.alt,
          excludeFromSemantics: decorative,
          errorBuilder: (context, _, _) => ColoredBox(
            color: context.colors.sunken,
            child: Icon(
              Icons.home_work_outlined,
              color: context.colors.subtle,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

/// Price in the display style, with "per month" for rentals.
class ListingPrice extends StatelessWidget {
  const ListingPrice(this.listing, {super.key, this.size = 22});

  final Listing listing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        text: formatMoney(listing.price),
        style: displayStyle(c.ink, size),
        children: [
          if (listing.pricePerMonth)
            TextSpan(
              text: '  per month',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: c.muted,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// Up to three facts; missing values are left out rather than shown as a dash.
class ListingFacts extends StatelessWidget {
  const ListingFacts(this.listing, {super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final area = listing.floorArea ?? listing.landArea;
    final facts = <(IconData, String, String)>[
      if (listing.bedrooms != null)
        (
          Icons.bed_outlined,
          '${listing.bedrooms} bed',
          '${listing.bedrooms} bedrooms',
        ),
      if (listing.bathrooms != null)
        (
          Icons.bathtub_outlined,
          '${listing.bathrooms} bath',
          '${listing.bathrooms} bathrooms',
        ),
      if (area != null)
        (Icons.open_in_full, formatArea(area), '${formatArea(area)} area'),
    ];
    final style = TextStyle(fontSize: 14, color: context.colors.muted);
    return Wrap(
      spacing: Space.x4,
      runSpacing: Space.x1,
      children: [
        for (final (icon, label, spoken) in facts)
          Semantics(
            label: spoken,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: context.colors.muted),
                const SizedBox(width: 6),
                Text(label, style: style),
              ],
            ),
          ),
      ],
    );
  }
}

/// The unit of search results: photo, price, title, location, facts. The
/// whole card is one button with a single spoken summary. Featured listings
/// always carry the gradient outline.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.heroScope = 'list',
    this.compact = false,
    this.placement,
    this.rank = 0,
  });

  final Listing listing;
  final VoidCallback onTap;
  final String heroScope;

  /// Where the card is shown, for listing statistics; null is not counted.
  final AnalyticsPlacement? placement;

  /// Its position in that list.
  final int rank;

  /// For horizontal rows: no facts line, tighter text.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    // The heart sits outside the card, so it is its own button for screen
    // readers and its own tap target.
    final card = Stack(
      children: [
        _card(c, text),
        Positioned(
          right: Space.x2,
          top: Space.x2,
          child: SaveHeart(
            listingId: listing.id,
            title: listing.title,
            onPhoto: true,
          ),
        ),
      ],
    );
    final where = placement;
    return where == null
        ? card
        : ImpressionTracker(
            listingId: listing.id,
            placement: where,
            rank: rank,
            child: card,
          );
  }

  Widget _card(AppColors c, TextTheme text) {
    return BrandCard(
      onTap: onTap,
      emphasised: listing.featured,
      semanticLabel: listing.spokenSummary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ListingPhoto(
                listing: listing,
                heroScope: heroScope,
                decorative: true,
              ),
              Positioned(
                left: Space.x3,
                top: Space.x3,
                child: Row(
                  children: [
                    AppBadge(listing.deal.label, tone: BadgeTone.onPhoto),
                    if (listing.placementLabel case final label?) ...[
                      const SizedBox(width: 6),
                      AppBadge(
                        label,
                        key: Key('placement-${listing.id}'),
                        tone: BadgeTone.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.all(compact ? Space.x3 : Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListingPrice(listing, size: compact ? 18 : 22),
                const SizedBox(height: Space.x1),
                Text(
                  listing.title,
                  style: text.titleMedium,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.x1),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 16, color: c.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        listing.location,
                        style: text.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: Space.x3),
                  const Divider(),
                  const SizedBox(height: Space.x3),
                  ListingFacts(listing),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontally scrolling row of compact listing cards.
class ListingRail extends StatelessWidget {
  const ListingRail({
    super.key,
    required this.listings,
    required this.heroScope,
    required this.onOpen,
    this.placement,
  });

  final List<Listing> listings;
  final String heroScope;
  final AnalyticsPlacement? placement;
  final void Function(Listing listing) onOpen;

  @override
  Widget build(BuildContext context) {
    // Grows with the text size so large text is not clipped.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      // Photo (260 wide at 16:10) and padding, plus three lines of text.
      height: 192 + 104 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        itemCount: listings.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.x3),
        itemBuilder: (context, index) => SizedBox(
          width: 260,
          child: Align(
            alignment: Alignment.topCenter,
            child: ListingCard(
              listing: listings[index],
              heroScope: heroScope,
              compact: true,
              placement: placement,
              rank: index,
              onTap: () => onOpen(listings[index]),
            ),
          ),
        ),
      ),
    );
  }
}
