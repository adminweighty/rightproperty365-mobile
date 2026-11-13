import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/async_view.dart';
import '../../markets/data/market.dart';
import '../data/listing.dart';
import 'widgets/listing_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();
  Future<List<Listing>>? _featured;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _featured ??= AppScope.of(context).listings.featured();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() => context.go(Routes.search(query: _query.text.trim()));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RightProperty365'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.x4),
            child: Center(
              child: Text(
                '${activeMarket.name} · ${activeMarket.currency}',
                style: text.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          ColoredBox(
            // The indigo brand panel: one per screen, same in light and dark.
            color: c.brand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x8,
                Space.x4,
                Space.x6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find the right property, and know your enquiry arrived.',
                    style: text.displaySmall?.copyWith(color: c.onBrand),
                  ),
                  const SizedBox(height: Space.x3),
                  Text(
                    'Homes, commercial space and land from verified agents and owners across Zimbabwe.',
                    style: text.bodyLarge?.copyWith(
                      color: c.onBrand.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: Space.x6),
                  TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'Suburb, city or property type',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: Space.x3),
                  SizedBox(
                    width: double.infinity,
                    // White on indigo: the primary colour would vanish here.
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.onBrand,
                        foregroundColor: c.brand,
                      ),
                      onPressed: _search,
                      child: const Text('Search'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x8,
              Space.x4,
              Space.x3,
            ),
            child: Semantics(
              header: true,
              child: Text('Browse by category', style: text.headlineSmall),
            ),
          ),
          for (final (category, icon, note) in const [
            (
              ListingCategory.residential,
              Icons.house_outlined,
              'Houses, apartments and townhouses',
            ),
            (
              ListingCategory.commercial,
              Icons.apartment_outlined,
              'Offices, retail and showrooms',
            ),
            (
              ListingCategory.land,
              Icons.landscape_outlined,
              'Stands, plots and farms',
            ),
          ])
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                0,
                Space.x4,
                Space.x3,
              ),
              child: Card(
                child: ListTile(
                  minTileHeight: 64,
                  leading: Icon(icon, color: c.primaryInk),
                  title: Text(category.label, style: text.titleMedium),
                  subtitle: Text(note, style: text.bodyMedium),
                  trailing: Icon(Icons.chevron_right, color: c.subtle),
                  onTap: () => context.go(Routes.search(category: category)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x6,
              Space.x4,
              Space.x3,
            ),
            child: Semantics(
              header: true,
              child: Text('Featured properties', style: text.headlineSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: SizedBox(
              // AsyncView centres its states; give them room before data arrives.
              child: AsyncView<List<Listing>>(
                future: _featured!,
                onRetry: () => setState(
                  () => _featured = AppScope.of(context).listings.featured(),
                ),
                builder: (context, listings) => Column(
                  children: [
                    for (final listing in listings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.x4),
                        child: ListingCard(
                          listing: listing,
                          onTap: () =>
                              context.push(Routes.listing(listing.slug)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x8),
            child: Text(
              'Development build. Listings shown are sample data.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
