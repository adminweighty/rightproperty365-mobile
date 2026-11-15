import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/brand.dart';
import '../data/auth_models.dart';
import 'auth_screens.dart';

/// Signing in is two steps: the email and password, then the code the API
/// emails to the account's address.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /// How long to wait before a new code may be asked for, when the API does
  /// not say (it allows one every 30 seconds).
  static const _resendWait = Duration(seconds: 30);

  final _passwordForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  bool _sending = false;
  ApiFailure? _failure;

  /// Set once the password is accepted; the screen then asks for the code.
  SignInChallenge? _challenge;
  String? _codeProblem;

  /// Seconds until a new code may be asked for; counted down by [_tick].
  int _resendWaitSeconds = 0;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [_email, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _waitBeforeResend(Duration wait) {
    _tick?.cancel();
    setState(() => _resendWaitSeconds = wait.inSeconds);
    // Counts down on the resend button once a second until it reaches zero.
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendWaitSeconds--);
      if (_resendWaitSeconds <= 0) timer.cancel();
    });
  }

  void _done() => Navigator.of(context).maybePop();

  /// Back to the email and password, keeping the email.
  void _restart({ApiFailure? because}) {
    _tick?.cancel();
    setState(() {
      _challenge = null;
      _codeProblem = null;
      _resendWaitSeconds = 0;
      _code.clear();
      _password.clear();
      _failure = because;
    });
  }

  Future<void> _submitPassword() async {
    if (!_passwordForm.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      final challenge = await AppScope.of(context).auth
          .signIn(_email.text, _password.text);
      if (!mounted) return;
      // Lets a password manager offer to save what was typed.
      TextInput.finishAutofillContext();
      if (challenge == null) return _done(); // Signed in without a code.
      setState(() {
        _challenge = challenge;
        _codeProblem = null;
        _code.clear();
      });
      _waitBeforeResend(_resendWait);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitCode() async {
    final challenge = _challenge;
    if (challenge == null || _sending) return;
    setState(() => _codeProblem = null);
    if (!_codeForm.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).auth.verifyCode(challenge.id, _code.text);
      if (mounted) _done();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'CODE_EXPIRED') {
        _restart(because: failure);
      } else if (failure.fields['code'] case final problem?) {
        setState(() {
          _codeProblem = problem;
          _code.clear();
        });
        _codeForm.currentState!.validate();
      } else {
        setState(() => _failure = failure);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resend() async {
    final challenge = _challenge;
    if (challenge == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final next = await AppScope.of(context).auth.resendCode(challenge.id);
      if (!mounted) return;
      setState(() {
        _challenge = next;
        _codeProblem = null;
        _failure = null;
        _code.clear();
      });
      _waitBeforeResend(_resendWait);
      messenger.showSnackBar(
        SnackBar(content: Text('We sent a new code to ${next.sentTo}')),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'CODE_EXPIRED') return _restart(because: failure);
      if (failure.status == 429) {
        final wait = failure.retryAfter ?? _resendWait;
        _waitBeforeResend(wait);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'You can ask for a new code in ${wait.inSeconds} seconds.',
            ),
          ),
        );
        return;
      }
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x4),
        child: challenge == null
            ? _passwordStep(context)
            : _codeStep(context, challenge),
      ),
    );
  }

  Widget _passwordStep(BuildContext context) {
    const gap = SizedBox(height: Space.x4);
    return AutofillGroup(
      child: Form(
        key: _passwordForm,
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
              validator: (value) => emailPattern.hasMatch((value ?? '').trim())
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
              onFieldSubmitted: (_) => _submitPassword(),
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
              onPressed: _sending ? null : _submitPassword,
              child: Text(_sending ? 'Checking…' : 'Continue'),
            ),
            const SizedBox(height: Space.x2),
            Text(
              'We will email you a code to finish signing in.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
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
    );
  }

  Widget _codeStep(BuildContext context, SignInChallenge challenge) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.x4);
    final waitSeconds = _resendWaitSeconds;

    return Form(
      key: _codeForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Check your email', style: text.headlineSmall),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'We sent a ${challenge.codeLength}-digit code to ${challenge.sentTo}. '
            'Enter it to finish signing in. It works for 10 minutes.',
            style: text.bodyLarge?.copyWith(color: c.muted),
          ),
          gap,
          TextFormField(
            key: const Key('sign-in-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (value) {
              if (_codeProblem != null) setState(() => _codeProblem = null);
              // Pasted or autofilled in full: no need to tap the button.
              if (value.length == challenge.codeLength) _submitCode();
            },
            onFieldSubmitted: (_) => _submitCode(),
            style: text.headlineSmall?.copyWith(letterSpacing: 6),
            decoration: const InputDecoration(labelText: 'Code'),
            validator: (value) {
              // The emailed code has code_length digits; the demo code on
              // test servers can be shorter, so 4 to 6 digits are accepted.
              // The API's message for the last attempt wins; it is shown
              // over the emptied field.
              if (_codeProblem != null) return _codeProblem;
              final digits = (value ?? '').trim();
              return digits.length < 4 ? 'Enter the code we sent you.' : null;
            },
          ),
          if (_failure != null) ...[gap, FailureBox(_failure!)],
          const SizedBox(height: Space.x5),
          FilledButton(
            key: const Key('sign-in-verify'),
            onPressed: _sending ? null : _submitCode,
            child: Text(_sending ? 'Checking…' : 'Verify and sign in'),
          ),
          const SizedBox(height: Space.x2),
          TextButton(
            key: const Key('sign-in-resend'),
            onPressed: waitSeconds > 0 || _sending ? null : _resend,
            child: Text(
              waitSeconds > 0
                  ? 'Send a new code in $waitSeconds s'
                  : 'Send a new code',
            ),
          ),
          TextButton(
            key: const Key('sign-in-restart'),
            onPressed: _sending ? null : () => _restart(),
            child: const Text('Use a different email or password'),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'No email? Check your spam folder. A new code replaces the last one.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
