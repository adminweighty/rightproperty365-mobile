import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../data/account_security.dart';
import '../data/auth_repository.dart' show extractEmailToken;
import 'auth_screens.dart' show FailureBox, emailPattern;

final _when = DateFormat('d MMM y, HH:mm');

/// Account → Account Management → Password, email and devices (API 0.50.0).
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  Future<List<DeviceSession>>? _sessions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessions ??= AppScope.of(context).security.sessions();
  }

  void _reloadSessions() => setState(() {
    _sessions = AppScope.of(context).security.sessions();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password, email and devices')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          _PasswordSection(onChanged: _reloadSessions),
          const SizedBox(height: Space.x8),
          const SectionHeading('Signed-in devices'),
          const SizedBox(height: Space.x2),
          FutureBuilder<List<DeviceSession>>(
            future: _sessions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error is ApiFailure) FailureBox(error),
                    TextButton(
                      onPressed: _reloadSessions,
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(Space.x4),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _Devices(snapshot.data!, onChanged: _reloadSessions);
            },
          ),
          const SizedBox(height: Space.x8),
          const _EmailSection(),
        ],
      ),
    );
  }
}

class _PasswordSection extends StatefulWidget {
  const _PasswordSection({required this.onChanged});

  /// Other sessions were signed out.
  final VoidCallback onChanged;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  String? _apiError(String field, String label) {
    final problem = _failure?.fields[field];
    return problem == null ? null : '$label $problem';
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).security
          .changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Your other devices are signed out.'),
        ),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Change password'),
          const SizedBox(height: Space.x2),
          Text(
            'Changing your password signs out every other device. This phone '
            'stays signed in.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.x3),
          TextFormField(
            key: const Key('security-current-password'),
            controller: _current,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (value) => (value ?? '').isEmpty
                ? 'Enter your current password'
                : _apiError('current_password', 'Current password'),
          ),
          const SizedBox(height: Space.x3),
          TextFormField(
            key: const Key('security-new-password'),
            controller: _next,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least 10 characters.',
            ),
            validator: (value) => (value ?? '').length < 10
                ? 'Use at least 10 characters'
                : _apiError('new_password', 'New password'),
          ),
          if (failure != null && failure.fields.isEmpty) ...[
            const SizedBox(height: Space.x3),
            FailureBox(failure),
          ],
          const SizedBox(height: Space.x3),
          FilledButton(
            key: const Key('security-change-password'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Changing…' : 'Change password'),
          ),
        ],
      ),
    );
  }
}

class _Devices extends StatefulWidget {
  const _Devices(this.sessions, {required this.onChanged});

