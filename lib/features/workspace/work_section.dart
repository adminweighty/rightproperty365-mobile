import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/brand.dart';
import '../contacts/contacts_screens.dart';
import 'workspace.dart';

/// The signed-in person's documents, leases and teams, on the Account tab.
/// What is offered comes from the dashboard; the API checks every action.
class WorkSection extends StatefulWidget {
  const WorkSection({super.key, required this.professional});

  /// Joining a team is offered to professional accounts only.
  final bool professional;

  @override
  State<WorkSection> createState() => _WorkSectionState();
}

class _WorkSectionState extends State<WorkSection> {
  Future<Workspace>? _workspace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _workspace ??= AppScope.of(context).workspace.load();
  }

  void _reload() => setState(() {
    _workspace = AppScope.of(context).workspace.load();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Workspace>(
      future: _workspace,
      builder: (context, snapshot) {
        // Without the dashboard the documents still open; the rest waits.
        final work = snapshot.data ?? const Workspace();
        final waiting = work.documentsWaitingForYou;
        Future<void> open(String route) async {
          await context.push(route);
          if (mounted) _reload();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading('Your work'),
            const SizedBox(height: Space.x3),
            _Tile(
              key: const Key('open-documents'),
              icon: Icons.draw_outlined,
              title: 'Documents to sign',
              subtitle: waiting == 0
                  ? 'Leases and agreements sent to you'
                  : waiting == 1
                  ? '1 waiting for your signature'
                  : '$waiting waiting for your signature',
              emphasised: waiting > 0,
              onTap: () => open(Routes.documentsToSign),
            ),
            if (widget.professional)
              _Tile(
                key: const Key('open-appointments'),
                icon: Icons.event_outlined,
                title: 'Viewing Appointments',
                subtitle: 'Confirm, reschedule or cancel viewings',
                onTap: () => open(Routes.receivedAppointments),
              ),
            _Tile(
              key: const Key('open-signature'),
              icon: Icons.gesture,
              title: 'My signature',
              subtitle: 'Saved signature and initials',
              onTap: () => open(Routes.mySignature),
            ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-contacts'),
                icon: Icons.contacts_outlined,
                title: 'Contacts',
                subtitle:
                    'Buyers, tenants and owners, with notes and reminders',
                onTap: () => context.push(
                  Routes.contacts,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-applications'),
                icon: Icons.assignment_outlined,
                title: 'Applications',
                subtitle: 'Review, shortlist and decide',
                onTap: () => context.push(
                  Routes.receivedApplications,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-venue-bookings'),
                icon: Icons.meeting_room_outlined,
                title: 'Hourly bookings',
                subtitle: 'Showroom and venue requests to confirm',
                onTap: () => context.push(
                  Routes.hostedVenueBookings,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (work.organisations.any((o) => o.kind == 'SERVICE_PROVIDER'))
              _Tile(
                key: const Key('open-received-reviews'),
                icon: Icons.reviews_outlined,
                title: 'Reviews of your business',
                subtitle: 'Published reviews and your replies',
                onTap: () => context.push('${Routes.reviews}?tab=received'),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-properties'),
                icon: Icons.home_work_outlined,
                title: 'Properties',
                subtitle: 'Properties, units and tenancies',
                onTap: () => context.push(
                  Routes.properties,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-maintenance'),
                icon: Icons.build_outlined,
                title: 'Maintenance',
                subtitle: 'Repair requests, providers and costs',
                onTap: () => context.push(
                  Routes.maintenance,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-inspections'),
                icon: Icons.fact_check_outlined,
                title: 'Inspections',
                subtitle: 'Move-in, routine and move-out checklists',
                onTap: () => context.push(
                  Routes.inspections,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (contactBooks(work, AppScope.of(context).auth.user).isNotEmpty)
              _Tile(
                key: const Key('open-books'),
                icon: Icons.account_balance_wallet_outlined,
                title: 'Books',
                subtitle: 'Your own cashbook, per currency',
                onTap: () => context.push(
                  Routes.books,
                  extra: contactBooks(work, AppScope.of(context).auth.user),
                ),
              ),
            if (work.managesListings)
              _Tile(
                key: const Key('open-my-listings'),
                icon: Icons.home_work_outlined,
                title: 'My listings',
                subtitle: 'Expiry dates and relisting',
                onTap: () => open(Routes.myListings),
              ),
            if (work.statisticsOrganisations.isNotEmpty)
              _Tile(
                key: const Key('open-statistics'),
                icon: Icons.insights_outlined,
                title: 'Listing statistics',
                subtitle: 'Views, enquiries and conversion',
                onTap: () => context.push(
                  Routes.statistics,
                  extra: work.statisticsOrganisations,
                ),
              ),
            if (work.createsLeases)
              _Tile(
                key: const Key('open-leases'),
                icon: Icons.description_outlined,
                title: 'Leases',
                subtitle: 'Draft leases and send them for signing',
                onTap: () => open(Routes.leases),
              ),
            for (final organisation in work.teamsToManage)
              _Tile(
                key: Key('open-team-${organisation.id}'),
                icon: Icons.groups_outlined,
                title: 'Team: ${organisation.name}',
                subtitle: 'Members, roles and invitations',
                onTap: () => open(Routes.team(organisation.id)),
              ),
            if (widget.professional)
              _Tile(
                key: const Key('open-join-team'),
                icon: Icons.group_add_outlined,
                title: 'Join a team',
                subtitle: 'Open an invitation from your agency',
                onTap: () => open(Routes.joinTeam),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: BrandCard(
        emphasised: emphasised,
        onTap: onTap,
        semanticLabel: '$title. $subtitle',
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Row(
            children: [
              Icon(icon, color: c.primaryInk),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text(subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.subtle),
            ],
          ),
        ),
      ),
    );
  }
}
