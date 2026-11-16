import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import 'adopt_signature.dart';
import 'signing_repository.dart';
import 'signing_screen.dart';

final _day = DateFormat('d MMM y');

/// Documents in which the signed-in person is a recipient: leases and other
/// agreements to sign or approve, and the ones already finished.
class DocumentsToSignScreen extends StatefulWidget {
  const DocumentsToSignScreen({super.key});

  @override
  State<DocumentsToSignScreen> createState() => _DocumentsToSignScreenState();
}

class _DocumentsToSignScreenState extends State<DocumentsToSignScreen> {
  Future<List<SigningRequest>>? _requests;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requests ??= AppScope.of(context).signing.requests();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).signing.requests();
    setState(() {
      _requests = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents to sign')),
      body: AsyncView<List<SigningRequest>>(
        future: _requests!,
        onRetry: _reload,
        builder: (context, requests) {
          if (requests.isEmpty) {
            return MessageView(
              icon: Icons.draw_outlined,
              title: 'Nothing to sign',
              body: 'Leases and other documents sent to your email address for signing appear here.',
              actionLabel: 'Refresh',
              onAction: _reload,
            );
          }
          final waiting = [
            for (final r in requests)
              if (r.canSign) r,
          ];
          final other = [
            for (final r in requests)
              if (!r.canSign) r,
          ];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                if (waiting.isNotEmpty) ...[
                  SectionHeading(
                    waiting.length == 1
                        ? '1 waiting for you'
                        : '${waiting.length} waiting for you',
                  ),
                  const SizedBox(height: Space.x3),
                  for (final r in waiting) ...[
                    _RequestCard(r, onClosed: _reload),
                    const SizedBox(height: Space.x3),
                  ],
                  const SizedBox(height: Space.x3),
                ],
                if (other.isNotEmpty) ...[
                  const SectionHeading('Other documents'),
                  const SizedBox(height: Space.x3),
                  for (final r in other) ...[
                    _RequestCard(r, onClosed: _reload),
                    const SizedBox(height: Space.x3),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.request, {required this.onClosed});

  final SigningRequest request;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final action = request.canSign
        ? (request.role == 'APPROVER'
              ? 'Review and approve'
              : 'Review and sign')
        : 'Open';
    return BrandOutline(
      active: request.canSign,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(request.name, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(
                  request.canSign
                      ? recipientStatusLabel(request.recipientStatus)
                      : agreementStatusLabel(request.agreementStatus),
                  tone: request.canSign ? BadgeTone.primary : BadgeTone.neutral,
                ),
              ],
            ),
            Text(
              'From ${request.senderName} · ${request.reference}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.x1),
            Text(
              request.completedAt != null
                  ? 'Completed ${_day.format(request.completedAt!.toLocal())}'
                  : 'Open until ${_day.format(request.expiresAt.toLocal())}',
              style: text.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x3),
            Align(
              alignment: Alignment.centerRight,
              child: request.canSign
                  ? FilledButton(
                      key: Key('open-signing-${request.recipientId}'),
                      onPressed: () async {
                        await openSigningRequest(context, request);
                        onClosed();
                      },
                      child: Text(action),
                    )
                  : OutlinedButton(
                      key: Key('open-signing-${request.recipientId}'),
                      onPressed: () => openSigningRequest(context, request),
                      child: Text(action),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signature and initials saved to the account, offered on every
/// document until another is adopted.
class MySignatureScreen extends StatefulWidget {
  const MySignatureScreen({super.key});

  @override
  State<MySignatureScreen> createState() => _MySignatureScreenState();
}

class _MySignatureScreenState extends State<MySignatureScreen> {
  Future<SavedSignature>? _saved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saved ??= AppScope.of(context).signing.saved();
  }

  Future<void> _change(SavedSignature saved, {required bool initials}) async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showAdoptSignature(
      context,
      initials: initials,
      name: services.auth.user?.name ?? '',
      fonts: saved.fonts,
      current: initials ? saved.initials : saved.signature,
    );
    if (choice == null) return;
    try {
      final next = services.signing.save(
        signature: initials ? saved.signature : choice.value,
        initials: initials ? choice.value : saved.initials,
      );
      setState(() {
        _saved = next;
      });
      await next;
      messenger.showSnackBar(
        SnackBar(
          content: Text(initials ? 'Initials saved' : 'Signature saved'),
        ),
      );
    } on ApiFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(signingMessage(failure))));
      if (mounted) {
        setState(() {
          _saved = Future.value(saved);
        });
      }
    }
  }

  Future<void> _clear(SavedSignature saved, {required bool initials}) async {
    final next = AppScope.of(context).signing.save(
      signature: initials ? saved.signature : null,
      initials: initials ? null : saved.initials,
    );
    setState(() {
      _saved = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My signature')),
      body: AsyncView<SavedSignature>(
        future: _saved!,
        onRetry: () => setState(() {
          _saved = AppScope.of(context).signing.saved();
        }),
        builder: (context, saved) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(
              'Save a signature and initials to add them to documents with one tap. '
              'Nothing is signed until you press Click to sign on a document.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: Space.x5),
            _SavedCard(
              title: 'Signature',
              value: saved.signature,
              onChange: () => _change(saved, initials: false),
              onClear: saved.signature == null
                  ? null
                  : () => _clear(saved, initials: false),
            ),
            const SizedBox(height: Space.x4),
            _SavedCard(
              title: 'Initials',
              value: saved.initials,
              onChange: () => _change(saved, initials: true),
              onClear: saved.initials == null
                  ? null
                  : () => _clear(saved, initials: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.title,
    required this.value,
    required this.onChange,
    this.onClear,
  });

  final String title;
  final AdoptedSignature? value;
  final VoidCallback onChange;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final saved = value;
    return BrandOutline(
      active: false,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: Space.x3),
            Container(
              height: 90,
              padding: const EdgeInsets.all(Space.x2),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: c.lineStrong)),
              ),
              child: saved == null
                  ? Center(child: Text('Not saved yet', style: text.bodyMedium))
                  : SignaturePreview(saved),
            ),
            const SizedBox(height: Space.x3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onClear != null)
                  TextButton(onPressed: onClear, child: const Text('Remove')),
                const SizedBox(width: Space.x2),
                OutlinedButton(
                  key: Key('change-${title.toLowerCase()}'),
                  onPressed: onChange,
                  child: Text(saved == null ? 'Add' : 'Change'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
