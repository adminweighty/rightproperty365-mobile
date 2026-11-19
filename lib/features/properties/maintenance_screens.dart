import 'dart:async';
import 'dart:typed_data';

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
import '../appointments/appointment_screens.dart' show askForText;
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_repository.dart' show ContactBook;
import 'maintenance_repository.dart';
import 'properties_repository.dart';

final _iso = DateFormat('yyyy-MM-dd');
final _stamp = DateFormat('d MMM y, HH:mm');
String _day(String iso) => DateFormat('d MMM y').format(DateTime.parse(iso));

const _statusOrder = [
  ('NEW', 'New'),
  ('TRIAGED', 'Triaged'),
  ('ASSIGNED', 'Assigned'),
  ('IN_PROGRESS', 'In progress'),
  ('RESOLVED', 'Resolved'),
  ('CLOSED', 'Closed'),
  ('CANCELLED', 'Cancelled'),
];

String _statusLabel(String code) =>
    _statusOrder.firstWhere((s) => s.$1 == code, orElse: () => (code, code)).$2;

/// What moving to a status is called on a button.
String _moveLabel(String to) => switch (to) {
  'TRIAGED' => 'Mark triaged',
  'IN_PROGRESS' => 'Mark in progress',
  'RESOLVED' => 'Mark resolved',
  'CLOSED' => 'Close',
  'CANCELLED' => 'Cancel the request',
  _ => _statusLabel(to),
};

class MaintenanceStatusBadge extends StatelessWidget {
  const MaintenanceStatusBadge(this.request, {super.key});

  final MaintenanceRequest request;

  @override
  Widget build(BuildContext context) => AppBadge(
    request.statusLabel.isEmpty
        ? _statusLabel(request.status)
        : request.statusLabel,
    tone: switch (request.status) {
      'NEW' => BadgeTone.accent,
      'RESOLVED' || 'CLOSED' => BadgeTone.success,
      'CANCELLED' => BadgeTone.neutral,
      _ => BadgeTone.primary,
    },
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.request, {required this.onTap});

  final MaintenanceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = request;
    return BrandCard(
      key: Key('maintenance-${r.id}'),
      onTap: onTap,
      semanticLabel:
          '${r.reference}. ${r.title}. ${r.place}. ${r.statusLabel}. '
          '${r.priority.label} priority',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.title, style: text.titleMedium),
            Text(r.place, style: text.bodyMedium),
            Text(
              '${r.reference} · ${r.category.label} · ${r.priority.label}',
              style: text.bodySmall,
            ),
            if (r.providerName != null)
              Text('With ${r.providerName}', style: text.bodySmall),
            if (r.costTotals.isNotEmpty)
              Text('Costs ${r.costTotals.join(', ')}', style: text.bodySmall),
            const SizedBox(height: Space.x1),
            MaintenanceStatusBadge(r),
          ],
        ),
      ),
    );
  }
}

