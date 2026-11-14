import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/terminology.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/searchable_select.dart';
import '../data/auth_models.dart';
import 'auth_screens.dart';

/// The two kinds of account. A registration is one or the other: the API
/// refuses a mix of Property Seeker roles and any other role.
enum _Side {
  seeker('I am looking for a property', 'To buy or to rent.'),
  professional(
    'I work in property, or I own property to sell or let',
    'Estate Agents, agencies, Solicitors, Landlords, Property Sellers and other property businesses.',
  );

  const _Side(this.title, this.detail);
  final String title;
  final String detail;
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
  final _roleQuery = TextEditingController();
  final _answer = TextEditingController();

  // Starts with the roles built into the app and is replaced by the API's
  // list, so names, groups and newly added roles follow the server without an
  // app update, and a role the server has switched off is not offered.
  List<SelectableRole> _accepted = builtInRoles;
  _Side? _side;
  final _roles = <String>{};
  bool _sideMissing = false;

  // The sign-up question. Each one is valid for ten minutes and for one
  // attempt, so a new one is fetched after any refused registration and when
  // the current one expires.
  Captcha? _captcha;
  bool _captchaFailed = false;
  String? _captchaProblem;
  Timer? _captchaExpiry;

  bool _consent = false;
  bool _consentMissing = false;
  bool _sending = false;
  bool _sent = false;
  bool _started = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    AppScope.of(context).auth.repository.selectableRoles().then((accepted) {
      if (!mounted || accepted.isEmpty) return;
      setState(() {
        _accepted = accepted;
        final codes = {for (final role in accepted) role.code};
        _roles.removeWhere((code) => !codes.contains(code));
      });
    }, onError: (_) {}); // Offline: keep the built-in list.
    _loadCaptcha();
  }

  @override
  void dispose() {
    _captchaExpiry?.cancel();
    for (final c in [_name, _email, _password, _roleQuery, _answer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    _captchaExpiry?.cancel();
    setState(() {
      _captcha = null;
      _captchaFailed = false;
      _answer.clear();
    });
    try {
      final captcha = await AppScope.of(context).auth.repository.captcha();
      if (!mounted) return;
      setState(() => _captcha = captcha);
      final remaining = captcha.expiresAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _captchaExpiry = Timer(remaining, () {
          if (!mounted) return;
          _captchaProblem = 'That question has expired. Try the new question.';
          _loadCaptcha();
        });
      }
    } on ApiFailure {
      if (mounted) setState(() => _captchaFailed = true);
    }
  }

  void _choose(_Side side) {
    if (_side == side) return;
    setState(() {
      _side = side;
      _sideMissing = false;
      _roleQuery.clear();
      // Roles never carry over: a registration is one side or the other.
      _roles.clear();
      final seekers = _accepted.where((role) => role.seeker).toList();
      if (side == _Side.seeker && seekers.isNotEmpty) {
        _roles.add(seekers.first.code);
      }
    });
  }

  String? _apiError(String field, String label) {
    final problem = _failure?.fields[field];
    return problem == null ? null : '$label $problem';
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() {
      _consentMissing = !_consent;
      _sideMissing = _side == null;
    });
    final captcha = _captcha;
    if (!valid ||
        !_consent ||
        _side == null ||
        _roles.isEmpty ||
        captcha == null) {
      return;
    }

    setState(() {
      _sending = true;
      _failure = null;
      _captchaProblem = null;
    });
    try {
      await AppScope.of(context).auth.repository.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        roles: _roles.toList(),
        consentAccepted: _consent,
        privacyVersion: AppConfig.privacyNoticeVersion,
        captchaId: captcha.id,
        captchaAnswer: _answer.text,
      );
      if (mounted) setState(() => _sent = true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _captchaProblem = failure.fields['captcha'];
      });
      // The question is used up by the attempt: ask a new one.
      await _loadCaptcha();
      if (mounted) _form.currentState!.validate();
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

    final side = _side;
    final groups = side == null
        ? const <AccountRoleGroup>[]
        : signUpRoleGroups([
            for (final role in _accepted)
              if (role.seeker == (side == _Side.seeker)) role,
          ]);
    // Groups keep their heading while any of their roles match the search.
    final visibleGroups = [
      for (final group in groups)
        if (filterOptions([
              for (final role in group.roles)
                SelectOption(
                  role,
                  role.label,
                  keywords: '${role.description} ${group.legend}',
                ),
            ], _roleQuery.text)
            case final matches when matches.isNotEmpty)
          AccountRoleGroup(group.legend, [for (final m in matches) m.value]),
    ];
    final rolesError = side != null && _roles.isEmpty
        ? 'Choose at least one'
        : _failure?.fields['roles'];
    final captcha = _captcha;

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
              const SectionHeading('Which describes you?'),
              const SizedBox(height: Space.x3),
              for (final option in _Side.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x3),
                  child: Semantics(
                    inMutuallyExclusiveGroup: true,
                    checked: side == option,
                    child: BrandCard(
                      key: Key('side-${option.name}'),
                      emphasised: side == option,
                      onTap: () => _choose(option),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.x4),
                        child: Row(
                          children: [
                            Icon(
                              side == option
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: side == option ? c.primaryInk : c.muted,
                            ),
                            const SizedBox(width: Space.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(option.title, style: text.titleMedium),
                                  Text(option.detail, style: text.bodyMedium),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_sideMissing)
                Text(
                  'Choose one to continue',
                  style: TextStyle(fontSize: 14, color: c.danger),
                ),
              if (side != null) ...[
                const SizedBox(height: Space.x3),
                const SectionHeading('Your role'),
                const SizedBox(height: Space.x2),
                Text(
                  side == _Side.seeker
                      ? 'Choose one or both. An account for Property Seekers cannot also hold '
                            'professional or owner roles.'
                      : 'Choose every role that applies to you, for example Landlord and Property '
                            'Seller. Each is verified by a Platform Administrator before it is approved.',
                  style: text.bodyMedium,
                ),
                // A pick-many list filters in place instead of opening a
                // picker. Two seeker roles need no search box.
                if (side == _Side.professional) ...[
                  gap,
                  TextField(
                    key: const Key('role-search'),
                    controller: _roleQuery,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Search roles',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _roleQuery.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_roleQuery.clear),
                            ),
                    ),
                  ),
                ],
                if (visibleGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x4),
                    child: Semantics(
                      liveRegion: true,
                      child: Text('No matches', style: text.bodyLarge),
                    ),
                  ),
                for (final group in visibleGroups) ...[
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
                      title: Text(role.label, style: text.titleMedium),
                      subtitle: role.description.isEmpty
                          ? null
                          : Text(role.description, style: text.bodyMedium),
                    ),
                ],
                if (rolesError != null)
                  Text(
                    rolesError,
                    style: TextStyle(fontSize: 14, color: c.danger),
                  ),
              ],
              const SizedBox(height: Space.x6),
              const SectionHeading('One quick question'),
              const SizedBox(height: Space.x3),
              if (captcha != null)
                TextFormField(
                  key: const Key('register-captcha'),
                  controller: _answer,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: (_) {
                    if (_captchaProblem != null) {
                      setState(() => _captchaProblem = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: captcha.question,
                    helperText:
                        'Answer in digits. This keeps automated sign-ups out.',
                    suffixIcon: IconButton(
                      key: const Key('register-captcha-new'),
                      tooltip: 'Ask a different question',
                      icon: const Icon(Icons.refresh),
                      onPressed: _sending ? null : _loadCaptcha,
                    ),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? (_captchaProblem ?? 'Answer the question')
                      : _captchaProblem,
                )
              else if (_captchaFailed)
                Semantics(
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
                          'We could not load the sign-up question, so the account cannot be '
                          'created yet. Check your connection and try again.',
                          style: TextStyle(fontSize: 14, color: c.danger),
                        ),
                        const SizedBox(height: Space.x2),
                        OutlinedButton(
                          key: const Key('register-captcha-retry'),
                          onPressed: _loadCaptcha,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: Text(
                        'Loading the question…',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
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
                // Without a question the API would refuse the registration.
                onPressed: _sending || captcha == null ? null : _submit,
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
