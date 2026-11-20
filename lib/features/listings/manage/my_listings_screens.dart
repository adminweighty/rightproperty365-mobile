import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../../auth/presentation/auth_screens.dart' show FailureBox;
import 'my_listings.dart';

final _day = DateFormat('d MMM y');

String expiryDate(ListingExpiry e) => _day.format(e.expiresAt.toLocal());

/// Published or paused: the publication period is running (a pause never
/// extends it).
bool _running(String status) => status == 'PUBLISHED' || status == 'PAUSED';

/// "Expires in 6 days" or "Expires tomorrow" for a published or paused
/// listing whose period ends within 14 days; null otherwise.
String? expiryWarning(String status, ListingExpiry? e) =>
    !_running(status) || e?.state != ExpiryState.expiringSoon
    ? null
    : e!.daysLeft <= 1
    ? 'Expires tomorrow'
    : 'Expires in ${e.daysLeft} days';

/// "Expires 4 Dec 2026" for a live listing, "Expired on 4 Dec 2026" for an
/// expired one. The badge shows `status`; `expiry.state` is EXPIRED for
/// archived listings and relists in review too, which get no line.
String? expiryLine(String status, ListingExpiry? e) => switch (status) {
  _ when e == null => null,
  'PUBLISHED' || 'PAUSED' => 'Expires ${expiryDate(e)}',
  'EXPIRED' => 'Expired on ${expiryDate(e)}',
  _ => null,
};