/// Maintenance requests of each book the person works in, by status.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  String? _status;
  String _query = '';
  Timer? _typing;
  Future<({MaintenancePage page, MaintenanceOptions options})>? _loading;

  MaintenanceRepository get _repo => AppScope.of(context).maintenance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading == null) _load();
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  void _load() {
    final book = _book;
    if (book == null) return;
    setState(() {
      _loading = () async {
        final (page, options) = await (
          _repo.list(book.id, status: _status, query: _query),
          _repo.options(book.id),
        ).wait;
        return (page: page, options: options);
      }();
    });
  }

  Future<void> _open(String id) async {
    await context.push(Routes.maintenanceRequest(_book!.id, id), extra: _book);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Maintenance')),
        body: const MessageView(
          icon: Icons.build_outlined,
          title: 'No maintenance to manage',
          body: 'Requests belong to an organisation or a landlord\'s own book.',
        ),
      );
    }
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final write = data?.options.canWrite ?? false;
        return Scaffold(
          appBar: AppBar(title: const Text('Maintenance')),
          floatingActionButton: write
              ? FloatingActionButton.extended(
                  key: const Key('new-maintenance'),
                  onPressed: () async {
                    final made = await Navigator.of(context)
                        .push<MaintenanceRequest>(
                          MaterialPageRoute(
                            builder: (_) => NewMaintenanceScreen(
                              book: book,
                              options: data!.options,
                            ),
                          ),
                        );
                    if (made != null) await _open(made.id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New request'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x4,
              Space.x4,
              Space.x10 * 2,
            ),
            children: [
              if (widget.books.length > 1) ...[
                SearchableSelectField<String>(
                  key: const Key('maintenance-book'),
                  label: 'Requests of',
                  value: book.id,
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
              if (data != null && !write) ...[
                Text(
                  'You can see these but not change them.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.x2),
              ],
              TextField(
                key: const Key('maintenance-search'),
                decoration: const InputDecoration(
                  labelText: 'Search by reference or title',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (q) {
                  _query = q;
                  _typing?.cancel();
                  _typing = Timer(const Duration(milliseconds: 400), _load);
                },
              ),
              const SizedBox(height: Space.x3),
              if (data != null)
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    ChoiceChip(
                      key: const Key('maintenance-status-all'),
                      label: const Text('All'),
                      selected: _status == null,
                      onSelected: (_) {
                        _status = null;
                        _load();
                      },
                    ),
                    for (final (code, label) in _statusOrder)
                      ChoiceChip(
                        key: Key('maintenance-status-$code'),
                        label: Text(
                          '$label (${data.page.statusCounts[code] ?? 0})',
                        ),
                        selected: _status == code,
                        onSelected: (_) {
                          _status = code;
                          _load();
                        },
                      ),
                  ],
                ),
              const SizedBox(height: Space.x4),
              if (snapshot.hasError)
                MessageView(
                  icon: Icons.cloud_off_outlined,
                  title: 'We could not load the requests',
                  body: snapshot.error is ApiFailure
                      ? (snapshot.error! as ApiFailure).message
                      : 'Check your connection and try again.',
                  actionLabel: 'Try again',
                  onAction: _load,
                )
              else if (data == null)
                const Padding(
                  padding: EdgeInsets.all(Space.x6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (data.page.items.isEmpty)
                const MessageView(
                  icon: Icons.build_outlined,
                  title: 'No requests here',
                  body: 'Requests raised by you or your tenants show here.',
                )
              else
                for (final r in data.page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _RequestCard(r, onTap: () => _open(r.id)),
                  ),
              const SizedBox(height: Space.x4),
              Text(
                'Editing a request\'s title, description, category or '
                'priority, and removing photos, are on the website.',
                style: text.bodySmall,
              ),
              Align(
                child: TextButton(
                  key: const Key('maintenance-website'),
                  onPressed: () => AppScope.of(context).openLink(
                    Uri.parse('${AppConfig.webBaseUrl}/agent/maintenance'),
                  ),
                  child: const Text('Open on the website'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Category, priority, title and description: shared by the manager's new
/// request and the tenant's report.
class _RequestFields extends StatelessWidget {
  const _RequestFields({
    required this.options,
    required this.category,
    required this.priority,
    required this.onCategory,
    required this.onPriority,
    required this.title,
    required this.description,
  });

  final MaintenanceOptions options;
  final String? category;
  final String? priority;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onPriority;
  final TextEditingController title;
  final TextEditingController description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SearchableSelectField<String>(
        key: const Key('maintenance-category'),
        label: 'What it is about',
        value: category,
        options: [
          for (final e in options.categories.entries)
            SelectOption(e.key, e.value),
        ],
        onChanged: onCategory,
        validator: (v) => v == null ? 'Choose what it is about.' : null,
      ),
      const SizedBox(height: Space.x3),
      SearchableSelectField<String>(
        key: const Key('maintenance-priority'),
        label: 'How urgent',
        value: priority,
        options: [
          for (final e in options.priorities.entries)
            SelectOption(e.key, e.value),
        ],
        onChanged: onPriority,
        validator: (v) => v == null ? 'Choose how urgent it is.' : null,
      ),
      const SizedBox(height: Space.x3),
      TextFormField(
        key: const Key('maintenance-title'),
        controller: title,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'In a few words, for example Kitchen tap leaking',
        ),
        validator: (v) =>
            (v ?? '').trim().isEmpty ? 'Say what the problem is.' : null,
      ),
      TextFormField(
        key: const Key('maintenance-description'),
        controller: description,
        maxLength: 5000,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Details (optional)'),
      ),
    ],
  );
}

class NewMaintenanceScreen extends StatefulWidget {
  const NewMaintenanceScreen({
    super.key,
    required this.book,
    required this.options,
  });

  final ContactBook book;
  final MaintenanceOptions options;

  @override
  State<NewMaintenanceScreen> createState() => _NewMaintenanceScreenState();
}

class _NewMaintenanceScreenState extends State<NewMaintenanceScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  Future<PropertyPage>? _properties;
  ManagedProperty? _property;
  String? _unit;
  String? _category;
  String? _priority = 'normal';
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _properties ??= AppScope.of(context).properties.properties(widget.book.id);
    if (!widget.options.priorities.containsKey(_priority)) _priority = null;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final made = await AppScope.of(context).maintenance.create(
        widget.book.id,
        propertyId: _property!.id,
        unitId: _unit,
        category: _category!,
        priority: _priority!,
        title: _title.text,
        description: _description.text,
      );
      if (mounted) Navigator.of(context).pop(made);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New maintenance request')),
      body: AsyncView<PropertyPage>(
        future: _properties!,
        onRetry: () => setState(() {
          _properties = AppScope.of(context).properties
              .properties(widget.book.id);
        }),
        builder: (context, page) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              SearchableSelectField<String>(
                key: const Key('maintenance-property'),
                label: 'Property',
                value: _property?.id,
                options: [
                  for (final p in page.items) SelectOption(p.id, p.name),
                ],
                onChanged: (id) => setState(() {
                  _property = page.items.firstWhere((p) => p.id == id);
                  _unit = null;
                }),
                validator: (v) => v == null ? 'Choose the property.' : null,
              ),
              if (_property != null && _property!.units.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                SearchableSelectField<String>(
                  key: Key('maintenance-unit-${_property!.id}'),
                  label: 'Unit',
                  anyLabel: 'The whole property',
                  value: _unit,
                  options: [
                    for (final u in _property!.units)
                      SelectOption(u.id, u.label),
                  ],
                  onChanged: (id) => setState(() => _unit = id),
                ),
              ],
              const SizedBox(height: Space.x3),
              _RequestFields(
                options: widget.options,
                category: _category,
                priority: _priority,
                onCategory: (v) => setState(() => _category = v),
                onPriority: (v) => setState(() => _priority = v),
                title: _title,
                description: _description,
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              FilledButton(
                key: const Key('maintenance-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Raise the request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The request's photos, read with the session.
class _Photos extends StatelessWidget {
  const _Photos(this.photos);

  final List<MaintenancePhoto> photos;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).maintenance;
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        for (final (i, p) in photos.indexed)
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              width: 96,
              height: 96,
              child: FutureBuilder<Uint8List>(
                future: repo.photo(p.url),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        semanticLabel: 'Photo ${i + 1}',
                      )
                    : ColoredBox(
                        color: context.colors.sunken,
                        child: Icon(
                          snapshot.hasError
                              ? Icons.broken_image_outlined
                              : Icons.photo_outlined,
                          semanticLabel: 'Photo ${i + 1}',
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The request's history, oldest first.
class _Timeline extends StatelessWidget {
  const _Timeline(this.items);

  final List<TimelineItem> items;

  String _what(TimelineItem t) => switch (t.type) {
    'CREATED' => 'Raised the request',
    'STATUS_CHANGED' =>
      t.toStatus == null
          ? 'Changed the status'
          : t.fromStatus == 'RESOLVED' && t.toStatus == 'IN_PROGRESS'
          ? 'Reopened it'
          : 'Moved it to ${_statusLabel(t.toStatus!)}',
    'COMMENT' => t.internal ? 'Internal note' : 'Comment',
    'ASSIGNED' =>
      'Assigned it to ${(t.details?['provider'] as Map<String, dynamic>?)?['name'] ?? 'a provider'}'
          '${t.details?['enquiry_reference'] == null ? '' : ' (enquiry ${t.details!['enquiry_reference']})'}',
    'COST_ADDED' =>
      'Recorded a cost of ${t.details?['currency'] ?? ''} ${t.details?['amount'] ?? ''}'
          '${t.details?['description'] == null ? '' : ': ${t.details!['description']}'}',
    'PHOTO_ADDED' => 'Added a photo',
    'UPDATED' =>
      'Updated ${(t.details?['fields'] as List?)?.join(', ') ?? 'the request'}',
    _ => t.type,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            key: Key('timeline-${t.id}'),
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.you ? 'You' : t.actorName}: ${_what(t)}',
                    style: text.titleSmall,
                  ),
                  if (t.text != null && t.text!.isNotEmpty)
                    Text(t.text!, style: text.bodyMedium),
                  Text(_stamp.format(t.at), style: text.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One request for the people who manage it: its details, photos, costs
/// and history, and what the role may do now.
class MaintenanceRequestScreen extends StatefulWidget {
  const MaintenanceRequestScreen({
    super.key,
    required this.book,
    required this.id,
  });

  final ContactBook book;
  final String id;

  @override
  State<MaintenanceRequestScreen> createState() =>
      _MaintenanceRequestScreenState();
}

class _MaintenanceRequestScreenState extends State<MaintenanceRequestScreen> {
  Future<({MaintenanceRequest request, MaintenanceOptions options})>? _loading;
  ApiFailure? _failure;
  String? _done;
  bool _busy = false;

  MaintenanceRepository get _repo => AppScope.of(context).maintenance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<({MaintenanceRequest request, MaintenanceOptions options})>
  _get() async {
    final (request, options) = await (
      _repo.get(widget.book.id, widget.id),
      _repo.options(widget.book.id),
    ).wait;
    return (request: request, options: options);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
      _done = null;
    });
    try {
      await action();
      if (mounted) setState(() => _done = done);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = _get();
        });
      }
    }
  }

  Future<void> _move(String to) async {
    final note = await askForText(
      context,
      title: _moveLabel(to),
      label: to == 'CANCELLED' ? 'Why it is cancelled' : 'Note (optional)',
      action: _moveLabel(to),
      required: to == 'CANCELLED',
    );
    if (note == null) return;
    if (to == 'CANCELLED' && note.trim().isEmpty) return;
    await _run(
      () => _repo.setStatus(widget.book.id, widget.id, to, note: note),
      'Now ${_statusLabel(to).toLowerCase()}.',
    );
  }

  Future<void> _comment() async {
    final result = await showDialog<({String text, bool internal})>(
      context: context,
      builder: (_) => const _CommentDialog(allowInternal: true),
    );
    if (result == null || result.text.trim().isEmpty) return;
    await _run(
      () => _repo.comment(
        widget.book.id,
        widget.id,
        result.text,
        internal: result.internal,
      ),
      result.internal ? 'Note added for your team.' : 'Comment added.',
    );
  }

  Future<void> _assign(MaintenanceRequest r) async {
    final picked = await showModalBottomSheet<MaintenanceProvider>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProviderPicker(book: widget.book.id),
    );
    if (picked == null || !mounted) return;
    final message = await askForText(
      context,
      title: 'Assign to ${picked.name}',
      label: 'Message for the provider (optional)',
      action: 'Send the enquiry',
      maxLength: 1500,
    );
    if (message == null) return;
    String? reference;
    await _run(() async {
      final done = await _repo.assign(
        widget.book.id,
        widget.id,
        picked.id,
        message: message,
      );
      reference = done.enquiryReference;
    }, 'Assigned to ${picked.name}.');
    if (reference != null && mounted && _failure == null) {
      setState(
        () => _done =
            'Assigned to ${picked.name}. Enquiry $reference was sent to them.',
      );
    }
  }

  Future<void> _cost(MaintenanceOptions options) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CostScreen(
          book: widget.book.id,
          requestId: widget.id,
          options: options,
        ),
      ),
    );
    if (added == true && mounted) {
      setState(() {
        _done =
            'Cost recorded in your books as "Recorded by you, not '
            'verified".';
        _loading = _get();
      });
    }
  }

  Future<void> _photo(bool camera) async {
    final picked = await AppScope.of(context).pickApplicationFile(
      camera: camera,
      accept: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null) return;
    await _run(
      () => _repo.addPhoto(widget.book.id, widget.id, picked),
      'Photo added.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance request')),
      body: AsyncView(
        future: _loading!,
        onRetry: () => setState(() => _loading = _get()),
        builder: (context, data) {
          final r = data.request;
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text(r.title, style: text.headlineSmall),
              Text(r.place, style: text.bodyLarge),
              Text(
                '${r.reference} · ${r.category.label} · ${r.priority.label}',
                style: text.bodySmall,
              ),
              const SizedBox(height: Space.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: MaintenanceStatusBadge(r),
              ),
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                Text(r.description, style: text.bodyLarge),
              ],
              const SizedBox(height: Space.x3),
              if (r.raisedByName != null)
                Text(
                  'Raised by ${r.raisedByName}'
                  '${r.raisedByKind == 'TENANT' ? ' (tenant)' : ''}, '
                  '${_stamp.format(r.createdAt)}',
                  style: text.bodyMedium,
                ),
              if (r.tenants.isNotEmpty)
                Text(
                  'Tenants: ${r.tenants.join(', ')}',
                  style: text.bodyMedium,
                ),
              if (r.providerName != null)
                Text(
                  'Assigned to ${r.providerName}'
                  '${r.enquiryReference == null ? '' : ' (enquiry ${r.enquiryReference})'}',
                  style: text.bodyMedium,
                ),
              if (_done != null) ...[
                const SizedBox(height: Space.x3),
                Text(_done!, style: text.bodyMedium),
              ],
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x3),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  if (r.canAssign)
                    FilledButton.icon(
                      key: const Key('maintenance-assign'),
                      onPressed: _busy ? null : () => _assign(r),
                      icon: const Icon(Icons.handyman_outlined),
                      label: Text(
                        r.providerName == null
                            ? 'Assign to a provider'
                            : 'Assign another provider',
                      ),
                    ),
                  for (final to in r.transitions)
                    OutlinedButton(
                      key: Key('maintenance-move-$to'),
                      onPressed: _busy ? null : () => _move(to),
                      child: Text(
                        to == 'IN_PROGRESS' && r.status == 'RESOLVED'
                            ? 'Reopen'
                            : _moveLabel(to),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.x4),
              SectionHeading('Photos (${r.photos.length})'),
              const SizedBox(height: Space.x2),
              if (r.photos.isEmpty)
                Text('No photos.', style: text.bodyMedium)
              else
                _Photos(r.photos),
              if (r.canAddPhoto && r.photos.length < data.options.maxPhotos)
                Wrap(
                  children: [
                    TextButton.icon(
                      key: const Key('maintenance-photo-camera'),
                      onPressed: _busy ? null : () => _photo(true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take a photo'),
                    ),
                    TextButton.icon(
                      key: const Key('maintenance-photo-file'),
                      onPressed: _busy ? null : () => _photo(false),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose a photo'),
                    ),
                  ],
                ),
              const SizedBox(height: Space.x4),
              const SectionHeading('Costs'),
              const SizedBox(height: Space.x2),
              if (r.costs.isEmpty)
                Text('No costs recorded.', style: text.bodyMedium),
              for (final c in r.costs)
                Padding(
                  key: Key('cost-${c.id}'),
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: Space.x2,
                        children: [
                          Text(c.description, style: text.titleSmall),
                          Text(
                            c.money.toString(),
                            style: text.titleSmall?.copyWith(
                              decoration: c.reversed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${c.methodLabel} · ${_day(c.incurredOn)}'
                        '${c.reversed ? ' · Reversed' : ''}',
                        style: text.bodySmall,
                      ),
                      if (c.ledgerStatusLabel != null)
                        AppBadge(c.ledgerStatusLabel!),
                    ],
                  ),
                ),
              if (r.costTotals.isNotEmpty)
                Text(
                  'Total ${r.costTotals.join(' and ')}',
                  key: const Key('maintenance-cost-totals'),
                  style: text.titleSmall,
                ),
              if (r.canAddCost)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('maintenance-add-cost'),
                    onPressed: _busy ? null : () => _cost(data.options),
                    icon: const Icon(Icons.add),
                    label: const Text('Record a cost'),
                  ),
                ),
              const SizedBox(height: Space.x4),
              const SectionHeading('History'),
              const SizedBox(height: Space.x2),
              _Timeline(r.timeline),
              if (r.canComment)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('maintenance-comment'),
                    onPressed: _busy ? null : _comment,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Add a comment'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({required this.allowInternal});

  final bool allowInternal;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  final _text = TextEditingController();
  bool _internal = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a comment'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('comment-text'),
            controller: _text,
            autofocus: true,
            maxLength: 2000,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Comment'),
          ),
          if (widget.allowInternal)
            SwitchListTile(
              key: const Key('comment-internal'),
              contentPadding: EdgeInsets.zero,
              value: _internal,
              onChanged: (v) => setState(() => _internal = v),
              title: const Text('Only for your team'),
              subtitle: const Text('The tenant never sees it'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('comment-send'),
        onPressed: () =>
            Navigator.of(context).pop((text: _text.text, internal: _internal)),
        child: const Text('Add'),
      ),
    ],
  );
}

class _ProviderPicker extends StatefulWidget {
  const _ProviderPicker({required this.book});

  final String book;

  @override
  State<_ProviderPicker> createState() => _ProviderPickerState();
}

class _ProviderPickerState extends State<_ProviderPicker> {
  Future<List<MaintenanceProvider>>? _results;
  Timer? _typing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= AppScope.of(context).maintenance.providers(widget.book);
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Choose a service provider', style: text.titleMedium),
                  Text(
                    'Verified providers in the directory. They get an '
                    'enquiry with the request reference, category, priority '
                    'and property, never the tenant\'s details.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: Space.x2),
                  TextField(
                    key: const Key('provider-search'),
                    decoration: const InputDecoration(
                      labelText: 'Search providers',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (q) {
                      _typing?.cancel();
                      _typing = Timer(const Duration(milliseconds: 300), () {
                        setState(() {
                          _results = AppScope.of(context).maintenance
                              .providers(widget.book, query: q);
                        });
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<MaintenanceProvider>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const MessageView(
                      icon: Icons.cloud_off_outlined,
                      title: 'We could not search the directory',
                      body: 'Check your connection and try again.',
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return const MessageView(
                      icon: Icons.search_off,
                      title: 'No providers match',
                      body: 'Try another name or trade.',
                    );
                  }
                  return ListView(
                    children: [
                      for (final p in items)
                        ListTile(
                          key: Key('pick-provider-${p.id}'),
                          title: Text(p.name),
                          subtitle: Text([?p.trade, ?p.city].join(' · ')),
                          trailing: p.verified
                              ? const Icon(
                                  Icons.verified_outlined,
                                  semanticLabel: 'Verified',
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostScreen extends StatefulWidget {
  const _CostScreen({
    required this.book,
    required this.requestId,
    required this.options,
  });

  final String book;
  final String requestId;
  final MaintenanceOptions options;

  @override
  State<_CostScreen> createState() => _CostScreenState();
}

class _CostScreenState extends State<_CostScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  late String _currency = widget.options.currencies.containsKey('USD')
      ? 'USD'
      : (widget.options.currencies.keys.firstOrNull ?? 'USD');
  String _method = 'BANK';
  DateTime _date = DateTime.now();
  bool _saving = false;
  ApiFailure? _failure;

  Map<String, String> get _methods => widget.options.methods.isEmpty
      ? const {
          'CASH': 'Cash',
          'BANK': 'Bank',
          'MOBILE_MONEY': 'Mobile money',
          'OTHER': 'Other',
        }
      : widget.options.methods;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).maintenance.addCost(
        widget.book,
        widget.requestId,
        amount: _amount.text,
        currency: _currency,
        description: _description.text,
        method: _method,
        incurredOn: _iso.format(_date),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.options;
    return Scaffold(
      appBar: AppBar(title: const Text('Record a cost')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(
              'The cost goes into your books as an expense, "Recorded by you, '
              'not verified". A mistake is put right by reversing it there.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.x3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('cost-amount'),
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    validator: (v) => o.amountProblem(v ?? '', _currency),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  flex: 2,
                  child: SearchableSelectField<String>(
                    key: const Key('cost-currency'),
                    label: 'Currency',
                    value: _currency,
                    options: [
                      for (final c in o.currencies.keys) SelectOption(c, c),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('cost-description'),
              controller: _description,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What it was for, for example Replace tap washer',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Say what it was for.' : null,
            ),
            SearchableSelectField<String>(
              key: const Key('cost-method'),
              label: 'Paid by',
              value: _method,
              options: [
                for (final e in _methods.entries) SelectOption(e.key, e.value),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'OTHER'),
            ),
            const SizedBox(height: Space.x3),
            OutlinedButton.icon(
              key: const Key('cost-date'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Paid ${DateFormat('d MMMM y').format(_date)}'),
            ),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('cost-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Recording…' : 'Record the cost'),
            ),
          ],
        ),
      ),
    );
  }
}

/// My Tenancy, Repairs: the requests on the tenant's own tenancy, and
/// reporting a problem while the tenancy is active.
class MyMaintenanceScreen extends StatefulWidget {
  const MyMaintenanceScreen({super.key, required this.tenancy});

  final Tenancy tenancy;

  @override
  State<MyMaintenanceScreen> createState() => _MyMaintenanceScreenState();
}

class _MyMaintenanceScreenState extends State<MyMaintenanceScreen> {
  Future<List<MaintenanceRequest>>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<List<MaintenanceRequest>> _get() =>
      AppScope.of(context).maintenance.mine(widget.tenancy.id);

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MyMaintenanceRequestScreen(tenancyId: widget.tenancy.id, id: id),
      ),
    );
    if (mounted) setState(() => _loading = _get());
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.tenancy.status == 'ACTIVE';
    return Scaffold(
      appBar: AppBar(title: const Text('Repairs')),
      floatingActionButton: active
          ? FloatingActionButton.extended(
              key: const Key('report-problem'),
              onPressed: () async {
                final made = await Navigator.of(context)
                    .push<MaintenanceRequest>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReportProblemScreen(tenancy: widget.tenancy),
                      ),
                    );
                if (made != null) await _open(made.id);
              },
              icon: const Icon(Icons.add),
              label: const Text('Report a problem'),
            )
          : null,
      body: AsyncView<List<MaintenanceRequest>>(
        future: _loading!,
        onRetry: () => setState(() => _loading = _get()),
        builder: (context, items) => items.isEmpty
            ? MessageView(
                icon: Icons.build_outlined,
                title: 'No repairs requested',
                body: active
                    ? 'Report a problem and your landlord or agent is told.'
                    : 'Requests can be raised while the tenancy is active.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  Space.x4,
                  Space.x4,
                  Space.x10 * 2,
                ),
                children: [
                  for (final r in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x3),
                      child: _RequestCard(r, onTap: () => _open(r.id)),
                    ),
                ],
              ),
      ),
    );
  }
}

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key, required this.tenancy});

  final Tenancy tenancy;

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  Future<MaintenanceOptions>? _options;
  String? _category;
  String? _priority;
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _options ??= AppScope.of(context).maintenance
        .myOptions(widget.tenancy.id)
        .then((o) {
          if (o.priorities.containsKey('normal')) _priority ??= 'normal';
          return o;
        });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final made = await AppScope.of(context).maintenance.report(
        widget.tenancy.id,
        category: _category!,
        priority: _priority!,
        title: _title.text,
        description: _description.text,
      );
      if (mounted) Navigator.of(context).pop(made);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: AsyncView<MaintenanceOptions>(
        future: _options!,
        builder: (context, options) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text(widget.tenancy.place, style: text.titleMedium),
              Text(
                'For an emergency (gas, fire, flooding), call the emergency '
                'services first.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Space.x3),
              _RequestFields(
                options: options,
                category: _category,
                priority: _priority,
                onCategory: (v) => setState(() => _category = v),
                onPriority: (v) => setState(() => _priority = v),
                title: _title,
                description: _description,
              ),
              Text(
                'You can add photos once it is sent.',
                style: text.bodySmall,
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              FilledButton(
                key: const Key('report-send'),
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? 'Sending…' : 'Send to my landlord or agent',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyMaintenanceRequestScreen extends StatefulWidget {
  const MyMaintenanceRequestScreen({
    super.key,
    required this.tenancyId,
    required this.id,
  });

  final String tenancyId;
  final String id;

  @override
  State<MyMaintenanceRequestScreen> createState() =>
      _MyMaintenanceRequestScreenState();
}

class _MyMaintenanceRequestScreenState
    extends State<MyMaintenanceRequestScreen> {
  Future<MaintenanceRequest>? _loading;
  ApiFailure? _failure;
  bool _busy = false;

  MaintenanceRepository get _repo => AppScope.of(context).maintenance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _repo.myRequest(widget.tenancyId, widget.id);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = _repo.myRequest(widget.tenancyId, widget.id);
        });
      }
    }
  }

  Future<void> _comment() async {
    final result = await showDialog<({String text, bool internal})>(
      context: context,
      builder: (_) => const _CommentDialog(allowInternal: false),
    );
    if (result == null || result.text.trim().isEmpty) return;
    await _run(() => _repo.myComment(widget.tenancyId, widget.id, result.text));
  }

  Future<void> _photo(bool camera) async {
    final picked = await AppScope.of(context).pickApplicationFile(
      camera: camera,
      accept: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null) return;
    await _run(() => _repo.myPhoto(widget.tenancyId, widget.id, picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Repair request')),
      body: AsyncView<MaintenanceRequest>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = _repo.myRequest(widget.tenancyId, widget.id);
        }),
        builder: (context, r) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(r.title, style: text.headlineSmall),
            Text(r.place, style: text.bodyLarge),
            Text(
              '${r.reference} · ${r.category.label} · ${r.priority.label}',
              style: text.bodySmall,
            ),
            const SizedBox(height: Space.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: MaintenanceStatusBadge(r),
            ),
            if (r.description.isNotEmpty) ...[
              const SizedBox(height: Space.x3),
              Text(r.description, style: text.bodyLarge),
            ],
            const SizedBox(height: Space.x2),
            Text(
              r.raisedByYou
                  ? 'You raised this'
                  : 'Raised by your landlord or agent',
              style: text.bodyMedium,
            ),
            if (r.providerName != null)
              Text(
                'Being handled by ${r.providerName}',
                style: text.bodyMedium,
              ),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            SectionHeading('Photos (${r.photos.length})'),
            const SizedBox(height: Space.x2),
            if (r.photos.isEmpty)
              Text('No photos.', style: text.bodyMedium)
            else
              _Photos(r.photos),
            if (r.canAddPhoto)
              Wrap(
                children: [
                  TextButton.icon(
                    key: const Key('my-photo-camera'),
                    onPressed: _busy ? null : () => _photo(true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take a photo'),
                  ),
                  TextButton.icon(
                    key: const Key('my-photo-file'),
                    onPressed: _busy ? null : () => _photo(false),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Choose a photo'),
                  ),
                ],
              ),
            const SizedBox(height: Space.x4),
            const SectionHeading('History'),
            const SizedBox(height: Space.x2),
            _Timeline(r.timeline),
            if (r.canComment)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('my-comment'),
                  onPressed: _busy ? null : _comment,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Add a comment'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
