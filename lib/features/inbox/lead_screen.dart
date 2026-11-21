import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_screens.dart';
import '../property_requests/presentation/request_thread.dart';
import 'lead_repository.dart';

final _stamp = DateFormat('d MMM y, HH:mm');

/// Working a received request: its lead stage, the history and internal
/// notes. The customer only ever sees a status derived from the stage.
class LeadScreen extends StatefulWidget {
  const LeadScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<LeadScreen> createState() => _LeadScreenState();
}

class _LeadScreenState extends State<LeadScreen> {
  Future<Lead>? _loading;
  Lead? _lead;
  ApiFailure? _failure;
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<Lead> _load() =>
      AppScope.of(context).leads
          .get(widget.requestId)
          .then((lead) => _lead = lead);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Lead> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final lead = await action();
      if (!mounted) return;
      setState(() => _lead = lead);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enquiry')),
      body: AsyncView<Lead>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = _load();
        }),
        builder: (context, _) => _body(context, _lead!),
      ),
    );
  }

  Widget _body(BuildContext context, Lead lead) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final leads = AppScope.of(context).leads;
    final e = lead.enquiry;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(e.subject, style: text.headlineSmall),
              ),
            ),
            const SizedBox(width: Space.x2),
            AppBadge(e.statusLabel, tone: BadgeTone.primary),
          ],
        ),
        Text(
          '${e.kind} · ${e.reference}',
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        if (e.branch != null)
          Text(
            'Branch: ${e.branch}',
            key: const Key('lead-branch'),
            style: text.bodyMedium,
          ),
        const SizedBox(height: Space.x3),
        Text(e.message, style: text.bodyLarge),
        const SizedBox(height: Space.x3),
        Text('Reply by ${e.replyBy}', style: text.titleSmall),
        SelectableText(e.contactName, style: text.bodyLarge),
        SelectableText(e.contactEmail, style: text.bodyLarge),
        if (e.contactPhone != null)
          SelectableText(e.contactPhone!, style: text.bodyLarge),
        const SizedBox(height: Space.x5),
        const SectionHeading('Lead stage'),
        const SizedBox(height: Space.x2),
        Text(
          lead.allowedStages.isEmpty
              ? 'This request cannot move from here.'
              : 'Move it on as you work it. The customer sees a simpler '
                    'status and is told when it changes.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final s in lead.allowedStages)
              ActionChip(
                key: Key('stage-${s.stage}'),
                label: Text(s.label),
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => leads.moveTo(widget.requestId, s.stage),
                        'Moved to ${s.label.toLowerCase()}.',
                      ),
              ),
          ],
        ),
        if (_failure != null) ...[
          const SizedBox(height: Space.x3),
          FailureBox(_failure!),
        ],
        const SizedBox(height: Space.x5),
        const SectionHeading('Conversation with the customer'),
        const SizedBox(height: Space.x2),
        Text(
          'The customer sees these messages in their account and by email.',
          style: text.bodyMedium,
        ),
        RequestThread(
          key: const Key('lead-thread'),
          messages: lead.messages,
          emptyText:
              'No messages yet. Your first reply moves a new request '
              'to Contacted.',
          blockedText: lead.canReply
              ? null
              : 'This request is closed. Reopen it to reply.',
          sendLabel: 'Send reply',
          onSend: (body) async {
            final updated = await leads.reply(widget.requestId, body);
            if (!mounted) return;
            setState(() => _lead = updated);
            ScaffoldMessenger.of(this.context)
                .showSnackBar(const SnackBar(content: Text('Reply sent.')));
          },
        ),
        const SizedBox(height: Space.x5),
        Container(
          key: const Key('lead-private-notes'),
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            border: Border.all(color: c.lineStrong),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.lock_outline, color: c.muted),
                  ),
                  const SizedBox(width: Space.x2),
                  const Expanded(child: SectionHeading('Private notes')),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text(
                'Private notes, only your team sees these. The customer never does. '
                'Notes cannot be edited.',
                style: text.bodyMedium,
              ),
              for (final n in lead.notes)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.body, style: text.bodyLarge),
                      Text(
                        '${n.mine ? 'You' : n.author} · ${_stamp.format(n.at.toLocal())}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.x3),
              TextField(
                key: const Key('lead-note'),
                controller: _note,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Add a note'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('lead-add-note'),
                  onPressed: _busy || _note.text.trim().isEmpty
                      ? null
                      : () async {
                          await _run(
                            () => leads.addNote(widget.requestId, _note.text),
                            'Note added.',
                          );
                          if (_failure == null) _note.clear();
                        },
                  child: const Text('Add note'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x5),
        OutlinedButton.icon(
          key: const Key('lead-add-contact'),
          onPressed: _busy
              ? null
              : () async {
                  final services = AppScope.of(context);
                  final work = await services.workspace.load();
                  if (!context.mounted) return;
                  await addToContacts(
                    context,
                    books: contactBooks(work, services.auth.user),
                    itemId: widget.requestId,
                    kind: 'PROPERTY_REQUEST',
                  );
                },
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add to contacts'),
        ),
        const SizedBox(height: Space.x5),
        const SectionHeading('History'),
        const SizedBox(height: Space.x2),
        for (final t in lead.timeline)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text(
              '${t.label}${t.who == null ? '' : ' · ${t.who}'} · ${_stamp.format(t.at.toLocal())}',
              style: text.bodyLarge,
            ),
          ),
      ],
    );
  }
}
