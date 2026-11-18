import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../auth/data/auth_models.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../workspace/workspace.dart';
import 'contacts_repository.dart';

final _day = DateFormat('d MMM y');
final _stamp = DateFormat('d MMM y, HH:mm');

/// The contact books this person can open: each organisation they belong
/// to, and an approved direct owner's own.
List<ContactBook> contactBooks(Workspace work, User? user) => [
  for (final o in work.organisations)
    ContactBook(
      id: o.id,
      name: o.name,
      canWrite: o.role != 'STAFF',
      canExport: o.role == 'OWNER' || o.role == 'MANAGER',
    ),
  if (user != null &&
      work.organisations.isEmpty &&
      user.accountRoles.any(
        (r) =>
            r.approved && (r.role == 'LANDLORD' || r.role == 'PRIVATE_SELLER'),
      ))
    ContactBook(
      id: user.id,
      name: 'My contacts',
      canWrite: true,
      personal: true,
    ),
];

BadgeTone _stageTone(String stage) => switch (stage) {
  'CLOSED' => BadgeTone.success,
  'UNSUCCESSFUL' => BadgeTone.neutral,
  'NEW' => BadgeTone.accent,
  _ => BadgeTone.primary,
};

/// The contact book: search, stage filters with counts, contacts with a
/// reminder due, and new contacts. Import, export and merging are on the
/// website.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  final _query = TextEditingController();
  String? _stage;
  bool _dueOnly = false;
  int _page = 1;
  Future<ContactPage>? _contacts;
  final List<Contact> _shown = [];
  Timer? _typing;

  ContactsRepository get _repo => AppScope.of(context).contacts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_contacts == null && _book != null) _load();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _load({bool more = false}) {
    final book = _book;
    if (book == null) return;
    if (!more) {
      _page = 1;
      _shown.clear();
    }
    final next = _repo.list(
      book.id,
      query: _query.text,
      stage: _stage,
      dueOnly: _dueOnly,
      page: _page,
    );
    setState(() {
      _contacts = next.then((page) {
        _shown.addAll(page.items);
        return page;
      });
    });
  }

  Future<void> _open(Contact contact) async {
    await context.push(Routes.contact(_book!.id, contact.id), extra: _book);
    if (mounted) _load();
  }

  Future<void> _create() async {
    final created = await context.push<String>(
      Routes.newContact(_book!.id),
      extra: _book,
    );
    if (created != null && mounted) {
      _load();
      await context.push(Routes.contact(_book!.id, created), extra: _book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final text = Theme.of(context).textTheme;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contacts')),
        body: const MessageView(
          icon: Icons.lock_outline,
          title: 'No contact book on this account',
          body: 'Contacts open once you belong to an agency or business, or your landlord or seller role is approved.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: book.canWrite
          ? FloatingActionButton.extended(
              key: const Key('new-contact'),
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('New contact'),
            )
          : null,
      body: FutureBuilder<ContactPage>(
        future: _contacts,
        builder: (context, snapshot) {
          final page = snapshot.data;
          final loading = snapshot.connectionState != ConnectionState.done;
          final error = snapshot.error;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x4,
              Space.x4,
              Space.x10 * 2,
            ),
            children: [
              if (widget.books.length > 1) ...[
                SearchableSelectField<String>(
                  value: book.id,
                  label: 'Contact book',
                  options: [
                    for (final b in widget.books) SelectOption(b.id, b.name),
                  ],
                  onChanged: (id) {
                    _book = widget.books.firstWhere((b) => b.id == id);
                    _load();
                  },
                ),
                const SizedBox(height: Space.x3),
              ],
              TextField(
                key: const Key('contacts-search'),
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search by name, email or phone',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) {
                  _typing?.cancel();
                  _typing = Timer(const Duration(milliseconds: 400), _load);
                },
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  FilterChip(
                    key: const Key('contacts-due'),
                    label: const Text('Reminder due'),
                    selected: _dueOnly,
                    onSelected: (v) {
                      _dueOnly = v;
                      _load();
                    },
                  ),
                  for (final s in contactStages.entries)
                    FilterChip(
                      key: Key('contacts-stage-${s.key}'),
                      label: Text(
                        page?.stageCounts[s.key] == null
                            ? s.value
                            : '${s.value} (${page!.stageCounts[s.key]})',
                      ),
                      selected: _stage == s.key,
                      onSelected: (v) {
                        _stage = v ? s.key : null;
                        _load();
                      },
                    ),
                ],
              ),
              const SizedBox(height: Space.x3),
              if (error != null)
                _ListProblem(error: error, onRetry: _load)
              else if (loading && _shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Center(
                    child: Semantics(
                      label: 'Loading',
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                )
              else if (_shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x6),
                  child: Text(
                    _query.text.isEmpty && _stage == null && !_dueOnly
                        ? 'No contacts yet. Add one, or use "Add to contacts" on an enquiry.'
                        : 'No contacts match.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    page == null
                        ? ''
                        : page.total == 1
                        ? '1 contact'
                        : '${page.total} contacts',
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(height: Space.x2),
                for (final c in _shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _ContactCard(c, onTap: () => _open(c)),
                  ),
                if (page != null && _page < page.totalPages)
                  OutlinedButton(
                    key: const Key('contacts-more'),
                    onPressed: loading
                        ? null
                        : () {
                            _page++;
                            _load(more: true);
                          },
                    child: const Text('Show more'),
                  ),
              ],
              if (book.canExport) ...[
                const SizedBox(height: Space.x4),
                TextButton.icon(
                  onPressed: () => AppScope.of(context).openLink(
                    Uri.parse('${AppConfig.webBaseUrl}/agent/contacts'),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Import, export and merge on the website'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ListProblem extends StatelessWidget {
  const _ListProblem({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final none = error is ApiFailure && (error as ApiFailure).status == 404;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x6),
      child: Column(
        children: [
          Text(
            none
                ? 'This contact book is not open to your account.'
                : 'We could not load the contacts.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (!none)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard(this.contact, {required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = contact;
    final details = [
      if (c.typeLabel.isNotEmpty) c.typeLabel,
      if (c.ownerName != null) 'with ${c.ownerName}',
      if (c.lastContactAt != null)
        'last contact ${_day.format(c.lastContactAt!.toLocal())}',
    ].join(' · ');
    return BrandCard(
      key: Key('contact-${c.id}'),
      onTap: onTap,
      emphasised: c.remindersDue > 0,
      semanticLabel:
          '${c.name}. ${c.stageLabel}. $details'
          '${c.remindersDue > 0 ? '. Reminder due' : ''}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(c.name, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(c.stageLabel, tone: _stageTone(c.stage)),
              ],
            ),
            if (details.isNotEmpty) Text(details, style: text.bodyMedium),
            if (c.tags.isNotEmpty)
              Text(c.tags.map((t) => '#$t').join(' '), style: text.bodySmall),
            if (c.remindersDue > 0)
              Text(
                c.remindersDue == 1
                    ? '1 reminder due'
                    : '${c.remindersDue} reminders due',
                style: text.titleSmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// One contact: details, stage, notes, reminders, what is linked to it and
/// the history. STAFF read it only.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key, required this.book, required this.id});

  final ContactBook book;
  final String id;

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  Future<(ContactDetail, List<ContactEvent>)>? _loading;
  final _note = TextEditingController();
  ApiFailure? _failure;
  bool _busy = false;

  ContactsRepository get _repo => AppScope.of(context).contacts;

  Future<(ContactDetail, List<ContactEvent>)> _fetch() async {
    final results = await Future.wait([
      _repo.get(widget.book.id, widget.id),
      _repo.timeline(widget.book.id, widget.id),
    ]);
    return (results[0] as ContactDetail, results[1] as List<ContactEvent>);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _fetch();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _loading = _fetch();
  });

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStage(Contact contact) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _StageSheet(current: contact.stage),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _repo.moveStage(
        widget.book.id,
        widget.id,
        result.$1,
        note: result.$2,
      ),
      'Moved to ${contactStages[result.$1]!.toLowerCase()}.',
    );
  }

  Future<void> _addReminder() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: 'Remind me on',
      initialDate: now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    final what = await showDialog<String>(
      context: context,
      builder: (context) => const _ReminderTextDialog(),
    );
    if (what == null || !mounted) return;
    await _run(
      () => _repo.addReminder(
        widget.book.id,
        widget.id,
        DateTime(day.year, day.month, day.day, time.hour, time.minute),
        what,
      ),
      'Reminder added.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: AsyncView<(ContactDetail, List<ContactEvent>)>(
        future: _loading!,
        onRetry: _reload,
        builder: (context, data) => _body(context, data.$1, data.$2),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ContactDetail detail,
    List<ContactEvent> timeline,
  ) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final contact = detail.contact;
    final write = widget.book.canWrite && contact.mergedInto == null;

    Widget line(IconData icon, String value) => Padding(
      padding: const EdgeInsets.only(top: Space.x1),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: c.muted)),
          const SizedBox(width: Space.x2),
          Expanded(child: SelectableText(value, style: text.bodyLarge)),
        ],
      ),
    );

    final openReminders = [
      for (final r in detail.reminders)
        if (!r.done) r,
    ];
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(contact.name, style: text.headlineSmall),
              ),
            ),
            const SizedBox(width: Space.x2),
            AppBadge(contact.stageLabel, tone: _stageTone(contact.stage)),
          ],
        ),
        Text(
          [
            contact.typeLabel,
            if (contact.sourceLabel != null) 'from ${contact.sourceLabel}',
            if (contact.ownerName != null) 'with ${contact.ownerName}',
          ].where((s) => s.isNotEmpty).join(' · '),
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        if (contact.mergedInto != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(
              'This contact was merged into another one. Its history is kept there.',
              style: text.bodyMedium,
            ),
          ),
        for (final e in contact.emails) line(Icons.mail_outline, e),
        for (final p in contact.phones) line(Icons.phone_outlined, p),
        if (contact.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [for (final t in contact.tags) Chip(label: Text(t))],
            ),
          ),
        const SizedBox(height: Space.x2),
        Text(switch (contact.marketingGranted) {
          null => 'Marketing permission: not recorded',
          final granted =>
            'Marketing permission: ${granted ? 'given' : 'refused'}'
                '${contact.marketingAt == null ? '' : ', ${_day.format(contact.marketingAt!.toLocal())}'}'
                '${contact.marketingSource == null ? '' : ' (${contact.marketingSource})'}',
        }, style: text.bodyMedium),
        if (_failure != null) ...[
          const SizedBox(height: Space.x3),
          FailureBox(_failure!),
        ],
        if (write) ...[
          const SizedBox(height: Space.x3),
          OutlinedButton.icon(
            key: const Key('contact-stage'),
            onPressed: _busy ? null : () => _changeStage(contact),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Change the stage'),
          ),
        ],
        const SizedBox(height: Space.x5),
        const SectionHeading('Reminders'),
        const SizedBox(height: Space.x2),
        if (openReminders.isEmpty)
          Text('No open reminders.', style: text.bodyMedium),
        for (final r in openReminders)
          CheckboxListTile(
            key: Key('reminder-${r.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: false,
            onChanged: !write || _busy
                ? null
                : (_) => _run(
                    () => _repo.setReminderDone(
                      widget.book.id,
                      widget.id,
                      r.id,
                      true,
                    ),
                    'Reminder done.',
                  ),
            title: Text(r.text),
            subtitle: Text(
              '${r.overdue ? 'Overdue · ' : ''}${_stamp.format(r.dueAt.toLocal())}',
              style: r.overdue ? TextStyle(color: c.danger) : null,
            ),
          ),
        if (write)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add-reminder'),
              onPressed: _busy ? null : _addReminder,
              icon: const Icon(Icons.alarm_add),
              label: const Text('Add a reminder'),
            ),
          ),
        if (write) ...[
          const SizedBox(height: Space.x4),
          const SectionHeading('Quick note'),
          const SizedBox(height: Space.x2),
          TextField(
            key: const Key('contact-note'),
            controller: _note,
            maxLength: 5000,
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Note (seen by your team only)',
              helperText: 'Notes cannot be edited. A correction is a new note.',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('contact-add-note'),
              onPressed: _busy || _note.text.trim().isEmpty
                  ? null
                  : () async {
                      final note = _note.text;
                      await _run(
                        () => _repo.addNote(widget.book.id, widget.id, note),
                        'Note added.',
                      );
                      if (_failure == null) _note.clear();
                    },
              child: const Text('Add note'),
            ),
          ),
        ],
        if (detail.linkedItems.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          const SectionHeading('Enquiries and viewings'),
          const SizedBox(height: Space.x2),
          for (final i in detail.linkedItems)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.title.isEmpty ? i.reference : i.title),
              subtitle: Text(
                '${switch (i.kind) {
                  'APPOINTMENT' => 'Appointment',
                  'BUSINESS_ENQUIRY' => 'Business enquiry',
                  _ => 'Property enquiry',
                }} · ${i.reference} · ${_day.format(i.at.toLocal())}'
                '${i.auto ? ' · matched by email or phone' : ''}',
              ),
            ),
        ],
        if (contact.linkedListings.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          const SectionHeading('Properties'),
          const SizedBox(height: Space.x2),
          for (final l in contact.linkedListings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.title),
              subtitle: Text(l.reference),
              trailing: l.slug == null ? null : const Icon(Icons.chevron_right),
              onTap: l.slug == null
                  ? null
                  : () => context.push(
                      Routes.listing(l.slug!, heroScope: 'contact'),
                    ),
            ),
        ],
        const SizedBox(height: Space.x4),
        const SectionHeading('History'),
        const SizedBox(height: Space.x2),
        for (final e in timeline)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: text.bodyLarge),
                if (e.text != null && e.text!.isNotEmpty)
                  Text(e.text!, style: text.bodyMedium),
                Text(
                  [
                    _stamp.format(e.at.toLocal()),
                    ?e.actorName,
                    ?e.reference,
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StageSheet extends StatefulWidget {
  const _StageSheet({required this.current});

  final String current;

  @override
  State<_StageSheet> createState() => _StageSheetState();
}

class _StageSheetState extends State<_StageSheet> {
  late String _stage = widget.current;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.x4,
          0,
          Space.x4,
          Space.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Move to', style: text.titleLarge),
              RadioGroup<String>(
                groupValue: _stage,
                onChanged: (v) => setState(() => _stage = v ?? _stage),
                child: Column(
                  children: [
                    for (final s in contactStages.entries)
                      RadioListTile<String>(
                        key: Key('stage-option-${s.key}'),
                        value: s.key,
                        title: Text(s.value),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _note,
                maxLength: 5000,
                decoration: const InputDecoration(
                  labelText: 'Why (optional, kept in the history)',
                ),
              ),
              FilledButton(
                key: const Key('stage-confirm'),
                onPressed: _stage == widget.current
                    ? null
                    : () => Navigator.pop(context, (_stage, _note.text)),
                child: const Text('Move'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderTextDialog extends StatefulWidget {
  const _ReminderTextDialog();

  @override
  State<_ReminderTextDialog> createState() => _ReminderTextDialogState();
}

class _ReminderTextDialogState extends State<_ReminderTextDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('What to do'),
    content: TextField(
      key: const Key('reminder-text'),
      controller: _text,
      maxLength: 500,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'For example: call back'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      TextButton(
        key: const Key('reminder-save'),
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _text.text.trim()),
        child: const Text('Add reminder'),
      ),
    ],
  );
}

/// A new contact. A duplicate email or phone shows who already has it,
/// with "Create anyway".
class NewContactScreen extends StatefulWidget {
  const NewContactScreen({super.key, required this.book});

  final ContactBook book;

  @override
  State<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends State<NewContactScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  Future<Map<String, String>>? _types;
  String _type = 'buyer';
  bool? _marketing;
  bool _busy = false;
  bool _tried = false;
  ApiFailure? _failure;
  List<({String id, String name})> _duplicates = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _types ??= AppScope.of(context).contacts.types();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool anyway = false}) async {
    setState(() => _tried = true);
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final created = await AppScope.of(context).contacts.create(
        widget.book.id,
        ContactDraft(
          name: _name.text,
          type: _type,
          emails: [_email.text],
          phones: [_phone.text],
          note: _note.text,
          marketingGranted: _marketing,
          marketingSource: _marketing == null ? null : 'Recorded in the app',
        ),
        allowDuplicate: anyway,
      );
      if (mounted) Navigator.pop(context, created.contact.id);
    } on DuplicateContacts catch (duplicate) {
      if (mounted) setState(() => _duplicates = duplicate.duplicates);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fields = _failure?.fields ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('New contact')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          TextField(
            key: const Key('contact-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _tried && _name.text.trim().isEmpty
                  ? 'Enter the contact\'s name.'
                  : fields['name'],
            ),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('contact-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email (optional)',
              errorText: fields['emails'] ?? fields['emails[0]'],
            ),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('contact-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone (optional)',
              helperText: 'A local number is read in your market',
              errorText: fields['phones'] ?? fields['phones[0]'],
            ),
          ),
          const SizedBox(height: Space.x3),
          FutureBuilder<Map<String, String>>(
            future: _types,
            builder: (context, snapshot) {
              final types = snapshot.data ?? contactTypesFallback;
              return SearchableSelectField<String>(
                key: const Key('contact-type'),
                value: types.containsKey(_type) ? _type : types.keys.first,
                label: 'Type',
                options: [
                  for (final t in types.entries) SelectOption(t.key, t.value),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              );
            },
          ),
          const SizedBox(height: Space.x3),
          Text('Marketing permission', style: text.titleSmall),
          RadioGroup<bool?>(
            groupValue: _marketing,
            onChanged: (v) => setState(() => _marketing = v),
            child: const Column(
              children: [
                RadioListTile<bool?>(
                  value: null,
                  title: Text('Not asked'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool?>(
                  value: true,
                  title: Text('They agreed to marketing'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool?>(
                  value: false,
                  title: Text('They refused marketing'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          TextField(
            controller: _note,
            maxLength: 5000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'First note (optional)',
            ),
          ),
          if (_duplicates.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.only(top: Space.x3),
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: context.colors.warningSoft,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Already in your contacts with this email or phone:',
                      style: text.titleSmall,
                    ),
                    for (final d in _duplicates)
                      TextButton(
                        key: Key('duplicate-${d.id}'),
                        onPressed: () => context.pushReplacement(
                          Routes.contact(widget.book.id, d.id),
                          extra: widget.book,
                        ),
                        child: Text('Open ${d.name}'),
                      ),
                    TextButton(
                      key: const Key('create-anyway'),
                      onPressed: _busy ? null : () => _save(anyway: true),
                      child: const Text('Create a separate contact anyway'),
                    ),
                  ],
                ),
              ),
            ),
          if (_failure != null && _failure!.fields.isEmpty) ...[
            const SizedBox(height: Space.x3),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('contact-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save contact'),
          ),
        ],
      ),
    );
  }
}

/// "Add to contacts" for a property request, business enquiry or
/// appointment: creates the contact, or links it to the one that already
/// has the email or phone, then opens it.
Future<void> addToContacts(
  BuildContext context, {
  required List<ContactBook> books,
  required String itemId,
  required String kind,
}) async {
  final writable = [
    for (final b in books)
      if (b.canWrite) b,
  ];
  if (writable.isEmpty) return;
  var book = writable.first;
  if (writable.length > 1) {
    final picked = await showModalBottomSheet<ContactBook>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in writable)
              ListTile(
                title: Text(b.name),
                onTap: () => Navigator.pop(context, b),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    book = picked;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await AppScope.of(context).contacts
        .fromRequest(book.id, itemId, kind: kind);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.created
              ? 'Added ${result.detail.contact.name} to your contacts.'
              : 'Linked to ${result.detail.contact.name}, already in your contacts.',
        ),
      ),
    );
    if (context.mounted) {
      await context.push(
        Routes.contact(book.id, result.detail.contact.id),
        extra: book,
      );
    }
  } on ApiFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure.code == 'REQUEST_NOT_FOUND'
              ? 'This item is not in that contact book\'s inbox.'
              : failure.message,
        ),
      ),
    );
  }
}