  final List<DeviceSession> sessions;
  final VoidCallback onChanged;

  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  String? _busy;
  ApiFailure? _failure;

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('security-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _run(String busy, Future<String?> Function() work) async {
    setState(() {
      _busy = busy;
      _failure = null;
    });
    try {
      final done = await work();
      if (!mounted) return;
      if (done != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      widget.onChanged();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _signOut(DeviceSession s) async {
    final services = AppScope.of(context);
    if (s.current) {
      if (!await _confirm(
        'Sign out on this phone?',
        'You will need to sign in again to use your account here.',
        'Sign out',
      )) {
        return;
      }
      await services.auth.signOut();
      if (mounted) context.go(Routes.account);
      return;
    }
    if (!await _confirm(
      'Sign out ${s.client}?',
      'That device will need to sign in again.',
      'Sign out',
    )) {
      return;
    }
    await _run(s.id, () async {
      await services.security.signOutSession(s.id);
      return '${s.client} is signed out.';
    });
  }

  Future<void> _signOutOthers() async {
    final services = AppScope.of(context);
    if (!await _confirm(
      'Sign out everywhere else?',
      'Every other device and browser signed in to your account will need '
          'to sign in again. This phone stays signed in.',
      'Sign out others',
    )) {
      return;
    }
    await _run('others', () async {
      final n = await services.security.signOutOthers();
      return n == 1
          ? 'Signed out 1 other device.'
          : 'Signed out $n other devices.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final others = widget.sessions.where((s) => !s.current).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in widget.sessions)
          Padding(
            key: Key('security-session-${s.id}'),
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: Container(
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(s.client, style: text.titleMedium),
                            if (s.current)
                              const AppBadge(
                                'This phone',
                                tone: BadgeTone.success,
                              ),
                          ],
                        ),
                        if (s.lastSeenAt != null)
                          Text(
                            'Last active ${_when.format(s.lastSeenAt!.toLocal())}',
                            style: text.bodyMedium,
                          ),
                        if (s.createdAt != null)
                          Text(
                            'Signed in ${_when.format(s.createdAt!.toLocal())}',
                            style: text.bodyMedium?.copyWith(color: c.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.x2),
                  OutlinedButton(
                    key: Key('security-sign-out-${s.id}'),
                    onPressed: _busy != null ? null : () => _signOut(s),
                    child: Text(
                      _busy == s.id
                          ? 'Signing out…'
                          : s.current
                          ? 'Sign out on this phone'
                          : 'Sign out',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_failure != null) ...[
          FailureBox(_failure!),
          const SizedBox(height: Space.x3),
        ],
        if (others > 0)
          FilledButton(
            key: const Key('security-sign-out-others'),
            onPressed: _busy != null ? null : _signOutOthers,
            child: Text(
              _busy == 'others' ? 'Signing out…' : 'Sign out everywhere else',
            ),
          )
        else
          Text(
            'No other device is signed in.',
            key: const Key('security-no-others'),
            style: text.bodyMedium,
          ),
      ],
    );
  }
}

class _EmailSection extends StatefulWidget {
  const _EmailSection();

  @override
  State<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends State<_EmailSection> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _sentTo;
  ApiFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _apiError(String field, String label) {
    final problem = _failure?.fields[field];
    return problem == null ? null : '$label $problem';
  }

  Future<void> _send() async {
    setState(() => _failure = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).security
          .changeEmail(newEmail: _email.text, password: _password.text);
      if (!mounted) return;
      setState(() => _sentTo = _email.text.trim());
      _password.clear();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final user = AppScope.of(context).auth.user;
    final failure = _failure;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Change email address'),
          const SizedBox(height: Space.x2),
          if (user != null) Text('Now: ${user.email}', style: text.bodyLarge),
          Text(
            'We email a link to the new address. The change is made when you '
            'open it; until then you sign in with your current address.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.x3),
          TextFormField(
            key: const Key('security-new-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'New email address'),
            validator: (value) => !emailPattern.hasMatch((value ?? '').trim())
                ? 'Enter a valid email address'
                : _apiError('new_email', 'New email address'),
          ),
          const SizedBox(height: Space.x3),
          TextFormField(
            key: const Key('security-email-password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (value) => (value ?? '').isEmpty
                ? 'Enter your current password'
                : _apiError('current_password', 'Current password'),
          ),
          if (failure != null && failure.fields.isEmpty) ...[
            const SizedBox(height: Space.x3),
            FailureBox(failure),
          ],
          if (_sentTo != null) ...[
            const SizedBox(height: Space.x3),
            Semantics(
              liveRegion: true,
              child: Text(
                'We sent a link to $_sentTo. Open it within 24 hours to '
                'finish the change.',
                key: const Key('security-email-sent'),
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: Space.x3),
          FilledButton(
            key: const Key('security-change-email'),
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'Sending…' : 'Send confirmation link'),
          ),
        ],
      ),
    );
  }
}

/// Opened by the link in the email-change confirmation
/// (`/confirm-email-change?token=`), signed in or not.
class ConfirmEmailChangeScreen extends StatefulWidget {
  const ConfirmEmailChangeScreen({super.key, this.token});

  final String? token;

  @override
  State<ConfirmEmailChangeScreen> createState() =>
      _ConfirmEmailChangeScreenState();
}

class _ConfirmEmailChangeScreenState extends State<ConfirmEmailChangeScreen> {
  final _link = TextEditingController();
  bool _working = false;
  String? _confirmed;
  ApiFailure? _failure;

  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(token));
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _confirm(String token) async {
    setState(() {
      _working = true;
      _failure = null;
    });
    final services = AppScope.of(context);
    try {
      final user = await services.security.confirmEmailChange(token);
      services.auth.userChanged(user);
      if (mounted) setState(() => _confirmed = user.email);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final Widget body;
    if (_confirmed != null) {
      body = MessageView(
        key: const Key('email-change-confirmed'),
        icon: Icons.mark_email_read_outlined,
        title: 'Email address changed',
        body: 'Your account now uses $_confirmed. Sign in with it from now on.',
        actionLabel: 'Continue',
        onAction: () => context.go(Routes.account),
      );
    } else if (_working) {
      body = Center(
        child: Semantics(
          label: 'Confirming your new email address',
          child: const CircularProgressIndicator(),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Text(
            'Opening the link from the email on this phone confirms your new '
            'address. If it opened somewhere else, paste it here.',
            style: text.bodyLarge,
          ),
          if (_failure != null) ...[
            const SizedBox(height: Space.x4),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x4),
          TextField(
            key: const Key('email-change-link'),
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Link from the email'),
          ),
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('email-change-submit'),
            onPressed: () {
              final token = extractEmailToken(_link.text);
              if (token != null) _confirm(token);
            },
            child: const Text('Confirm new address'),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm new email')),
      body: body,
    );
  }
}
