import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/terminology.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../listings/data/listing.dart';
import '../listings/presentation/widgets/listing_card.dart';
import '../appointments/appointment_screens.dart';
import 'activity_store.dart';
import 'my_request_screen.dart';
import 'my_requests_repository.dart';

/// The customer's requests, viewings and saved properties.
///
/// Signed in, enquiries and viewings come from the API with their live
/// status. As a guest, only what this phone sent is listed (see
/// [ActivityStore]), with the status from each receipt, which is not updated.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final activity = services.activity;
    return ListenableBuilder(
      listenable: services.auth,
      builder: (context, _) {
        final signedIn = services.auth.signedIn;
        return DefaultTabController(
          key: ValueKey(signedIn),
          length: signedIn ? 3 : 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Activity'),
              bottom: TabBar(
                isScrollable: signedIn,
                tabs: [
                  const Tab(text: 'My Enquiries'),
                  if (signedIn) const Tab(text: 'My Viewings'),
                  const Tab(text: 'Saved Properties'),
                ],
              ),
            ),
            body: ListenableBuilder(
              listenable: activity,
              builder: (context, _) => TabBarView(
                children: [
                  signedIn ? _AccountRequests(activity) : _Requests(activity),
                  if (signedIn) const MyViewingsView(),
                  _Saved(activity),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Signed in: the requests the account sent, with their live status, then
/// anything this phone sent as a guest.
class _AccountRequests extends StatefulWidget {
  const _AccountRequests(this.activity);

  final ActivityStore activity;

  @override
  State<_AccountRequests> createState() => _AccountRequestsState();
}

class _AccountRequestsState extends State<_AccountRequests> {
  Future<({List<MyRequest> items, int total})>? _requests;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requests ??= AppScope.of(context).myRequests.list();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).myRequests.list();
    setState(() {
      _requests = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<({List<MyRequest> items, int total})>(
      future: _requests,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Semantics(
              label: 'Loading',
              child: const CircularProgressIndicator(),
            ),
          );
        }
        final mine = snapshot.data?.items ?? const <MyRequest>[];
        final references = {for (final r in mine) r.reference};
        // Guest enquiries from this phone are never linked to the account.
        final fromPhone = [
          for (final r in widget.activity.requests)
            if (!references.contains(r.reference)) r,
        ];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x4),
                  child: Column(
                    children: [
                      Text(
                        'We could not load the enquiries on your account.',
                        style: text.titleMedium,
                      ),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              else if (mine.isEmpty && fromPhone.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x6),
                  child: Column(
                    children: [
                      Text('No enquiries yet', style: text.titleMedium),
                      const SizedBox(height: Space.x2),
                      Text(
                        'Enquiries you send while signed in appear here, with their status as '
                        'the Estate Agent, Landlord or Property Seller works on them.',
                        style: text.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => context.go(Routes.search()),
                        child: const Text('Find a property'),
                      ),
                    ],
                  ),
                )
              else if (mine.isNotEmpty) ...[
                Text(
                  'Statuses update as your enquiries are worked on. Pull down to refresh.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x4),
                for (final r in mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: MyRequestCard(
                      r,
                      onTap: () async {
                        await context.push(Routes.myRequest(r.id));
                        if (mounted) _reload();
                      },
                    ),
                  ),
              ],
              if (fromPhone.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('Sent from this phone'),
                const SizedBox(height: Space.x2),
                Text(
                  'Sent as a guest or to a business. Their status is from when they were sent.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x3),
                for (final r in fromPhone)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _RequestCard(r),
                  ),
              ],
            ],
          ),
        );
      },
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
          'This removes the list from this phone only. Your enquiries stay with the Estate Agents and '
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
        title: 'No enquiries yet',
        body:
            'When you contact an Estate Agent, Landlord, Property Seller or business, the enquiry and its reference are '
            'kept here so you can follow up.',
        actionLabel: 'Find a property',
        onAction: () => context.go(Routes.search()),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Text(
          'Enquiries sent from this phone. Replies come by the contact method you chose; '
          'the status here is from when the enquiry was saved.',
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

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.request);

  final SentRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final sent = DateFormat('d MMM y, HH:mm').format(request.sentAt.toLocal());
    final status = enquiryStatusLabel(request.status);
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
