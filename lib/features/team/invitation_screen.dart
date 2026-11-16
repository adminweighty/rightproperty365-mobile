import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/terminology.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import 'team_repository.dart';

/// Joining a team from an invitation. The path matches the emailed link
/// (`/invitations/{token}`); without a token the link can be pasted.
class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key, this.token});

  final String? token;

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  late String? _token = widget.token;
  Future<PublicInvitation>? _invitation;
  final _link = TextEditingController();
  String? _linkProblem;
  bool _accepting = false;
  ApiFailure? _failure;
  String? _joined;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = _token;
    if (token != null) {
      _invitation ??= AppScope.of(context).team.invitation(token);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _open() {
    final token = invitationTokenFrom(_link.text);
    if (token == null) {
      setState(
        () => _linkProblem = 'Paste the whole link from the invitation email.',
      );
      return;
    }
    setState(() {
      _linkProblem = null;
      _token = token;
      _invitation = AppScope.of(context).team.invitation(token);
    });
  }

  Future<void> _accept() async {
    final services = AppScope.of(context);
    setState(() {
      _accepting = true;
      _failure = null;
    });
    try {
      final name = await services.team.accept(_token!);
      // The new membership and role show on the account from the next load.
      await services.auth.restore();
      if (mounted) setState(() => _joined = name);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _failure = failure.withMessage(teamMessage(failure)));
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a team')),
      body: _token == null ? _paste(context) : _view(context),
    );
  }

  Widget _paste(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Text('Open your invitation', style: text.headlineSmall),
        const SizedBox(height: Space.x2),
        Text(
          'Paste the link from the invitation email. It looks like '
          'https://rightproperty365.com/invitations/…',
          style: text.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: Space.x4),
        TextField(
          key: const Key('invitation-link'),
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Invitation link',
            errorText: _linkProblem,
          ),
          onSubmitted: (_) => _open(),
        ),
        const SizedBox(height: Space.x4),
        FilledButton(
          key: const Key('invitation-open'),
          onPressed: _open,
          child: const Text('Open invitation'),
        ),
      ],
    );
  }

  Widget _view(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return FutureBuilder<PublicInvitation>(
      future: _invitation,
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
          return MessageView(
            icon: Icons.link_off,
            title: 'This invitation cannot be opened',
            body: error is ApiFailure
                ? teamMessage(error)
                : 'Check your connection and try again.',
          );
        }
        final invitation = snapshot.data!;
        final joined = _joined;
        if (joined != null) {
          return MessageView(
            icon: Icons.check_circle_outline,
            title: 'You joined $joined',
            body:
                'You are now ${invitation.roleLabel}. Enquiries given to you appear '
                'under Enquiries Received.',
            actionLabel: 'Go to my account',
            onAction: () => context.go(Routes.account),
          );
        }
        final auth = AppScope.of(context).auth;
        return ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final user = auth.user;
            return ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                BrandCard(
                  emphasised: true,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invitation.organisationName,
                          style: text.headlineSmall,
                        ),
                        Text(
                          organisationKindLabel(invitation.organisationKind),
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: Space.x3),
                        Text(
                          '${invitation.invitedByName} invites you to join as '
                          '${invitation.roleLabel}'
                          '${invitation.jobTitle == null ? '' : ' (${invitation.jobTitle})'}.',
                          style: text.bodyLarge,
                        ),
                        const SizedBox(height: Space.x2),
                        Text(
                          'Sent to ${invitation.emailMasked}. Open until '
                          '${DateFormat('d MMM y, HH:mm').format(invitation.expiresAt.toLocal())}.',
                          style: text.bodyMedium?.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.x5),
                if (_failure != null) ...[
                  FailureBox(_failure!),
                  const SizedBox(height: Space.x4),
                ],
                if (user == null) ...[
                  Text(
                    'Sign in with the invited address to accept. New to RightProperty365? '
                    'Create a professional account with that address first.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: Space.x4),
                  FilledButton(
                    key: const Key('invitation-sign-in'),
                    onPressed: () => context.push(Routes.signIn),
                    child: const Text('Sign in to accept'),
                  ),
                  const SizedBox(height: Space.x2),
                  OutlinedButton(
                    onPressed: () => context.push(Routes.register),
                    child: const Text('Create an account'),
                  ),
                ] else ...[
                  Text('Signed in as ${user.email}.', style: text.bodyMedium),
                  const SizedBox(height: Space.x4),
                  FilledButton(
                    key: const Key('invitation-accept'),
                    onPressed: _accepting ? null : _accept,
                    child: Text(
                      _accepting
                          ? 'Joining…'
                          : 'Join ${invitation.organisationName}',
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
