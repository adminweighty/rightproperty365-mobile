import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../appointments/appointment_screens.dart' show askForText;
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_repository.dart' show ContactBook;
import 'application_models.dart';

const _statuses = {
  'SUBMITTED': 'Submitted',
  'UNDER_REVIEW': 'In review',
  'MORE_INFO': 'More information asked',
  'SHORTLISTED': 'Shortlisted',
  'ACCEPTED': 'Accepted',
  'REJECTED': 'Declined',
  'WITHDRAWN': 'Withdrawn',
};

/// Applications an organisation received: the Agency Principal and
/// Administrator see all, an Estate Agent those for their listings.
/// Application forms are built on the website.
class ReceivedApplicationsScreen extends StatefulWidget {
  const ReceivedApplicationsScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<ReceivedApplicationsScreen> createState() =>
      _ReceivedApplicationsScreenState();
}

class _ReceivedApplicationsScreenState
    extends State<ReceivedApplicationsScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  String? _status;
  Future<({List<Application> items, Map<String, int> counts})>? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_list == null) _load();
  }

  void _load() {
    final book = _book;
    if (book == null) return;
    final next = AppScope.of(context).agentApplications
        .list(book.id, status: _status);
    setState(() {
      _list = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    return Scaffold(
      appBar: AppBar(title: const Text('Applications')),
      body: book == null
          ? const MessageView(
              icon: Icons.lock_outline,
              title: 'No applications inbox on this account',
              body:
                  'Applications go to the agencies and owners of the listings.',
            )
          : FutureBuilder<({List<Application> items, Map<String, int> counts})>(
              future: _list,
              builder: (context, snapshot) {
                final data = snapshot.data;
                final error = snapshot.error;
                return ListView(
                  padding: const EdgeInsets.all(Space.x4),
                  children: [
                    if (widget.books.length > 1) ...[
                      SearchableSelectField<String>(
                        value: book.id,
                        label: 'Agency or business',
                        options: [
                          for (final b in widget.books)
                            SelectOption(b.id, b.name),
                        ],
                        onChanged: (id) {
                          _book = widget.books.firstWhere((b) => b.id == id);
                          _load();
                        },
                      ),
                      const SizedBox(height: Space.x3),
                    ],
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x2,
                      children: [
                        for (final s in _statuses.entries)
                          FilterChip(
                            key: Key('applications-${s.key}'),
                            label: Text(
                              data?.counts[s.key] == null
                                  ? s.value
                                  : '${s.value} (${data!.counts[s.key]})',
                            ),
                            selected: _status == s.key,
                            onSelected: (v) {
                              _status = v ? s.key : null;
                              _load();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.x3),
                    if (snapshot.connectionState != ConnectionState.done)
                      const Padding(
                        padding: EdgeInsets.all(Space.x6),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (error != null)
                      Text(
                        error is ApiFailure && error.status == 404
                            ? 'This account does not receive applications here.'
                            : 'We could not load the applications.',
                        style: text.titleMedium,
                      )
                    else if (data!.items.isEmpty)
                      Text('No applications.', style: text.bodyLarge)
                    else
                      for (final a in data.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.x3),
                          child: BrandCard(
                            key: Key('received-${a.id}'),
                            semanticLabel:
                                '${a.applicantName}. ${a.listingTitle}. ${a.statusLabel}',
                            onTap: () async {
                              await context.push(
                                Routes.receivedApplication(book.id, a.id),
                              );
                              if (mounted) _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(Space.x4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.applicantName ?? 'Applicant',
                                    style: text.titleMedium,
                                  ),
                                  Text(a.listingTitle),
                                  Text(
                                    '${a.statusLabel} · ${a.reference ?? ''}',
                                    style: text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    const SizedBox(height: Space.x4),
                    Text(
                      'Application forms are built and attached to listings on the website.',
                      style: text.bodySmall,
                    ),
                    TextButton(
                      onPressed: () => AppScope.of(context).openLink(
                        Uri.parse('${AppConfig.webBaseUrl}/agent/forms'),
                      ),
                      child: const Text('Open the form builder on the website'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// One received application: the answers in the layout of the version it
/// was submitted on, files, decisions and internal notes. Opening it is
/// recorded in the organisation's audit trail.
class ReceivedApplicationScreen extends StatefulWidget {
  const ReceivedApplicationScreen({
    super.key,
    required this.organisationId,
    required this.id,
  });

  final String organisationId;
  final String id;

  @override
  State<ReceivedApplicationScreen> createState() =>
      _ReceivedApplicationScreenState();
}

class _ReceivedApplicationScreenState extends State<ReceivedApplicationScreen> {
  Future<Application>? _loading;
  Application? _app;
  ApiFailure? _failure;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<Application> _get() =>
      AppScope.of(context).agentApplications
          .get(widget.organisationId, widget.id)
          .then((a) => _app = a);

  Future<void> _run(Future<Application> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _app = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String status) async {
    final note = await askForText(
      context,
      title: transitionLabel(status),
      label: 'Internal note (optional, never shown to the applicant)',
      action: transitionLabel(status),
    );
    if (note == null || !mounted) return;
    final repo = AppScope.of(context).agentApplications;
    await _run(
      () => repo.decide(widget.organisationId, widget.id, status, note: note),
      'Done. The applicant is told by email.',
    );
  }

  Future<void> _askForMore() async {
    final message = await askForText(
      context,
      title: 'Ask for more information',
      label: 'What you need (sent to the applicant)',
      action: 'Send',
      required: true,
    );
    if (message == null || !mounted) return;
    final repo = AppScope.of(context).agentApplications;
    await _run(
      () => repo.requestInfo(widget.organisationId, widget.id, message),
      'Sent. The applicant can add it and send the application again.',
    );
  }

  Future<void> _note() async {
    final text = await askForText(
      context,
      title: 'Add an internal note',
      label: 'Never shown to the applicant',
      action: 'Add note',
      required: true,
    );
    if (text == null || !mounted) return;
    final repo = AppScope.of(context).agentApplications;
    await _run(() async {
      await repo.addNote(widget.organisationId, widget.id, text);
      return repo.get(widget.organisationId, widget.id);
    }, 'Note added.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stamp = DateFormat('d MMM y, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Application')),
      body: FutureBuilder<Application>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final a = _app;
          if (a == null) {
            final notFound =
                snapshot.error is ApiFailure &&
                (snapshot.error as ApiFailure).status == 404;
            return MessageView(
              icon: Icons.assignment_late_outlined,
              title: notFound
                  ? 'Application not found'
                  : 'We could not load this application',
              body: notFound
                  ? 'It is not one this account can open.'
                  : 'Check your connection and try again.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Semantics(
                header: true,
                child: Text(
                  a.applicantName ?? 'Applicant',
                  style: text.headlineSmall,
                ),
              ),
              if (a.applicantEmail != null) SelectableText(a.applicantEmail!),
              Text('${a.listingTitle} · ${a.reference ?? ''}'),
              Text(a.statusLabel, style: text.titleMedium),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x3),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  for (final s in a.allowedTransitions)
                    if (s != 'MORE_INFO')
                      OutlinedButton(
                        key: Key('decide-$s'),
                        onPressed: _busy ? null : () => _decide(s),
                        child: Text(transitionLabel(s)),
                      ),
                  if (a.allowedTransitions.contains('MORE_INFO'))
                    OutlinedButton(
                      key: const Key('request-info'),
                      onPressed: _busy ? null : _askForMore,
                      child: const Text('Ask for more information'),
                    ),
                ],
              ),
              if (a.erased)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: Text(
                    'The answers and files have been deleted (retention period or account deletion).',
                    style: text.bodyMedium,
                  ),
                ),
              for (final section in a.rendered) ...[
                const SizedBox(height: Space.x4),
                SectionHeading(section.title),
                const SizedBox(height: Space.x2),
                for (final f in section.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label, style: text.titleSmall),
                        if (f.files.isNotEmpty)
                          for (final file in f.files)
                            Row(
                              children: [
                                const ExcludeSemantics(
                                  child: Icon(Icons.attach_file, size: 18),
                                ),
                                const SizedBox(width: Space.x1),
                                Expanded(
                                  child: Text(
                                    file.fileName,
                                    style: text.bodyLarge,
                                  ),
                                ),
                              ],
                            )
                        else
                          SelectableText(
                            f.display ?? 'Not answered',
                            style: text.bodyLarge,
                          ),
                      ],
                    ),
                  ),
              ],
              if (a.rendered.any(
                (s) => s.fields.any((f) => f.files.isNotEmpty),
              ))
                Text(
                  'Files open on the website, where each opening is recorded.',
                  style: text.bodySmall,
                ),
              const SizedBox(height: Space.x4),
              const SectionHeading('Internal notes'),
              const SizedBox(height: Space.x2),
              for (final n in a.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Text(
                    '${n.text}\n${n.author} · ${stamp.format(n.at.toLocal())}',
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('application-note'),
                  onPressed: _busy ? null : _note,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add an internal note'),
                ),
              ),
              const SizedBox(height: Space.x4),
              const SectionHeading('History'),
              const SizedBox(height: Space.x2),
              for (final e in a.timeline.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Text(
                    '${e.label}${e.message == null ? '' : ': ${e.message}'}\n'
                    '${stamp.format(e.at.toLocal())}${e.actorName == null ? '' : ' · ${e.actorName}'}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Apply" on a listing page, when the listing takes applications.
class ApplySection extends StatefulWidget {
  const ApplySection({super.key, required this.slug});

  final String slug;

  @override
  State<ApplySection> createState() => _ApplySectionState();
}

class _ApplySectionState extends State<ApplySection> {
  Future<({bool open, String? formName})?>? _intake;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _intake ??= AppScope.of(context).listingDetails.applications(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<({bool open, String? formName})?>(
      future: _intake,
      builder: (context, snapshot) {
        final intake = snapshot.data;
        if (intake == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading('Apply'),
              const SizedBox(height: Space.x2),
              if (intake.open) ...[
                Text(
                  'This property takes applications${intake.formName == null ? '' : ' (${intake.formName})'}. '
                  'Your answers save as you go.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: Space.x2),
                FilledButton.tonal(
                  key: const Key('apply'),
                  onPressed: () => context.push(Routes.apply(widget.slug)),
                  child: const Text('Apply for this property'),
                ),
              ] else
                Text(
                  'Applications for this property are not open at the moment.',
                  style: text.bodyLarge,
                ),
            ],
          ),
        );
      },
    );
  }
}