/// The listings the signed-in person manages, with where each is in its
/// publication period. Editing is on the website.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key, this.filter});

  /// Opened on expiring or expired listings.
  final ExpiryState? filter;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late ExpiryState? _filter = widget.filter;

  /// A status filter (PAUSED, SOLD, LET, CLOSED); never with [_filter].
  String? _status;
  Future<({List<MyListing> items, int total})?>? _page;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= _load();
  }

  Future<({List<MyListing> items, int total})?> _load() =>
      AppScope.of(context).myListings.list(expiry: _filter, status: _status);

  void _reload() => setState(() {
    _page = _load();
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My listings')),
      body: AsyncView(
        future: _page!,
        onRetry: _reload,
        builder: (context, page) {
          if (page == null) {
            return const MessageView(
              key: Key('my-listings-none'),
              icon: Icons.home_work_outlined,
              title: 'No listings to manage',
              body: 'Listings are managed by agents, agencies and approved owners.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _page;
            },
            child: ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    for (final (key, label, value, status) in [
                      ('all', 'All', null, null),
                      ('soon', 'Expiring soon', ExpiryState.expiringSoon, null),
                      ('expired', 'Expired', ExpiryState.expired, null),
                      ('paused', 'Paused', null, 'PAUSED'),
                      ('sold', 'Sold', null, 'SOLD'),
                      ('let', 'Let', null, 'LET'),
                      ('closed', 'Closed', null, 'CLOSED'),
                    ])
                      ChoiceChip(
                        key: Key('my-listings-filter-$key'),
                        label: Text(label),
                        selected: _filter == value && _status == status,
                        onSelected: (_) {
                          _filter = value;
                          _status = status;
                          _reload();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: Space.x4),
                if (page.items.isEmpty)
                  Text(key: const Key('my-listings-empty'), switch ((
                    _filter,
                    _status,
                  )) {
                    (ExpiryState.expiringSoon, _) =>
                      'No listings expire in the next 14 days.',
                    (ExpiryState.expired, _) => 'No listings have expired.',
                    (_, final String s) =>
                      'No ${listingStatusLabel(s).toLowerCase()} listings.',
                    _ => 'You have no listings yet. Add one on the website.',
                  }, style: text.bodyLarge),
                for (final listing in page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: MyListingCard(
                      listing,
                      onTap: () async {
                        await context.push(Routes.myListing(listing.id));
                        if (mounted) _reload();
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

BadgeTone _statusTone(String status) => switch (status) {
  'PUBLISHED' => BadgeTone.success,
  'PENDING_REVIEW' || 'CHANGES_REQUESTED' || 'PAUSED' => BadgeTone.primary,
  'SOLD' || 'LET' => BadgeTone.success,
  _ => BadgeTone.neutral,
};

class MyListingCard extends StatelessWidget {
  const MyListingCard(this.listing, {super.key, required this.onTap});

  final MyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final e = listing.expiry;
    final warning = expiryWarning(listing.status, e);
    final expired = listing.status == 'EXPIRED';
    final status = listing.statusLabel;
    final line = expiryLine(listing.status, e);
    return BrandCard(
      key: Key('my-listing-${listing.id}'),
      onTap: onTap,
      semanticLabel: [
        listing.title,
        status,
        ?warning,
        ?line,
        listing.reference,
      ].join('. '),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(listing.title, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(status, tone: _statusTone(listing.status)),
              ],
            ),
            if (listing.city != null)
              Text(listing.city!, style: text.bodyMedium),
            if (warning != null) ...[
              const SizedBox(height: Space.x2),
              AppBadge(
                warning,
                key: Key('my-listing-warning-${listing.id}'),
                tone: BadgeTone.accent,
                icon: Icons.schedule,
              ),
            ],
            if (line != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x1),
                child: Text(
                  line,
                  key: Key('my-listing-expiry-${listing.id}'),
                  style: text.bodyMedium?.copyWith(
                    color: expired ? c.danger : null,
                  ),
                ),
              ),
            Text(listing.reference, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One listing's state: published, expiring or expired, with Relist for an
/// expired one. Changes to the listing itself are made on the website.
class MyListingScreen extends StatefulWidget {
  const MyListingScreen({super.key, required this.id});

  final String id;

  @override
  State<MyListingScreen> createState() => _MyListingScreenState();
}

class _MyListingScreenState extends State<MyListingScreen> {
  Future<ManagedListing>? _loading;
  ManagedListing? _listing;
  ApiFailure? _failure;
  bool _relisting = false;

  /// The lifecycle action being sent, if any.
  ListingAction? _acting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<ManagedListing> _load() =>
      AppScope.of(context).myListings.get(widget.id).then((l) => _listing = l);

  Future<void> _relist() async {
    setState(() {
      _relisting = true;
      _failure = null;
    });
    try {
      final listing = await AppScope.of(context).myListings.relist(widget.id);
      if (!mounted) return;
      setState(() => _listing = listing);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relist sent for review.')));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _relisting = false);
    }
  }

  Future<void> _apply(ListingAction action) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action.confirmTitle),
        content: Text(action.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('my-listing-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _acting = action;
      _failure = null;
    });
    try {
      final listing = await AppScope.of(context).myListings
          .apply(widget.id, action);
      if (!mounted) return;
      setState(() => _listing = listing);
      // A paused listing whose period ended meanwhile resumes as expired.
      final done = action == ListingAction.resume && listing.status == 'EXPIRED'
          ? 'Its period ended while it was paused. Relist it to send it for '
                'review.'
          : action.done;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: AsyncView<ManagedListing>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = _load();
        }),
        builder: (context, _) => _body(context, _listing!),
      ),
    );
  }

  Widget _body(BuildContext context, ManagedListing l) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final services = AppScope.of(context);
    final e = l.expiry;
    final expired = l.status == 'EXPIRED';
    final warning = expiryWarning(l.status, e);
    final line = expiryLine(l.status, e);
    final status = l.statusLabel;
    final busy = _relisting || _acting != null;
    final stateNote = switch (l.status) {
      'PAUSED' =>
        'Paused: hidden from search. It keeps its place in your package and '
            'its 90 days keep running.',
      'SOLD' =>
        'Marked as sold: hidden from search. The public page says Sold for '
            '30 days.',
      'LET' =>
        'Marked as let: hidden from search. The public page says Let for 30 '
            'days.',
      'CLOSED' => 'Closed: withdrawn from search.',
      _ => null,
    };
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l.title, style: text.headlineSmall),
              ),
            ),
            const SizedBox(width: Space.x2),
            AppBadge(status, tone: _statusTone(l.status)),
          ],
        ),
        Text(l.reference, style: text.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: Space.x4),
        if (stateNote != null) ...[
          _Callout(
            key: const Key('my-listing-state'),
            colour: c.infoSoft,
            text: stateNote,
          ),
          const SizedBox(height: Space.x2),
        ],
        if (l.relistInReview)
          _Callout(
            key: const Key('my-listing-relist-review'),
            colour: c.infoSoft,
            text:
                'Relist sent for review. Once approved, the listing is live '
                'for another 90 days.',
          )
        else if (e != null && expired)
          _Callout(
            key: const Key('my-listing-expired'),
            colour: c.dangerSoft,
            text:
                'This listing expired on ${expiryDate(e)} and is hidden from '
                'search. Relist it to send it for review; once approved it is '
                'live for another 90 days.',
          )
        else if (line != null) ...[
          if (warning != null) ...[
            AppBadge(
              warning,
              key: const Key('my-listing-warning'),
              tone: BadgeTone.accent,
              icon: Icons.schedule,
            ),
            const SizedBox(height: Space.x2),
          ],
          Text(
            line,
            key: const Key('my-listing-expiry'),
            style: text.bodyLarge,
          ),
          if (warning != null)
            Text(
              'When it expires it is hidden from search. You can then relist '
              'it for review.',
              style: text.bodyMedium,
            ),
        ],
        if (l.canRelist && !l.relistInReview) ...[
          const SizedBox(height: Space.x3),
          FilledButton.icon(
            key: const Key('my-listing-relist'),
            onPressed: busy ? null : _relist,
            icon: const Icon(Icons.replay),
            label: Text(_relisting ? 'Sending…' : 'Relist'),
          ),
        ],
        for (final action in l.lifecycleActions) ...[
          const SizedBox(height: Space.x3),
          if (action == ListingAction.resume)
            FilledButton.icon(
              key: Key('my-listing-action-${action.wire}'),
              onPressed: busy ? null : () => _apply(action),
              icon: const Icon(Icons.play_arrow),
              label: Text(_acting == action ? 'Sending…' : action.label),
            )
          else
            OutlinedButton.icon(
              key: Key('my-listing-action-${action.wire}'),
              onPressed: busy ? null : () => _apply(action),
              icon: Icon(switch (action) {
                ListingAction.pause => Icons.pause,
                ListingAction.close => Icons.block,
                _ => Icons.sell_outlined,
              }),
              label: Text(_acting == action ? 'Sending…' : action.label),
            ),
        ],
        if (_failure != null) ...[
          const SizedBox(height: Space.x3),
          FailureBox(_failure!),
        ],
        const SizedBox(height: Space.x5),
        if (l.public && l.slug.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('my-listing-public'),
            onPressed: () =>
                context.push(Routes.listing(l.slug, heroScope: 'my-listing')),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('View the public page'),
          ),
        const SizedBox(height: Space.x2),
        OutlinedButton.icon(
          key: const Key('my-listing-website'),
          onPressed: () => services.openLink(
            Uri.parse(
              '${AppConfig.webBaseUrl}/agent/listings/'
              '${Uri.encodeComponent(l.id)}',
            ),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Edit on the website'),
        ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({super.key, required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.x3),
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
