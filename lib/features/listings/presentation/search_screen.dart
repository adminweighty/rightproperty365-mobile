import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/brand.dart';
import '../../analytics/analytics_tracker.dart';
import '../../analytics/impressions.dart';
import '../data/listing.dart';
import 'map_search_view.dart';
import 'widgets/listing_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initial = const ListingFilters()});

  /// Filters carried in the route, for example from the home screen.
  final ListingFilters initial;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _query = TextEditingController(text: widget.initial.query);
  late DealType? _deal = widget.initial.deal;
  late ListingCategory? _category = widget.initial.category;
  Future<List<Listing>>? _results;

  /// The list is the default and always works; the map needs a tile source
  /// and the API.
  bool _map = false;

  ListingFilters get _filters =>
      ListingFilters(deal: _deal, category: _category, query: _query.text);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= AppScope.of(context).listings.search(_filters);
  }

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initial;
    final previous = oldWidget.initial;
    if (next.deal != previous.deal ||
        next.category != previous.category ||
        next.query != previous.query) {
      _deal = next.deal;
      _category = next.category;
      _query.text = next.query;
      _load();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _load() => setState(() {
    _results = AppScope.of(context).listings.search(_filters);
  });

  void _clear() {
    _query.clear();
    _deal = null;
    _category = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tiles = AppScope.of(context).mapTiles;
    final showMap = _map && tiles != null;
    // The bundled listings have no short stays; the map searches the API,
    // which does.
    final categories = [
      for (final c in ListingCategory.values)
        if (showMap || c != ListingCategory.shortStay) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ImpressionScope(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x4,
                Space.x4,
                Space.x2,
              ),
              child: BrandSearchField(controller: _query, onSubmitted: _load),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: Row(
                children: [
                  for (final deal in DealType.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.x2),
                      child: FilterChip(
                        label: Text(deal.label),
                        selected: _deal == deal,
                        onSelected: (selected) {
                          _deal = selected ? deal : null;
                          _load();
                        },
                      ),
                    ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.x2),
                      child: FilterChip(
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (selected) {
                          _category = selected ? category : null;
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (tiles != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  Space.x2,
                  Space.x4,
                  0,
                ),
                child: SegmentedButton<bool>(
                  key: const Key('search-view'),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('List'),
                      icon: Icon(Icons.view_list_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Map'),
                      icon: Icon(Icons.map_outlined),
                    ),
                  ],
                  selected: {_map},
                  onSelectionChanged: (v) => setState(() {
                    _map = v.first;
                    if (!_map && _category == ListingCategory.shortStay) {
                      _category = null;
                      _load();
                    }
                  }),
                ),
              ),
            const SizedBox(height: Space.x2),
            const Divider(),
            if (showMap)
              Expanded(
                child: MapSearchView(filters: _filters, tiles: tiles),
              )
            else
              Expanded(
                child: AsyncView<List<Listing>>(
                  future: _results!,
                  onRetry: _load,
                  builder: (context, listings) {
                    if (listings.isEmpty) {
                      return MessageView(
                        icon: Icons.search_off,
                        title: 'No properties match that search',
                        body: 'Try a nearby suburb, a different category, or clear the filters to see everything.',
                        actionLabel: 'Clear filters',
                        onAction: _clear,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(Space.x4),
                      itemCount: listings.length + 1,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.x4),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Semantics(
                            liveRegion: true,
                            child: Text(
                              listings.length == 1
                                  ? '1 property found'
                                  : '${listings.length} properties found',
                              style: text.bodyMedium,
                            ),
                          );
                        }
                        final listing = listings[index - 1];
                        return ListingCard(
                          listing: listing,
                          heroScope: 'search',
                          placement: AnalyticsPlacement.search,
                          rank: index - 1,
                          onTap: () => context.push(
                            Routes.listing(listing.slug, heroScope: 'search'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
