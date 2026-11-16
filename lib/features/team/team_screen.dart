import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox, emailPattern;
import 'team_repository.dart';

final _day = DateFormat('d MMM y');

/// An agency's team for its Agency Principal and administrators: members and
/// their roles, pending invitations, and inviting someone.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.organisationId});

  final String organisationId;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

typedef _TeamData = ({Team team, List<TeamInvitation> invitations});

class _TeamScreenState extends State<TeamScreen> {
  Future<_TeamData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_TeamData> _load() async {
    final repo = AppScope.of(context).team;
    final results = await Future.wait([
      repo.members(widget.organisationId),
      repo.invitations(widget.organisationId),
    ]);
    return (
      team: results[0] as Team,
      invitations: results[1] as List<TeamInvitation>,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _data = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Runs a team change, then reloads; a refusal is said in plain words.
  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      _say(done);
      await _reload();
    } on ApiFailure catch (failure) {
      if (mounted) _say(teamMessage(failure));
    }
  }

  Future<void> _invite(List<String> roles) async {
    final sent = await showModalBottomSheet<TeamInvitation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _InviteSheet(
        organisationId: widget.organisationId,
        roles: roles,
        repository: AppScope.of(context).team,
      ),
    );
    if (sent == null || !mounted) return;
    _say('Invitation emailed to ${sent.email}');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TeamData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final me = data?.team.members.where((m) => m.isYou).firstOrNull;
        final roles = switch (me?.role) {
          'OWNER' => const ['MANAGER', 'AGENT', 'STAFF'],
          'MANAGER' => const ['AGENT', 'STAFF'],
          _ => const <String>[],
        };
        return Scaffold(
          appBar: AppBar(title: Text(data?.team.organisationName ?? 'Team')),
          floatingActionButton: roles.isEmpty
              ? null
              : FloatingActionButton.extended(
                  key: const Key('team-invite'),
                  onPressed: () => _invite(roles),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invite'),
                ),
          body: _body(context, snapshot),
        );
      },
    );
  }

  Widget _body(BuildContext context, AsyncSnapshot<_TeamData> snapshot) {
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
      final forbidden =
          error is ApiFailure && (error.status == 403 || error.status == 404);
      return MessageView(
        icon: forbidden ? Icons.lock_outline : Icons.cloud_off_outlined,
        title: forbidden
            ? 'Only the Agency Principal and administrators manage the team'
            : 'We could not load the team',
        body: forbidden
            ? 'Ask your Agency Principal if you need to change who is on the team.'
            : 'Check your connection and try again.',
        actionLabel: forbidden ? null : 'Try again',
        onAction: forbidden ? null : _reload,
      );
    }
    final data = snapshot.data!;
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 96),
        children: [
          SectionHeading(
            data.team.members.length == 1
                ? '1 member'
                : '${data.team.members.length} members',
          ),
          const SizedBox(height: Space.x3),
          for (final member in data.team.members) ...[
            _MemberCard(
              member: member,
              onChange: (change, done) => _act(
                () =>
                    AppScope.of(context).team
                        .change(widget.organisationId, member.userId, change),
                done,
              ),
              onRemove: () => _act(
                () =>
                    AppScope.of(context).team
                        .remove(widget.organisationId, member.userId),
                '${member.name} was removed from the team',
              ),
            ),
            const SizedBox(height: Space.x3),
          ],
          const SizedBox(height: Space.x4),
          const SectionHeading('Invitations waiting'),
          const SizedBox(height: Space.x2),
          if (data.invitations.isEmpty)
            Text(
              'No invitations waiting. Invite someone with the Invite button.',
              style: text.bodyMedium,
            ),
          for (final invitation in data.invitations)
            _InvitationRow(
              invitation: invitation,
              onCancel: () => _act(
                () =>
                    AppScope.of(context).team
                        .cancelInvitation(widget.organisationId, invitation.id),
                'Invitation to ${invitation.email} cancelled',
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onChange,
    required this.onRemove,
  });

  final TeamMember member;
  final void Function(MemberChange change, String done) onChange;
  final VoidCallback onRemove;

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _changeRole(BuildContext context) async {
    final role = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: Text(
                'Role for ${member.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final role in member.allowedRoles)
              ListTile(
                title: Text(teamRoleLabel(role)),
                subtitle: Text(teamRoleHint(role)),
                trailing: role == member.role ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, role),
              ),
          ],
        ),
      ),
    );
    if (role == null || role == member.role) return;
    onChange(
      MemberChange(role: role),
      '${member.name} is now ${teamRoleLabel(role)}',
    );
  }

  Future<void> _editJobTitle(BuildContext context) async {
    final controller = TextEditingController(text: member.jobTitle ?? '');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Job title'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Job title',
            helperText:
                'For example Senior Lettings Negotiator. Leave empty to clear.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;
    onChange(MemberChange(jobTitle: title), 'Job title saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final joined = member.joinedAt;
    return BrandOutline(
      active: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.x4,
          Space.x3,
          Space.x2,
          Space.x3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.isYou ? '${member.name} (you)' : member.name,
                    style: text.titleMedium,
                  ),
                  Text(
                    [member.roleLabel, ?member.jobTitle].join(' · '),
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: Space.x2),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [
                      if (member.suspended)
                        AppBadge(
                          member.statusLabel.isEmpty
                              ? 'Suspended'
                              : member.statusLabel,
                        ),
                      if (member.canHoldLeads)
                        Text(
                          member.openLeads == 1
                              ? '1 open enquiry'
                              : '${member.openLeads} open enquiries',
                          style: text.bodyMedium?.copyWith(
                            color: c.primaryInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (joined != null) ...[
                    const SizedBox(height: Space.x1),
                    Text(
                      'Joined ${_day.format(joined.toLocal())}',
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (member.canChange)
              PopupMenuButton<String>(
                key: Key('member-menu-${member.userId}'),
                tooltip: 'Change ${member.name}',
                onSelected: (choice) async {
                  switch (choice) {
                    case 'role':
                      await _changeRole(context);
                    case 'title':
                      await _editJobTitle(context);
                    case 'suspend':
                      if (await _confirm(
                        context,
                        'Suspend ${member.name}?',
                        'They lose access to the agency straight away. Their open '
                            'enquiries and appointments go back to the agency inbox.',
                        'Suspend',
                      )) {
                        onChange(
                          const MemberChange(status: 'SUSPENDED'),
                          '${member.name} is suspended',
                        );
                      }
                    case 'reactivate':
                      onChange(
                        const MemberChange(status: 'ACTIVE'),
                        '${member.name} is active again',
                      );
                    case 'remove':
                      if (context.mounted &&
                          await _confirm(
                            context,
                            'Remove ${member.name}?',
                            'They are taken off the team and lose access. Their open '
                                'enquiries go back to the agency inbox. You can invite them again later.',
                            'Remove',
                          )) {
                        onRemove();
                      }
                  }
                },
                itemBuilder: (context) => [
                  if (member.allowedRoles.length > 1)
                    const PopupMenuItem(
                      value: 'role',
                      child: Text('Change role'),
                    ),
                  const PopupMenuItem(
                    value: 'title',
                    child: Text('Edit job title'),
                  ),
                  if (member.suspended)
                    const PopupMenuItem(
                      value: 'reactivate',
                      child: Text('Reactivate'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'suspend',
                      child: Text('Suspend'),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from team'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({required this.invitation, required this.onCancel});

  final TeamInvitation invitation;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invitation.email, style: text.titleSmall),
                Text(
                  invitation.expired
                      ? '${invitation.roleLabel} · Expired. Invite again to send a new link.'
                      : '${invitation.roleLabel} · Until ${_day.format(invitation.expiresAt.toLocal())}'
                            '${invitation.invitedBy.isEmpty ? '' : ' · From ${invitation.invitedBy}'}',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          if (invitation.canCancel)
            TextButton(
              key: Key('cancel-invitation-${invitation.id}'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({
    required this.organisationId,
    required this.roles,
    required this.repository,
  });

  final String organisationId;
  final List<String> roles;
  final TeamRepository repository;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _jobTitle = TextEditingController();
  late String _role = widget.roles.contains('AGENT')
      ? 'AGENT'
      : widget.roles.first;
  bool _sending = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _jobTitle.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      final invitation = await widget.repository.invite(
        widget.organisationId,
        email: _email.text,
        role: _role,
        jobTitle: _jobTitle.text,
      );
      if (mounted) Navigator.pop(context, invitation);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _failure = failure.withMessage(teamMessage(failure)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x4),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite someone to the team', style: text.titleLarge),
              const SizedBox(height: Space.x2),
              Text(
                'We email them a link that works for 7 days. They sign in or create an '
                'account with this address to join.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.x4),
              TextFormField(
                key: const Key('invite-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) =>
                    emailPattern.hasMatch((value ?? '').trim())
                    ? null
                    : 'Enter a valid email address',
              ),
              const SizedBox(height: Space.x4),
              Text('Role', style: text.titleSmall),
              RadioGroup<String>(
                groupValue: _role,
                onChanged: (value) => setState(() => _role = value!),
                child: Column(
                  children: [
                    for (final role in widget.roles)
                      RadioListTile<String>(
                        key: Key('invite-role-$role'),
                        value: role,
                        contentPadding: EdgeInsets.zero,
                        title: Text(teamRoleLabel(role)),
                        subtitle: Text(teamRoleHint(role)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.x2),
              TextFormField(
                controller: _jobTitle,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Job title (optional)',
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x2),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              FilledButton(
                key: const Key('invite-send'),
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send invitation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
