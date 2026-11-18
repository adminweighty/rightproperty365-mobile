import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/reveal.dart';
import '../../directory/presentation/directory_screens.dart';
import '../data/listing.dart';
import 'widgets/listing_card.dart';

/// Cities that have a bundled photo. Others get a brand-coloured tile.
const _cityPhotos = {
  'Harare': 'assets/images/city-harare.jpg',
  'Bulawayo': 'assets/images/city-bulawayo.jpg',
  'Victoria Falls': 'assets/images/city-victoria-falls.jpg',
};

/// Values with how often they occur, most frequent first, then A to Z.
List<MapEntry<String, int>> _countBy(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts.entries.toList()..sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : a.key.compareTo(b.key);
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();
  Future<List<Listing>>? _listings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listings ??= AppScope.of(context).listings.search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() => context.go(Routes.search(query: _query.text.trim()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView<List<Listing>>(
        future: _listings!,
        onRetry: () => setState(() {
          _listings = AppScope.of(context).listings.search();
        }),
        builder: (context, listings) =>
            _HomeContent(listings: listings, query: _query, onSearch: _search),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.listings,
    required this.query,
    required this.onSearch,
  });

  final List<Listing> listings;
  final TextEditingController query;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final directory = AppScope.of(context).directory;
    final text = Theme.of(context).textTheme;

    final newest = [...listings]
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final featured = listings.where((l) => l.featured).toList();
    List<Listing> where(bool Function(Listing) test) =>
        newest.where(test).toList();
    final forSale = where(
      (l) =>
          l.deal == DealType.sale && l.category == ListingCategory.residential,
    );
    final toRent = where(
      (l) =>
          l.deal == DealType.rent && l.category == ListingCategory.residential,
    );
    final commercialAndLand = where(
      (l) => l.category != ListingCategory.residential,
    );
    final cities = _countBy(listings.map((l) => l.city));
    final suburbs = _countBy(listings.map((l) => l.suburb)).take(10).toList();
    final advertisers = listings.map((l) => l.advertiser.name).toSet().length;

    void open(Listing listing, String scope) =>
        context.push(Routes.listing(listing.slug, heroScope: scope));

    Widget rail(
      String title,
      String scope,
      List<Listing> items,
      String location,
      int index,
    ) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Reveal(
        index: index,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x8,
                Space.x2,
                Space.x3,
              ),
              child: SectionHeading(
                title,
                actionLabel: 'View all',
                onAction: () => context.go(location),
              ),
            ),
            ListingRail(
              listings: items,
              heroScope: scope,
              onOpen: (listing) => open(listing, scope),
            ),
          ],
        ),
      );
    }

    const pad = EdgeInsets.symmetric(horizontal: Space.x4);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(
          slides: featured.isEmpty ? newest.take(3).toList() : featured,
          query: query,
          onSearch: onSearch,
          onOpen: (listing) => open(listing, 'hero'),
        ),
        _Stats([
          (listings.length, 'properties'),
          (cities.length, 'cities and towns'),
          (advertisers, 'advertisers'),
        ]),
        rail('Just listed', 'new', newest.take(8).toList(), Routes.search(), 1),
        rail('Featured collection', 'featured', featured, Routes.search(), 2),
        rail(
          'Homes for sale',
          'sale',
          forSale,
          Routes.search(
            deal: DealType.sale,
            category: ListingCategory.residential,
          ),
          3,
        ),
        rail(
          'Homes to rent',
          'rent',
          toRent,
          Routes.search(
            deal: DealType.rent,
            category: ListingCategory.residential,
          ),
          3,
        ),
        rail(
          'Commercial and land',
          'commercial',
          commercialAndLand,
          Routes.search(category: ListingCategory.commercial),
          3,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(Space.x4, Space.x8, Space.x4, Space.x3),
          child: SectionHeading('Explore by city'),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: pad,
            itemCount: cities.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.x3),
            itemBuilder: (context, index) => _CityTile(
              city: cities[index].key,
              count: cities[index].value,
              onTap: () => context.go(Routes.search(query: cities[index].key)),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(Space.x4, Space.x8, Space.x4, Space.x3),
          child: SectionHeading('Popular suburbs'),
        ),
        Padding(
          padding: pad,
          child: Wrap(
            spacing: Space.x2,
            runSpacing: Space.x1,
            children: [
              for (final suburb in suburbs)
                ActionChip(
                  label: Text('${suburb.key} (${suburb.value})'),
                  onPressed: () => context.go(Routes.search(query: suburb.key)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x8,
            Space.x2,
            Space.x3,
          ),
          child: SectionHeading(
            'Property directory',
            actionLabel: 'View all',
            onAction: () => context.go(Routes.directory),
          ),
        ),
        for (final info in directory.directories)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: DirectoryTile(
              info: info,
              count: directory.ofKind(info.kind).length,
              onTap: () => context.push(Routes.directoryKind(info.kind)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x3,
            Space.x4,
            Space.x8,
          ),
          child: Text(
            'Development build. Listings and profiles shown are sample data.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Photo hero. The featured listings rotate behind the headline and search
/// field. Rotation stops when the OS asks for reduced motion.
class _Hero extends StatefulWidget {
  const _Hero({
    required this.slides,
    required this.query,
    required this.onSearch,
    required this.onOpen,
  });

  final List<Listing> slides;
  final TextEditingController query;
  final VoidCallback onSearch;
  final void Function(Listing listing) onOpen;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  static const _interval = Duration(seconds: 6);

  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (!MediaQuery.disableAnimationsOf(context) && widget.slides.length > 1) {
      _timer = Timer.periodic(_interval, (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.slides.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final listing = widget.slides[_index];
    final still = MediaQuery.disableAnimationsOf(context);

    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              child: Image.asset(
                listing.image.asset,
                key: ValueKey(listing.id),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 1200,
              ),
            ),
          ),
        ),
        // Indigo scrim, so white text keeps its contrast on any photo.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.brandDeep.withValues(alpha: 0.88),
                  c.brandDeep.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x4,
              Space.x4,
              Space.x6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandLogo(reverse: true),
                const SizedBox(height: Space.x8),
                Reveal(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(
                        text: 'Find the right property, ',
                        children: [
                          TextSpan(
                            text: 'and know your enquiry arrived.',
                            style: TextStyle(color: c.brandAccent),
                          ),
                        ],
                      ),
                      style: text.displaySmall?.copyWith(color: c.onBrand),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x3),
                Reveal(
                  index: 1,
                  child: Text(
                    'Homes, commercial space and land from verified Estate Agents, Landlords and Property Sellers across Zimbabwe.',
                    style: text.bodyLarge?.copyWith(color: c.onBrand),
                  ),
                ),
                const SizedBox(height: Space.x6),
                Reveal(
                  index: 2,
                  child: BrandSearchField(
                    controller: widget.query,
                    onSubmitted: widget.onSearch,
                  ),
                ),
                const SizedBox(height: Space.x5),
                Reveal(
                  index: 3,
                  child: Semantics(
                    button: true,
                    label: 'Featured: ${listing.spokenSummary}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => widget.onOpen(listing),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: still ? Duration.zero : Motion.slow,
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [...previous, ?current],
                                ),
                                child: Column(
                                  key: ValueKey(listing.id),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Featured · ${listing.location}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: c.onBrand,
                                      ),
                                    ),
                                    Text(
                                      '${listing.title} · ${formatMoney(listing.price)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: c.onBrand,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_forward, color: c.brandAccent),
                          ],
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
    );
  }
}

/// Three headline numbers on the brand indigo. They count up once, unless the
/// OS asks for reduced motion.
class _Stats extends StatelessWidget {
  const _Stats(this.stats);

  final List<(int, String)> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: c.brand,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (value, label) in stats)
              Expanded(
                child: Semantics(
                  label: '$value $label',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: still ? value.toDouble() : 0,
                          end: value.toDouble(),
                        ),
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, shown, _) => Text(
                          '${shown.round()}',
                          style: displayStyle(c.brandAccent, 30),
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, color: c.onBrand),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.city,
    required this.count,
    required this.onTap,
  });

  final String city;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = _cityPhotos[city];
    return Semantics(
      button: true,
      label: '$city, ${count == 1 ? '1 property' : '$count properties'}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: SizedBox(
          width: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null)
                Image.asset(photo, fit: BoxFit.cover, cacheWidth: 700)
              else
                DecoratedBox(
                  decoration: BoxDecoration(gradient: brandGradient(c)),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.brandDeep.withValues(alpha: 0.1),
                      c.brandDeep.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(city, style: displayStyle(c.onBrand, 20)),
                        Text(
                          count == 1 ? '1 property' : '$count properties',
                          style: TextStyle(fontSize: 14, color: c.onBrand),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
