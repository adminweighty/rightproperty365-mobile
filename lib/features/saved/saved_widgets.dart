import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../analytics/analytics_tracker.dart';
import '../listings/data/listing.dart';
import '../listings/presentation/widgets/listing_card.dart';
import 'saved_listings_repository.dart';

/// The heart that saves a listing. Signed out, it explains that saving
/// needs an account, opens sign-in, and saves once the person is back.
class SaveHeart extends StatelessWidget {
  const SaveHeart({
    super.key,
    required this.listingId,
    required this.title,
    this.onPhoto = false,
  });

  final String listingId;
  final String title;

  /// Drawn over a photo: a filled circle behind the icon keeps it legible.
  final bool onPhoto;

  Future<void> _tap(BuildContext context) async {
    final services = AppScope.of(context);
    final saved = services.saved;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    if (!saved.signedIn) {
      final signIn = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign in to save properties'),
          content: const Text(
            'Saved properties are kept with your account, so you find them on any device. '
            'You come straight back here after signing in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const Key('save-sign-in'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      if (signIn != true || !context.mounted) return;
      await context.push(Routes.signIn);
      if (!saved.signedIn) return;
      try {
        await saved.save(listingId);
        say('Saved to Activity');
      } on ApiFailure catch (failure) {
        say(failure.message);
      }
      return;
    }

    try {
      final now = await saved.toggle(listingId);
      say(now ? 'Saved to Activity' : 'Removed from saved');
    } on ApiFailure catch (failure) {
      say(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = AppScope.of(context).saved;
    final c = context.colors;
    return ListenableBuilder(
      listenable: saved,
      builder: (context, _) {
        final on = saved.isSaved(listingId);
        final icon = IconButton(
          key: Key('save-$listingId'),
          tooltip: on ? 'Saved. Remove $title from saved' : 'Save $title',
          isSelected: on,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.favorite_border,
            color: onPhoto ? Colors.white : null,
          ),
          selectedIcon: Icon(
            Icons.favorite,
            color: onPhoto ? Colors.white : c.danger,
          ),
          onPressed: () => _tap(context),
        );
        if (!onPhoto) return icon;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x8C000000),
            shape: BoxShape.circle,
          ),
          child: icon,
        );
      },
    );
  }
}

/// The Saved Properties tab of Activity.
class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  Future<({List<SavedListing> items, int total, int totalPages})>? _page;
  Future<List<Listing>>? _sample;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services.saved.signedIn) {
      _page ??= services.saved.repository.list(pageSize: 100);
      _sample ??= services.listings.search();
    }
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).saved.repository.list(pageSize: 100);
    setState(() {
      _page = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  Future<void> _remove(SavedListing item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context).saved.remove(item.listingId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed from saved')),
      );
      await _reload();
    } on ApiFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.saved.signedIn) {
      return MessageView(
        icon: Icons.favorite_border,
        title: 'Save properties to your account',
        body: 'Sign in, then tap the heart on any property. Saved properties follow you to every device.',
        actionLabel: 'Sign in',
        onAction: () => context.push(Routes.signIn),
      );
    }
    return FutureBuilder<
      ({List<SavedListing> items, int total, int totalPages})
    >(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Semantics(
              label: 'Loading',
              child: const CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return MessageView(
            icon: Icons.cloud_off_outlined,
            title: 'We could not load your saved properties',
            body: 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return MessageView(
            icon: Icons.favorite_border,
            title: 'Nothing saved yet',
            body: 'Tap the heart on a property to keep it here.',
            actionLabel: 'Browse properties',
            onAction: () => context.go(Routes.search()),
          );
        }
        return FutureBuilder<List<Listing>>(
          future: _sample,
          builder: (context, sample) {
            final byId = {
              for (final l in sample.data ?? const <Listing>[]) l.id: l,
            };
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(Space.x4),
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x4),
                      child: item.available && byId[item.listingId] != null
                          ? ListingCard(
                              listing: byId[item.listingId]!,
                              heroScope: 'saved',
                              placement: AnalyticsPlacement.saved,
                              rank: items.indexOf(item),
                              onTap: () => context.push(
                                Routes.listing(item.slug!, heroScope: 'saved'),
                              ),
                            )
                          : _SavedCard(item, onRemove: () => _remove(item)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A saved listing drawn from the API's card data: an unavailable one is
/// greyed, labelled and not a link.
class _SavedCard extends StatelessWidget {
  const _SavedCard(this.item, {required this.onRemove});

  final SavedListing item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final slug = item.slug;
    final muted = !item.available;
    final body = Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: text.titleMedium?.copyWith(
                    color: muted ? c.muted : null,
                  ),
                ),
              ),
              if (muted) ...[
                const SizedBox(width: Space.x2),
                AppBadge(item.unavailableLabel ?? 'No longer listed'),
              ],
            ],
          ),
          if (item.priceText != null)
            Text(item.priceText!, style: text.bodyLarge),
          if (item.place.isNotEmpty) Text(item.place, style: text.bodyMedium),
          Text(
            '${item.reference} · saved ${DateFormat('d MMM y').format(item.savedAt.toLocal())}',
            style: text.bodySmall,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (slug != null)
                TextButton(
                  onPressed: () =>
                      context.push(Routes.listing(slug, heroScope: 'saved')),
                  child: const Text('View property'),
                ),
              TextButton(
                key: Key('remove-saved-${item.listingId}'),
                onPressed: onRemove,
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: muted
          ? '${item.title}. ${item.unavailableLabel ?? 'No longer listed'}'
          : item.title,
      child: Opacity(
        opacity: muted ? 0.75 : 1,
        child: BrandOutline(active: false, child: body),
      ),
    );
  }
}
