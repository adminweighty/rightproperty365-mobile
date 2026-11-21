import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import 'auth_screens.dart' show FailureBox;

/// Account → Settings → Account Management.
class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Account Management')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          ListTile(
            key: const Key('open-account-security'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Password, email and devices'),
            subtitle: const Text(
              'Change your password or email, and sign out other devices',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.accountSecurity),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'Your name is changed on the website for now.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.x6),
          ListTile(
            key: const Key('open-delete-account'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined, color: c.danger),
            title: Text('Delete Account', style: TextStyle(color: c.danger)),
            subtitle: const Text(
              'Permanently delete your RightProperty365 account',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.deleteAccount),
          ),
        ],
      ),
    );
  }
}

/// Deleting the account: what it does, the password again, and an explicit
/// confirmation (DELETE /v1/me).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  bool _hidden = true;
  ApiFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = AppScope.of(context);
    try {
      await services.auth.deleteAccount(_password.text);
      // Nothing about the account stays on this phone either.
      await services.activity.clearAll();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Your account is deleted'),
          content: const Text(
            'You have been signed out on every device. We sent a last email to the address '
            'the account had.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) context.go(Routes.home);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final ready = _understood && _password.text.isNotEmpty && !_busy;

    Widget point(String value) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(child: Text('•  ')),
          Expanded(child: Text(value, style: text.bodyLarge)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Delete Account')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Deleting your account cannot be undone',
              style: text.headlineSmall,
            ),
          ),
          const SizedBox(height: Space.x3),
          Text('When you delete it:', style: text.titleMedium),
          const SizedBox(height: Space.x2),
          point(
            'Your name, email address and phone number are removed, and you can never sign in to it again.',
          ),
          point('You are signed out everywhere.'),
          point(
            'You leave every agency or organisation; your open enquiries and appointments go back to it.',
          ),
          point('Listings you own yourself are withdrawn.'),
          point(
            'Your pending and active subscriptions are cancelled. No refund is recorded here.',
          ),
          point('Your saved signature and stamp are deleted.'),
          const SizedBox(height: Space.x2),
          Text(
            'Kept, as the law and the other people involved require: signed agreements and '
            'leases, the audit trail, and enquiries you sent, which stay with the people you sent '
            'them to.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.x5),
          TextField(
            key: const Key('delete-password'),
            controller: _password,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Your password',
              helperText: 'To prove it is you',
              errorText: _failure?.fields['password'],
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: Space.x2),
          CheckboxListTile(
            key: const Key('delete-understood'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            title: const Text(
              'I understand my account will be deleted for good',
            ),
          ),
          if (_failure != null && _failure!.fields.isEmpty) ...[
            const SizedBox(height: Space.x2),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('delete-account'),
            style: FilledButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: ready ? _delete : null,
            child: Text(_busy ? 'Deleting…' : 'Delete my account'),
          ),
        ],
      ),
    );
  }
}
