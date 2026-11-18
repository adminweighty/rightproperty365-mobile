import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/location.dart';
import '../../../core/widgets/async_view.dart';
import '../data/api_listing_repository.dart';
import '../data/listing.dart';
import 'listings_map.dart';
import 'widgets/listing_card.dart';

/// Search on a map: the results with a location, from the API. Moving the
/// map offers "Search this area"; "Near me" asks for the phone's position
/// only when tapped, after saying why. The results on the map are always
/// listed below it too, so the map is never the only way to a listing.
class MapSearchView extends StatefulWidget {
  const MapSearchView({super.key, required this.filters, required this.tiles});

  final ListingFilters filters;
  final MapTiles tiles;

  @override
  State<MapSearchView> createState() => _MapSearchViewState();
}

class _MapSearchViewState extends State<MapSearchView> {
  final _map = MapController();
  Future<MapSearchPage>? _page;
  Future<({int total, int mappable})>? _counts;
  LatLngBounds? _moved;

  /// Changes when the filters change, so the map is fitted to the new
  /// results; searching an area keeps the map where the person put it.
  int _fit = 0;
  bool _locating = false;

  ApiListingSearch get _search => AppScope.of(context).listingSearch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == null) _load();
  }

  @override
  void didUpdateWidget(MapSearchView old) {
    super.didUpdateWidget(old);
    final a = old.filters;
    final b = widget.filters;
    if (a.deal != b.deal || a.category != b.category || a.query != b.query) {
      _load();
    }
  }

  void _load({LatLngBounds? area}) {
    final bounds = area == null
        ? null
        : MapBounds(
            west: area.west,
            south: area.south,
            east: area.east,
            north: area.north,
          );
    final page = _search.mappable(
      widget.filters,
      bounds: bounds != null && bounds.valid ? bounds : null,
    );
    final counts = _search.counts(widget.filters);
    setState(() {
      if (area == null) _fit++;
      _page = page;
      _counts = counts;
      _moved = null;
    });
  }

  Future<void> _nearMe() async {
    final services = AppScope.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show properties near you?'),
        content: const Text(
          'RightProperty365 uses your location once, to move the map to where you are. '
          'It is not stored. Your phone will ask you to allow it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('near-me-continue'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _locating = true);
    final located = await services.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    final problem = located.problem;
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    _map.move(LatLng(located.latitude!, located.longitude!), 13);
    _load(area: _map.camera.visibleBounds);
  }

  void _open(Listing listing) =>
      context.push(Routes.listing(listing.slug, heroScope: 'map'));

  Future<void> _preview(Listing listing) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: SingleChildScrollView(
          child: ListingCard(
            listing: listing,
            heroScope: 'map-sheet',
            onTap: () {
              Navigator.pop(context);
              _open(listing);
            },
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(
      220.0,
      420.0,
    );
    return FutureBuilder<MapSearchPage>(
      future: _page,
      builder: (context, snapshot) {
        final page = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        if (snapshot.hasError) {
          return MessageView(
            icon: Icons.map_outlined,
            title: 'The map could not load results',
            body: 'It needs a connection. The list view still works.',
            actionLabel: 'Try again',
            onAction: _load,
          );
        }
        final listings = page?.listings ?? const <Listing>[];
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    ListingsMap(
                      // A new map when the results change, so it fits them.
                      key: ValueKey(_fit),
                      tiles: widget.tiles,
                      listings: listings,
                      controller: _map,
                      onSelect: _preview,
                      onMoved: (visible) {
                        if (_moved == null) setState(() => _moved = visible);
                        _moved = visible;
                      },
                    ),
                    Positioned(
                      top: Space.x2,
                      right: Space.x2,
                      child: FilledButton.tonalIcon(
                        key: const Key('near-me'),
                        onPressed: _locating ? null : _nearMe,
                        icon: const Icon(Icons.my_location),
                        label: Text(_locating ? 'Finding you…' : 'Near me'),
                      ),
                    ),
                    if (_moved != null)
                      Positioned(
                        bottom: Space.x6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FilledButton.icon(
                            key: const Key('search-this-area'),
                            onPressed: () => _load(area: _moved),
                            icon: const Icon(Icons.search),
                            label: const Text('Search this area'),
                          ),
                        ),
                      ),
                    if (loading)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(Space.x4),
              sliver: SliverList.list(
                children: [
                  FutureBuilder<({int total, int mappable})>(
                    future: _counts,
                    builder: (context, counts) {
                      final c = counts.data;
                      final shown = listings.length;
                      final missing = c == null ? 0 : c.total - c.mappable;
                      return Semantics(
                        liveRegion: true,
                        child: Text(
                          loading
                              ? 'Loading the map…'
                              : [
                                  shown == 1
                                      ? '1 property on the map'
                                      : '$shown properties on the map',
                                  if ((page?.mappableTotal ?? 0) > shown)
                                    'These are the first $shown: zoom in and search this area for the others',
                                  if (missing > 0)
                                    missing == 1
                                        ? '1 result has no location and is only in the list view'
                                        : '$missing results have no location and are only in the list view',
                                ].join('. '),
                          style: text.bodyMedium,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    'An approximate location is shown as an area, not an exact spot.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: Space.x4),
                  if (!loading && listings.isEmpty)
                    Text(
                      'No properties with a location here. Move the map and search this area, '
                      'or use the list view.',
                      style: text.bodyLarge,
                    ),
                  for (final listing in listings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x4),
                      child: ListingCard(
                        listing: listing,
                        heroScope: 'map-list',
                        onTap: () => _open(listing),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
