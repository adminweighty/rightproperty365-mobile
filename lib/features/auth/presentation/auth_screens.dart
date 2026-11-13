import 'package:go_router/go_router.dart';
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

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _sending = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.signIn(_email.text, _password.text);
      if (mounted) context.pop();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.x4);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x4),
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(height: 32),
                ),
                const SizedBox(height: Space.x6),
                TextFormField(
                  key: const Key('sign-in-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: (value) =>
                      emailPattern.hasMatch((value ?? '').trim())
                      ? null
                      : 'Enter a valid email address',
                ),
                gap,
                TextFormField(
                  key: const Key('sign-in-password'),
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) =>
                      (value ?? '').isEmpty ? 'Enter your password' : null,
                ),
                if (_failure != null) ...[gap, FailureBox(_failure!)],
                if (_failure?.code == 'EMAIL_NOT_VERIFIED') ...[
                  const SizedBox(height: Space.x2),
                  OutlinedButton(
                    key: const Key('sign-in-confirm-email'),
                    onPressed: () => context.push(Routes.verifyEmail()),
                    child: const Text('Confirm my email'),
                  ),
                ],
                const SizedBox(height: Space.x5),
                FilledButton(
                  key: const Key('sign-in-submit'),
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? 'Signing in…' : 'Sign in'),
                ),
                const SizedBox(height: Space.x2),
                TextButton(
                  key: const Key('sign-in-forgot'),
                  onPressed: () => context.push(Routes.forgotPassword),
                  child: const Text('Forgot your password?'),
                ),
                TextButton(
                  onPressed: () => context.pushReplacement(Routes.register),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _roles = <String>{'CONSUMER'};
  bool _consent = false;
  bool _consentMissing = false;
  bool _sending = false;
  bool _sent = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _apiError(String field, String label) {
    final problem = _failure?.fields[field];
    return problem == null ? null : '$label $problem';
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _consentMissing = !_consent);
    if (!valid || !_consent || _roles.isEmpty) return;

    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.repository.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        roles: _roles.toList(),
        consentAccepted: _consent,
        privacyVersion: AppConfig.privacyNoticeVersion,
      );
      if (mounted) setState(() => _sent = true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.x4);

    if (_sent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create an account')),
        // The API answers the same way whether or not the email is new, so
        // this must not claim an account was created.
        body: MessageView(
          icon: Icons.mark_email_unread_outlined,
          title: 'Check your email',
          body:
              'If ${_email.text.trim()} can be registered, we have sent it a link to confirm the '
              'address. Opening the link on this phone confirms it and signs you in.',
          actionLabel: 'The link did not open the app',
          onAction: () => context.pushReplacement(Routes.verifyEmail()),
        ),
      );
    }

    final rolesError = _roles.isEmpty
        ? 'Choose at least one'
        : _failure?.fields['roles'];

    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x4),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('register-name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter your full name'
                    : _apiError('name', 'Full name'),
              ),
              gap,
              TextFormField(
                key: const Key('register-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) =>
                    !emailPattern.hasMatch((value ?? '').trim())
                    ? 'Enter a valid email address'
                    : _apiError('email', 'Email address'),
              ),
              gap,
              TextFormField(
                key: const Key('register-password'),
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 10 characters.',
                ),
                validator: (value) => (value ?? '').length < 10
                    ? 'Use at least 10 characters'
                    : _apiError('password', 'Password'),
              ),
              const SizedBox(height: Space.x6),
              const SectionHeading('How will you use RightProperty365?'),
              const SizedBox(height: Space.x2),
              Text(
                'Choose all that apply. Professional roles are checked before they are switched on.',
                style: text.bodyMedium,
              ),
              for (final group in accountRoleGroups) ...[
                const SizedBox(height: Space.x4),
                Text(group.legend, style: text.titleSmall),
                for (final role in group.roles)
                  CheckboxListTile(
                    key: Key('role-${role.value}'),
                    value: _roles.contains(role.value),
                    onChanged: (selected) => setState(
                      () => selected ?? false
                          ? _roles.add(role.value)
                          : _roles.remove(role.value),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(role.label, style: text.bodyLarge),
                  ),
              ],
              if (rolesError != null)
                Text(
                  rolesError,
                  style: TextStyle(fontSize: 14, color: c.danger),
                ),
              const SizedBox(height: Space.x4),
              CheckboxListTile(
                key: const Key('register-consent'),
                value: _consent,
                onChanged: (value) => setState(() {
                  _consent = value ?? false;
                  if (_consent) _consentMissing = false;
                }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I agree to the RightProperty365 privacy notice.',
                  style: text.bodyMedium,
                ),
                subtitle: _consentMissing
                    ? Text(
                        'Tick the box to create your account',
                        style: TextStyle(fontSize: 14, color: c.danger),
                      )
                    : null,
              ),
              if (_failure != null) ...[gap, FailureBox(_failure!)],
              const SizedBox(height: Space.x5),
              FilledButton(
                key: const Key('register-submit'),
                onPressed: _sending ? null : _submit,
                child: Text(_sending ? 'Creating account…' : 'Create account'),
              ),
              const SizedBox(height: Space.x2),
              TextButton(
                onPressed: () => context.pushReplacement(Routes.signIn),
                child: const Text('I already have an account'),
              ),
            ],
          ),
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
          'With an account your enquiries use your saved name and email. '
          'You can still browse and send requests as a guest.',
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
        const SizedBox(height: Space.x6),
        const SectionHeading('Your roles'),
        const SizedBox(height: Space.x2),
        if (user.accountRoles.isEmpty &&
            user.memberships.isEmpty &&
            user.platformRoles.isEmpty)
          Text('Buyer or renter', style: text.bodyLarge),
        for (final role in user.accountRoles)
          row(
            roleLabel(role.role),
            role.pending
                ? 'Waiting to be verified. It gives no access until then.'
                : '',
            trailing: role.pending
                ? const AppBadge('Pending')
                : const AppBadge('Active', tone: BadgeTone.success),
          ),
        for (final role in user.platformRoles)
          row(roleLabel(role), 'Platform role'),
        if (user.memberships.isNotEmpty) ...[
          const SizedBox(height: Space.x6),
          const SectionHeading('Organisations'),
          const SizedBox(height: Space.x2),
          for (final membership in user.memberships)
            row(
              membership.organisationName,
              '${roleLabel(membership.role)} · ${roleLabel(membership.organisationKind)} · ${membership.marketCode}',
            ),
        ],
        const SizedBox(height: Space.x6),
        Text(
          'Roles decide what the app shows you. Every action is checked again by RightProperty365.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Space.x6),
        OutlinedButton(
          key: const Key('sign-out'),
          onPressed: () => AppScope.of(context).auth.signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
