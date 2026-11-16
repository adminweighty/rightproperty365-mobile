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
import '../team/assign_sheet.dart';
import '../workspace/workspace.dart';
import 'inbox_repository.dart';

/// Enquiries received by an Estate Agent, Agency Principal, Solicitor,
/// Landlord, Property Seller or other professional.
///
/// An Agency Principal or administrator can give a listing enquiry to a team
/// member. Replies and stage changes are not offered here yet.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  Future<List<ReceivedEnquiry>>? _enquiries;

  /// The organisations in which this person may assign enquiries.
  List<WorkOrganisation> _assigning = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enquiries == null) {
      final services = AppScope.of(context);
      _enquiries = services.inbox.received();
      // Without the dashboard the inbox still works, only without assigning.
      services.workspace.load().then((workspace) {
        if (mounted) {
          setState(() => _assigning = workspace.assigningOrganisations);
        }
      }, onError: (_) {});
    }
  }

  Future<void> _assign(ReceivedEnquiry enquiry) async {
    final done = await showAssignSheet(
      context,
      requestId: enquiry.requestId!,
      organisations: _assigning,
      current: enquiry.assignedTo,
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _reload();
    }
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).inbox.received();
    setState(() {
      _enquiries = next;
    });
    // Let the pull-to-refresh spinner run until the reload settles.
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enquiries Received')),
      body: FutureBuilder<List<ReceivedEnquiry>>(
        future: _enquiries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Semantics(
                label: 'Loading',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final error = snapshot.error;
          if (error != null) {
            final noInbox = error is ApiFailure && error.status == 403;
            final signedOut = error is ApiFailure && error.status == 401;
            return MessageView(
              icon: noInbox ? Icons.lock_outline : Icons.cloud_off_outlined,
              title: noInbox
                  ? 'No enquiries inbox on this account'
                  : signedOut
                  ? 'Sign in to see your enquiries'
                  : 'We could not load your enquiries',
              body: noInbox
                  ? 'The inbox opens once your professional role is approved and you are linked '
                        'to your agency, firm or listings.'
                  : signedOut
                  ? 'Your session has ended.'
                  : 'Check your connection and try again.',
              actionLabel: noInbox || signedOut ? null : 'Try again',
              onAction: noInbox || signedOut ? null : _reload,
            );
          }

          final enquiries = snapshot.data ?? const [];
          if (enquiries.isEmpty) {
            return MessageView(
              icon: Icons.inbox_outlined,
              title: 'No enquiries yet',
              body: 'Enquiries about your listings and your directory profile will appear here.',
              actionLabel: 'Refresh',
              onAction: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(Space.x4),
              itemCount: enquiries.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: Space.x3),
              itemBuilder: (context, index) => index == 0
                  ? Text(
                      enquiries.length == 1
                          ? '1 enquiry'
                          : '${enquiries.length} enquiries',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : _EnquiryCard(
                      enquiries[index - 1],
                      onAssign:
                          _assigning.isEmpty ||
                              enquiries[index - 1].requestId == null
                          ? null
                          : () => _assign(enquiries[index - 1]),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _EnquiryCard extends StatelessWidget {
  const _EnquiryCard(this.enquiry, {this.onAssign});

  final ReceivedEnquiry enquiry;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final received = DateFormat('d MMM y, HH:mm')
        .format(enquiry.receivedAt.toLocal());
    final slug = enquiry.listingSlug;

    Widget detail(IconData icon, String value) => Padding(
      padding: const EdgeInsets.only(top: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: c.muted)),
          const SizedBox(width: Space.x2),
          Expanded(child: SelectableText(value, style: text.bodyLarge)),
        ],
      ),
    );

    return BrandOutline(
      active: false,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(enquiry.subject, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(enquiry.statusLabel, tone: BadgeTone.primary),
              ],
            ),
            Text('${enquiry.kind} · $received', style: text.bodyMedium),
            if (enquiry.requestId != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.badge_outlined,
                        size: 18,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        enquiry.assignedTo == null
                            ? 'In the agency inbox'
                            : 'Assigned to ${enquiry.assignedTo}',
                        style: text.bodyMedium,
                      ),
                    ),
                    if (onAssign != null)
                      TextButton(
                        key: Key('assign-${enquiry.reference}'),
                        onPressed: onAssign,
                        child: Text(
                          enquiry.assignedTo == null ? 'Assign' : 'Reassign',
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Space.x3),
            Text(enquiry.message, style: text.bodyLarge),
            const SizedBox(height: Space.x3),
            const Divider(),
            const SizedBox(height: Space.x2),
            Text('Reply by ${enquiry.replyBy}', style: text.titleSmall),
            detail(Icons.person_outline, enquiry.contactName),
            detail(Icons.mail_outline, enquiry.contactEmail),
            if (enquiry.contactPhone != null)
              detail(Icons.phone_outlined, enquiry.contactPhone!),
            const SizedBox(height: Space.x2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    enquiry.reference,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                ),
                if (slug != null)
                  TextButton(
                    onPressed: () =>
                        context.push(Routes.listing(slug, heroScope: 'inbox')),
                    child: const Text('View listing'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
