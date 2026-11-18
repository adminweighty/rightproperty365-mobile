import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/brand.dart';
import '../data/listing.dart';
import 'listings_map.dart';

/// "Location" on the listing page: a small map that stays still until it is
/// tapped (so scrolling the page never gets caught in it), with a note when
/// the location is approximate. Absent without a location or a tile source.
class ListingMapSection extends StatefulWidget {
  const ListingMapSection({super.key, required this.listing});

  final Listing listing;

  @override
  State<ListingMapSection> createState() => _ListingMapSectionState();
}

class _ListingMapSectionState extends State<ListingMapSection> {
  Future<ListingLocation?>? _location;
  bool _interactive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final known = widget.listing.position;
    _location ??= known != null
        ? Future.value(known)
        : AppScope.of(context).listingDetails.location(widget.listing.slug);
  }

  @override
  Widget build(BuildContext context) {
    final tiles = AppScope.of(context).mapTiles;
    if (tiles == null) return const SizedBox.shrink();
    return FutureBuilder<ListingLocation?>(
      future: _location,
      builder: (context, snapshot) {
        final location = snapshot.data;
        if (location == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        final c = context.colors;
        final placed = widget.listing.withLocation(location);
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('Location'),
              const SizedBox(height: Space.x3),
              if (location.approximate)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Text(
                    'Approximate location: the advertiser shows the area, not the exact address.',
                    style: text.bodyMedium,
                  ),
                ),
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: Stack(
                    children: [
                      ListingsMap(
                        key: ValueKey(_interactive),
                        tiles: tiles,
                        listings: [placed],
                        interactive: _interactive,
                        initialZoom: location.approximate ? 13 : 15,
                        onSelect: (_) {},
                      ),
                      if (!_interactive)
                        Positioned.fill(
                          child: Semantics(
                            button: true,
                            label:
                                'Map of ${widget.listing.title}. Tap to move and zoom it',
                            excludeSemantics: true,
                            child: InkWell(
                              key: const Key('listing-map-activate'),
                              onTap: () => setState(() => _interactive = true),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Container(
                                  margin: const EdgeInsets.all(Space.x2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.x2,
                                    vertical: Space.x1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(
                                      Radii.sm,
                                    ),
                                  ),
                                  child: Text(
                                    'Tap to move the map',
                                    style: text.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
