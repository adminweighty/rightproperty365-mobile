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
import '../applications/apply_screen.dart' show MyApplicationsView;
import '../appointments/appointment_screens.dart';
import '../saved/saved_widgets.dart';
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
          length: signedIn ? 4 : 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Activity'),
              bottom: TabBar(
                isScrollable: signedIn,
                tabs: [
                  const Tab(text: 'My Enquiries'),
                  if (signedIn) const Tab(text: 'My Viewings'),
                  if (signedIn) const Tab(text: 'My Applications'),
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
                  if (signedIn) const MyApplicationsView(),
                  const SavedTab(),
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
