import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../listings/data/listing.dart';
import '../listings/presentation/widgets/listing_card.dart';
import 'activity_store.dart';

/// The customer's requests and saved properties.
///
/// Both are kept on this phone (see [ActivityStore]). The screen says so, and
/// shows the status from each receipt without claiming it is up to date.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final activity = AppScope.of(context).activity;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activity'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Requests'),
              Tab(text: 'Saved'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: activity,
          builder: (context, _) =>
              TabBarView(children: [_Requests(activity), _Saved(activity)]),
        ),
      ),
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests(this.activity);

  final ActivityStore activity;

  Future<void> _confirmClear(BuildContext context) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this list?'),
        content: const Text(
          'This removes the list from this phone only. Your requests stay with the agents and '
          'businesses you sent them to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear list'),
          ),
        ],
      ),
    );
    if (clear ?? false) await activity.clearRequests();
  }

  @override
  Widget build(BuildContext context) {
    final requests = activity.requests;
    final text = Theme.of(context).textTheme;

    if (requests.isEmpty) {
      return MessageView(
        icon: Icons.inbox_outlined,
        title: 'No requests yet',
        body:
            'When you contact an agent, seller or business, the request and its reference are '
            'kept here so you can follow up.',
        actionLabel: 'Find a property',
        onAction: () => context.go(Routes.search()),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Text(
          'Requests sent from this phone. Replies come by the contact method you chose; '
          'the status here is from when the request was saved.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x4),
        for (final request in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: _RequestCard(request),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('clear-requests'),
            onPressed: () => _confirmClear(context),
            child: const Text('Clear this list'),
          ),
        ),
      ],
    );
  }
}

/// Customer-facing words for a request status. Only "Received" is certain;
/// it means saved by RightProperty365, not delivered or read.
String requestStatusLabel(String status) => switch (status) {
  'RECEIVED' => 'Received',
  'ROUTED' => 'Sent to agent or seller',
  'IN_PROGRESS' => 'In progress',
  'RESPONDED' => 'Responded',
  'CLOSED' => 'Closed',
  'ROUTING_EXCEPTION' => 'Unable to route',
  _ => 'Received',
};

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.request);

  final SentRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final sent = DateFormat('d MMM y, HH:mm').format(request.sentAt.toLocal());
    final status = requestStatusLabel(request.status);
    return BrandCard(
      onTap: () => context.push(request.route),
      semanticLabel:
          '${request.title}, sent to ${request.recipient} on $sent. '
          'Status $status. Reference ${request.reference}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(request.title, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(status, tone: BadgeTone.success),
              ],
            ),
            const SizedBox(height: Space.x1),
            Text('To ${request.recipient} · $sent', style: text.bodyMedium),
            const SizedBox(height: Space.x2),
            Text(
              request.reference,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Saved extends StatefulWidget {
  const _Saved(this.activity);

  final ActivityStore activity;

  @override
  State<_Saved> createState() => _SavedState();
}

class _SavedState extends State<_Saved> {
  Future<List<Listing>>? _listings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listings ??= AppScope.of(context).listings.search();
  }

  @override
  Widget build(BuildContext context) {
    final slugs = widget.activity.savedSlugs;
    if (slugs.isEmpty) {
      return MessageView(
        icon: Icons.bookmark_border,
        title: 'Nothing saved yet',
        body: 'Tap the bookmark on a property to keep it here. Saved properties stay on this phone.',
        actionLabel: 'Browse properties',
        onAction: () => context.go(Routes.search()),
      );
    }

    return AsyncView<List<Listing>>(
      future: _listings!,
      builder: (context, listings) {
        // Saved order, skipping listings that are no longer published.
        final bySlug = {for (final listing in listings) listing.slug: listing};
        final saved = [for (final slug in slugs) ?bySlug[slug]];
        final gone = slugs.length - saved.length;
        return ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            if (gone > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: Text(
                  gone == 1
                      ? '1 saved property is no longer available.'
                      : '$gone saved properties are no longer available.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final listing in saved)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: ListingCard(
                  listing: listing,
                  heroScope: 'saved',
                  onTap: () => context.push(
                    Routes.listing(listing.slug, heroScope: 'saved'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bookmark toggle for a listing, for app bars.
class SaveListingButton extends StatelessWidget {
  const SaveListingButton({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final activity = AppScope.of(context).activity;
    return ListenableBuilder(
      listenable: activity,
      builder: (context, _) {
        final saved = activity.isSaved(slug);
        return IconButton(
          key: const Key('save-listing'),
          tooltip: saved ? 'Remove from saved' : 'Save property',
          isSelected: saved,
          icon: const Icon(Icons.bookmark_border),
          selectedIcon: const Icon(Icons.bookmark),
          onPressed: () async {
            await activity.toggleSaved(slug);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    saved ? 'Removed from saved' : 'Saved to Activity',
                  ),
                ),
              );
          },
        );
      },
    );
  }
}
