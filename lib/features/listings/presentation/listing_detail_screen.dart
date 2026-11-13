import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../data/listing.dart';
import 'widgets/listing_card.dart';
import 'widgets/listing_media.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Future<Listing?>? _listing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listing ??= AppScope.of(context).listings.bySlug(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Listing?>(
      future: _listing!,
      onRetry: () => setState(
        () => _listing = AppScope.of(context).listings.bySlug(widget.slug),
      ),
      builder: (context, listing) {
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
        return _Detail(listing);
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.listing);

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final contact = listing.advertiser.kind == AdvertiserKind.agency
        ? 'agent'
        : 'seller';

    return Scaffold(
      appBar: AppBar(title: Text(listing.suburb)),
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
            child: Text('Contact the $contact'),
          ),
        ),
      ),
      body: ListView(
        children: [
          ListingMedia(tone: listing.tone, aspectRatio: 16 / 9),
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
                ListingPrice(listing, size: 32),
                const SizedBox(height: Space.x4),
                const Divider(),
                const SizedBox(height: Space.x3),
                ListingFacts(listing),
                const SizedBox(height: Space.x3),
                const Divider(),
                const SizedBox(height: Space.x6),
                Semantics(
                  header: true,
                  child: Text('About this property', style: text.headlineSmall),
                ),
                const SizedBox(height: Space.x2),
                Text(
                  listing.description,
                  style: text.bodyLarge?.copyWith(color: c.muted),
                ),
                const SizedBox(height: Space.x6),
                Semantics(
                  header: true,
                  child: Text('Features', style: text.headlineSmall),
                ),
                const SizedBox(height: Space.x2),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Advertised by', style: text.bodyMedium),
                              Text(
                                listing.advertiser.name,
                                style: text.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        if (listing.advertiser.verified)
                          const AppBadge(
                            'Verified',
                            tone: BadgeTone.success,
                            icon: Icons.verified_outlined,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.x4),
                Text(
                  'Listing reference ${listing.reference}',
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
