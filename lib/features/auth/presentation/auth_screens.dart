import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/terminology.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../../workspace/work_section.dart';
import '../data/auth_models.dart';

final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// A failure message with its support reference, announced when it appears.
class FailureBox extends StatelessWidget {
  const FailureBox(this.failure, {super.key});

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure.fields.isEmpty
                  ? failure.message
                  : 'Check the highlighted fields and try again.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.danger,
              ),
            ),
            if (failure.traceId != null)
              Text(
                'Support reference: ${failure.traceId}',
                style: TextStyle(fontSize: 12, color: c.danger),
              ),
          ],
        ),
      ),
    );
  }
}

/// Signed out: ways in. Signed in: who you are, your roles, and sign out.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final user = auth.user;
          return user == null ? const _SignedOut() : _SignedIn(user);
        },
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        const SizedBox(height: Space.x4),
        const Align(
          alignment: Alignment.centerLeft,
          child: BrandLogo(height: 32),
        ),
        const SizedBox(height: Space.x6),
        Text('Sign in to RightProperty365', style: text.headlineSmall),
        const SizedBox(height: Space.x2),
        Text(
          'For Property Seekers, Estate Agents, Real Estate Agencies, Landlords and '
          'Property Sellers. With an account your enquiries use your saved name and email. '
          'You can still browse and send enquiries as a guest.',
          style: text.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: Space.x6),
        FilledButton(
          onPressed: () => context.push(Routes.signIn),
          child: const Text('Sign in'),
        ),
        const SizedBox(height: Space.x3),
        OutlinedButton(
          onPressed: () => context.push(Routes.register),
          child: const Text('Create an account'),
        ),
        const SizedBox(height: Space.x6),
        ListTile(
          key: const Key('open-reviews'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.rate_review_outlined),
          title: const Text('Reviews'),
          subtitle: const Text('Reviews you wrote of service providers'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.reviews),
        ),
        ListTile(
          key: const Key('open-notifications'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          subtitle: const Text('Everything sent to you, read or not'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.notifications),
        ),
        ListTile(
          key: const Key('open-notification-settings'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune),
          title: const Text('Notification settings'),
          subtitle: const Text(
            'News and offers, email and push for each kind, and push on this '
            'phone',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.notificationPreferences),
        ),
        const CountVisitsSwitch(),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn(this.user);

  final User user;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    Widget row(String title, String subtitle, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                if (subtitle.isNotEmpty) Text(subtitle, style: text.bodyMedium),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Semantics(
          header: true,
          child: Text(user.name, style: text.headlineSmall),
        ),
        Text(user.email, style: text.bodyLarge?.copyWith(color: c.muted)),
        // Professionals and property owners: the enquiries they have received.
        // The API decides what, if anything, each account may see.
        if (user.memberships.isNotEmpty ||
            user.accountRoles.any((r) => !r.isSeeker)) ...[
          const SizedBox(height: Space.x5),
          BrandCard(
            key: const Key('open-inbox'),
            emphasised: true,
            onTap: () => context.push(Routes.inbox),
            semanticLabel:
                'Enquiries Received. Enquiries about your listings and profile',
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Row(
                children: [
                  Icon(Icons.inbox_outlined, color: c.primaryInk),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Enquiries Received', style: text.titleMedium),
                        Text(
                          'Enquiries about your listings and profile',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.subtle),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Space.x6),
        WorkSection(
          professional:
              user.memberships.isNotEmpty ||
              user.accountRoles.any((r) => !r.isSeeker),
        ),
        const SizedBox(height: Space.x3),
        const SectionHeading('Your roles'),
        const SizedBox(height: Space.x2),
        if (user.accountRoles.isEmpty &&
            user.memberships.isEmpty &&
            user.platformRoles.isEmpty)
          Text(Terms.propertySeeker, style: text.bodyLarge),
        for (final role in user.accountRoles)
          row(
            role.label,
            role.isSeeker
                ? Terms.propertySeeker
                : role.approved
                ? ''
                : 'This role gives no access until a Platform Administrator approves it.',
            // Seeker roles need no verification, so they carry no status.
            trailing: role.isSeeker
                ? null
                : AppBadge(
                    role.verificationLabel,
                    tone: role.approved ? BadgeTone.success : BadgeTone.neutral,
                  ),
          ),
        for (final role in user.platformRoles)
          row(roleLabel(role), 'Platform operations'),
        if (user.memberships.isNotEmpty) ...[
          const SizedBox(height: Space.x6),
          const SectionHeading('Agencies and organisations'),
          const SizedBox(height: Space.x2),
          for (final membership in user.memberships)
            row(
              membership.organisationName,
              '${membership.roleLabel} · ${membership.kindLabel} · ${membership.marketCode}',
            ),
        ],
        const SizedBox(height: Space.x6),
        Text(
          'Roles decide what the app shows you. Every action is checked again by RightProperty365.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Space.x6),
        const SectionHeading('Settings'),
        const SizedBox(height: Space.x2),
        ListTile(
          key: const Key('open-account-management'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Account Management'),
          subtitle: const Text(
            'Password, email, signed-in devices and deleting your account',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.accountManagement),
        ),
        const CountVisitsSwitch(),
        const SizedBox(height: Space.x4),
        OutlinedButton(
          key: const Key('sign-out'),
          onPressed: () => AppScope.of(context).auth.signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// Phones send no Do Not Track signal, so the app asks instead: off means
/// this phone sends no listing statistics at all.
class CountVisitsSwitch extends StatefulWidget {
  const CountVisitsSwitch({super.key});

  @override
  State<CountVisitsSwitch> createState() => _CountVisitsSwitchState();
}

class _CountVisitsSwitchState extends State<CountVisitsSwitch> {
  @override
  Widget build(BuildContext context) {
    final analytics = AppScope.of(context).analytics;
    return SwitchListTile(
      key: const Key('count-visits'),
      contentPadding: EdgeInsets.zero,
      value: !analytics.optedOut,
      onChanged: (on) async {
        await analytics.setOptedOut(!on);
        if (mounted) setState(() {});
      },
      title: const Text('Count my visits anonymously'),
      subtitle: const Text(
        'Helps advertisers see how often their properties are viewed. '
        'Nothing identifies you or this phone, and nothing is shared with other companies.',
      ),
    );
  }
}
