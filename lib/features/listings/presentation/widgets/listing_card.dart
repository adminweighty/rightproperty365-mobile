import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/format.dart';
import '../../../../core/widgets/badge.dart';
import '../../data/listing.dart';
import 'listing_media.dart';

/// Price in the display face, with "per month" for rentals.
class ListingPrice extends StatelessWidget {
  const ListingPrice(this.listing, {super.key, this.size = 24});

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

/// The unit of search results: media, price, title, location, facts. The
/// whole card is one button with a single spoken summary.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: listing.spokenSummary,
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ListingMedia(tone: listing.tone),
                  Positioned(
                    left: Space.x3,
                    top: Space.x3,
                    child: Row(
                      children: [
                        AppBadge(listing.deal.label, tone: BadgeTone.primary),
                        if (listing.featured) ...[
                          const SizedBox(width: 6),
                          const AppBadge('Featured', tone: BadgeTone.accent),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListingPrice(listing),
                    const SizedBox(height: Space.x2),
                    Text(listing.title, style: text.titleMedium),
                    const SizedBox(height: Space.x1),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 16, color: c.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(listing.location, style: text.bodyMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x3),
                    const Divider(),
                    const SizedBox(height: Space.x3),
                    ListingFacts(listing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
