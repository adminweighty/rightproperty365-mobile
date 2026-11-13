import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/async_view.dart';
import '../data/auth_repository.dart';
import 'auth_screens.dart';

/// Where to paste the link from an email when it did not open the app.
class _LinkField extends StatelessWidget {
  const _LinkField({required this.controller, required this.fieldKey});

  final TextEditingController controller;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.url,
    autocorrect: false,
    minLines: 1,
    maxLines: 3,
    decoration: const InputDecoration(
      labelText: 'Link from the email',
      helperText:
          'Press and hold the link in the email, copy it, and paste it here.',
    ),
    validator: (value) => extractEmailToken(value ?? '') == null
        ? 'Paste the whole link from the email'
        : null,
  );
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller, required this.fieldKey});

  final TextEditingController controller;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(labelText: 'Email address'),
    validator: (value) => emailPattern.hasMatch((value ?? '').trim())
        ? null
        : 'Enter a valid email address',
  );
}

/// Confirms an email address.
///
/// Opened by the link in the confirmation email (the token is in the route)
/// or from the sign-in and registration screens, where the link is pasted.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.token});

  final String? token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _linkForm = GlobalKey<FormState>();
  final _resendForm = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _email = TextEditingController();
  bool _working = false;
  bool _confirmed = false;
  bool _resent = false;
  ApiFailure? _failure;

  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      // After the first frame, so AppScope is available.
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(token));
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _confirm(String token) async {
    setState(() {
      _working = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.confirmEmail(token);
      if (mounted) setState(() => _confirmed = true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resend() async {
    if (!_resendForm.currentState!.validate()) return;
    setState(() {
      _working = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.repository
          .resendVerification(_email.text);
      if (mounted) setState(() => _resent = true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    const gap = SizedBox(height: Space.x4);

    final Widget body;
    if (_confirmed) {
      body = MessageView(
        icon: Icons.verified_outlined,
        title: 'Email confirmed',
        body: 'Your email address is confirmed and you are signed in.',
        actionLabel: 'Continue',
        onAction: () => context.go(Routes.account),
      );
    } else if (_working && widget.token != null && _failure == null) {
      body = Center(
        child: Semantics(
          label: 'Confirming your email',
          child: const CircularProgressIndicator(),
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'We sent you an email with a link to confirm your address. Opening the link on '
              'this phone confirms it. If the link opens somewhere else, paste it here.',
              style: text.bodyLarge?.copyWith(color: c.muted),
            ),
            if (_failure != null) ...[gap, FailureBox(_failure!)],
            gap,
            Form(
              key: _linkForm,
              child: _LinkField(
                controller: _link,
                fieldKey: const Key('verify-link'),
              ),
            ),
            gap,
            FilledButton(
              key: const Key('verify-submit'),
              onPressed: _working
                  ? null
                  : () {
                      if (_linkForm.currentState!.validate()) {
                        _confirm(extractEmailToken(_link.text)!);
                      }
                    },
              child: Text(_working ? 'Confirming…' : 'Confirm email'),
            ),
            const SizedBox(height: Space.x8),
            Text('No email?', style: text.titleMedium),
            const SizedBox(height: Space.x1),
            Text(
              'Check your spam folder, or have it sent again. Links work for 24 hours.',
              style: text.bodyMedium,
            ),
            gap,
            if (_resent)
              // The API answers the same whether or not the address has an
              // unconfirmed account, so this must not say an email was sent.
              Semantics(
                liveRegion: true,
                child: Text(
                  'If ${_email.text.trim()} has an account waiting to be confirmed, a new link is on its way.',
                  style: text.bodyLarge,
                ),
              )
            else ...[
              Form(
                key: _resendForm,
                child: _EmailField(
                  controller: _email,
                  fieldKey: const Key('resend-email'),
                ),
              ),
              gap,
              OutlinedButton(
                key: const Key('resend-submit'),
                onPressed: _working ? null : _resend,
                child: const Text('Send the link again'),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your email')),
      body: body,
    );
  }
}

/// Asks for a password-reset email.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.repository
          .requestPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.x4);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset your password')),
      body: _sent
          // The API answers the same whether or not an account exists.
          ? MessageView(
              icon: Icons.mark_email_unread_outlined,
              title: 'Check your email',
              body:
                  'If ${_email.text.trim()} has an account, we have sent it a link to set a new '
                  'password. The link works for 1 hour.',
              actionLabel: 'I have the link',
              onAction: () => context.pushReplacement(Routes.resetPassword()),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x4),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter the email address of your account. We will send a link to set a new password.',
                      style: text.bodyLarge?.copyWith(
                        color: context.colors.muted,
                      ),
                    ),
                    gap,
                    _EmailField(
                      controller: _email,
                      fieldKey: const Key('forgot-email'),
                    ),
                    if (_failure != null) ...[gap, FailureBox(_failure!)],
                    const SizedBox(height: Space.x5),
                    FilledButton(
                      key: const Key('forgot-submit'),
                      onPressed: _sending ? null : _submit,
                      child: Text(_sending ? 'Sending…' : 'Send reset link'),
                    ),
                    const SizedBox(height: Space.x2),
                    TextButton(
                      onPressed: () =>
                          context.pushReplacement(Routes.resetPassword()),
                      child: const Text('I already have a link'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Sets a new password with the token from the reset email.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  bool _done = false;
  ApiFailure? _failure;

  bool get _hasToken => (widget.token ?? '').isNotEmpty;

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.resetPassword(
        _hasToken ? widget.token! : extractEmailToken(_link.text)!,
        _password.text,
      );
      if (mounted) setState(() => _done = true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.x4);
    final passwordProblem = _failure?.fields['password'];
    return Scaffold(
      appBar: AppBar(title: const Text('Set a new password')),
      body: _done
          ? MessageView(
              icon: Icons.lock_reset_outlined,
              title: 'Password changed',
              body: 'For your security every device has been signed out. Sign in with your new password.',
              actionLabel: 'Sign in',
              onAction: () => context.pushReplacement(Routes.signIn),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x4),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_hasToken) ...[
                      _LinkField(
                        controller: _link,
                        fieldKey: const Key('reset-link'),
                      ),
                      gap,
                    ],
                    TextFormField(
                      key: const Key('reset-password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 10 characters.',
                      ),
                      validator: (value) => (value ?? '').length < 10
                          ? 'Use at least 10 characters'
                          : passwordProblem == null
                          ? null
                          : 'Password $passwordProblem',
                    ),
                    if (_failure != null) ...[gap, FailureBox(_failure!)],
                    const SizedBox(height: Space.x5),
                    FilledButton(
                      key: const Key('reset-submit'),
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? 'Saving…' : 'Set new password'),
                    ),
                    if (_failure?.code == 'INVALID_TOKEN') ...[
                      const SizedBox(height: Space.x2),
                      TextButton(
                        onPressed: () =>
                            context.pushReplacement(Routes.forgotPassword),
                        child: const Text('Send a new reset link'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
