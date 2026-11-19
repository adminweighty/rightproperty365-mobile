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
import '../signing/pdf_pages.dart' show PdfScreen;
import 'inspection_repository.dart';
import 'properties_repository.dart';

final _stamp = DateFormat('d MMM y, HH:mm');

const _statuses = [
  ('SCHEDULED', 'Scheduled'),
  ('IN_PROGRESS', 'In progress'),
  ('COMPLETED', 'Completed'),
  ('CANCELLED', 'Cancelled'),
];

const _findings = [
  ('OK', 'OK'),
  ('ATTENTION', 'Needs attention'),
  ('DAMAGED', 'Damaged'),
  ('NA', 'Not applicable'),
];

String _findingLabel(String? code) => code == null
    ? 'Not recorded'
    : _findings.firstWhere((f) => f.$1 == code, orElse: () => (code, code)).$2;

class InspectionStatusBadge extends StatelessWidget {
  const InspectionStatusBadge(this.inspection, {super.key});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) => AppBadge(
    inspection.statusLabel,
    tone: switch (inspection.status) {
      'COMPLETED' => BadgeTone.success,
      'IN_PROGRESS' => BadgeTone.accent,
      'CANCELLED' => BadgeTone.neutral,
      _ => BadgeTone.primary,
    },
  );
}

String _progressText(InspectionProgress p) =>
    '${p.done} of ${p.items} items recorded'
    '${p.attention + p.damaged > 0 ? ' · ${p.attention} need attention, ${p.damaged} damaged' : ''}';

class _InspectionCard extends StatelessWidget {
  const _InspectionCard(this.inspection, {required this.onTap});

  final Inspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final i = inspection;
    return BrandCard(
      key: Key('inspection-${i.id}'),
      onTap: onTap,
      semanticLabel:
          '${i.typeLabel} inspection ${i.reference}. ${i.place}. '
          '${i.statusLabel}. ${_progressText(i.progress)}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i.typeLabel} · ${i.place}', style: text.titleMedium),
            Text(
              i.completedAt == null
                  ? 'Scheduled ${_stamp.format(i.scheduledFor)}'
                  : 'Completed ${_stamp.format(i.completedAt!)}',
              style: text.bodyMedium,
            ),
            Text(
              '${i.reference}${i.inspectorName == null ? '' : ' · ${i.inspectorName}'}',
              style: text.bodySmall,
            ),
            Text(_progressText(i.progress), style: text.bodySmall),
            const SizedBox(height: Space.x1),
            InspectionStatusBadge(i),
          ],
        ),
      ),
    );
  }
}

/// Inspections of each book the person works in, by status.
class InspectionsScreen extends StatefulWidget {
  const InspectionsScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<InspectionsScreen> createState() => _InspectionsScreenState();
}

class _InspectionsScreenState extends State<InspectionsScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  String? _status;
  Future<({InspectionPage page, InspectionOptions options})>? _loading;

  InspectionRepository get _repo => AppScope.of(context).inspections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading == null) _load();
  }

  void _load() {
    final book = _book;
    if (book == null) return;
    setState(() {
      _loading = () async {
        final (page, options) = await (
          _repo.list(book.id, status: _status),
          _repo.options(book.id),
        ).wait;
        return (page: page, options: options);
      }();
    });
  }

  Future<void> _open(String id) async {
    await context.push(Routes.inspection(_book!.id, id), extra: _book);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inspections')),
        body: const MessageView(
          icon: Icons.fact_check_outlined,
          title: 'No inspections to manage',
          body:
              'Inspections belong to an organisation or a landlord\'s own '
              'book.',
        ),
      );
    }
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final write = data?.options.canWrite ?? false;
        return Scaffold(
          appBar: AppBar(title: const Text('Inspections')),
          floatingActionButton: write
              ? FloatingActionButton.extended(
                  key: const Key('new-inspection'),
                  onPressed: () async {
                    final made = await Navigator.of(context).push<Inspection>(
                      MaterialPageRoute(
                        builder: (_) => NewInspectionScreen(
                          book: book,
                          options: data!.options,
                        ),
                      ),
                    );
                    if (made != null) await _open(made.id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Schedule'),
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
                  key: const Key('inspections-book'),
                  label: 'Inspections of',
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
              if (data != null)
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    ChoiceChip(
                      key: const Key('inspections-status-all'),
                      label: const Text('All'),
                      selected: _status == null,
                      onSelected: (_) {
                        _status = null;
                        _load();
                      },
                    ),
                    for (final (code, label) in _statuses)
                      ChoiceChip(
                        key: Key('inspections-status-$code'),
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
                  title: 'We could not load the inspections',
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
                  icon: Icons.fact_check_outlined,
                  title: 'No inspections here',
                  body: 'Schedule a move-in, routine or move-out inspection.',
                )
              else
                for (final i in data.page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _InspectionCard(i, onTap: () => _open(i.id)),
                  ),
              const SizedBox(height: Space.x4),
              Text(
                'Editing the checklist and rescheduling are on the website.',
                style: text.bodySmall,
              ),
              Align(
                child: TextButton(
                  key: const Key('inspections-website'),
                  onPressed: () => AppScope.of(context).openLink(
                    Uri.parse('${AppConfig.webBaseUrl}/agent/inspections'),
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

/// Schedules an inspection from a checklist template.
class NewInspectionScreen extends StatefulWidget {
  const NewInspectionScreen({
    super.key,
    required this.book,
    required this.options,
  });

  final ContactBook book;
  final InspectionOptions options;

  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final _form = GlobalKey<FormState>();
  Future<PropertyPage>? _properties;
  Future<List<Tenancy>>? _tenancies;
  ManagedProperty? _property;
  String? _unit;
  String? _tenancy;
  String? _type;
  String? _inspector;
  late String? _template = widget.options.templates.firstOrNull?.code;
  late DateTime _when = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 1)),
  ).add(const Duration(hours: 9));
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _properties ??= AppScope.of(context).properties.properties(widget.book.id);
  }

  void _pickProperty(ManagedProperty p) => setState(() {
    _property = p;
    _unit = null;
    _tenancy = null;
    _tenancies = AppScope.of(context).properties
        .tenancies(widget.book.id, propertyId: p.id)
        .then(
          (page) => [
            for (final t in page.items)
              if (t.status == 'DRAFT' || t.status == 'ACTIVE') t,
          ],
        );
  });

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final made = await AppScope.of(context).inspections.create(
        widget.book.id,
        propertyId: _property!.id,
        unitId: _unit,
        tenancyId: _tenancy,
        type: _type!,
        scheduledFor: _when,
        inspectorUserId: _inspector,
        template: _template!,
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
    final o = widget.options;
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule an inspection')),
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
                key: const Key('inspection-property'),
                label: 'Property',
                value: _property?.id,
                options: [
                  for (final p in page.items) SelectOption(p.id, p.name),
                ],
                onChanged: (id) =>
                    _pickProperty(page.items.firstWhere((p) => p.id == id)),
                validator: (v) => v == null ? 'Choose the property.' : null,
              ),
              if (_property != null && _property!.units.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                SearchableSelectField<String>(
                  key: Key('inspection-unit-${_property!.id}'),
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
              if (_tenancies != null)
                FutureBuilder<List<Tenancy>>(
                  future: _tenancies,
                  builder: (context, snapshot) {
                    final list = [
                      for (final t in snapshot.data ?? const <Tenancy>[])
                        if (_unit == null ||
                            _property!.units
                                    .where((u) => u.id == _unit)
                                    .firstOrNull
                                    ?.label ==
                                t.unitLabel)
                          t,
                    ];
                    if (list.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: Space.x3),
                      child: SearchableSelectField<String>(
                        key: Key('inspection-tenancy-${_property!.id}-$_unit'),
                        label: 'Tenancy (optional)',
                        anyLabel: 'No tenancy',
                        value: _tenancy,
                        helperText:
                            'Its tenants see the report once it is completed '
                            'and the tenancy is active.',
                        options: [
                          for (final t in list)
                            SelectOption(
                              t.id,
                              '${t.place}: ${t.tenants.map((p) => p.name).join(', ')}'
                              '${t.status == 'DRAFT' ? ' (draft)' : ''}',
                            ),
                        ],
                        onChanged: (id) => setState(() => _tenancy = id),
                      ),
                    );
                  },
                ),
              const SizedBox(height: Space.x3),
              SearchableSelectField<String>(
                key: const Key('inspection-type'),
                label: 'Type',
                value: _type,
                options: [
                  for (final e in o.types.entries) SelectOption(e.key, e.value),
                ],
                onChanged: (v) => setState(() => _type = v),
                validator: (v) => v == null ? 'Choose the type.' : null,
              ),
              const SizedBox(height: Space.x3),
              SearchableSelectField<String>(
                key: const Key('inspection-template'),
                label: 'Checklist',
                value: _template,
                options: [
                  for (final t in o.templates)
                    SelectOption(
                      t.code,
                      '${t.label} (${t.areas} areas, ${t.items} items)',
                    ),
                ],
                onChanged: (v) => setState(() => _template = v),
                validator: (v) => v == null ? 'Choose a checklist.' : null,
              ),
              const SizedBox(height: Space.x3),
              SearchableSelectField<String>(
                key: const Key('inspection-inspector'),
                label: 'Inspector',
                anyLabel: 'Me',
                value: _inspector,
                options: [
                  for (final e in o.inspectors.entries)
                    SelectOption(e.key, e.value),
                ],
                onChanged: (v) => setState(() => _inspector = v),
              ),
              const SizedBox(height: Space.x3),
              OutlinedButton.icon(
                key: const Key('inspection-when'),
                onPressed: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: _when,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 729)),
                  );
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_when),
                  );
                  setState(() {
                    _when = DateTime(
                      day.year,
                      day.month,
                      day.day,
                      time?.hour ?? _when.hour,
                      time?.minute ?? _when.minute,
                    );
                  });
                },
                icon: const Icon(Icons.event_outlined),
                label: Text('On ${_stamp.format(_when)}'),
              ),
              Text('In this phone\'s time.', style: text.bodySmall),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              FilledButton(
                key: const Key('inspection-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Schedule the inspection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo read with the session.
class _Photo extends StatelessWidget {
  const _Photo(this.url, {required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(Radii.sm),
    child: SizedBox(
      width: 72,
      height: 72,
      child: FutureBuilder<Uint8List>(
        future: AppScope.of(context).inspections.bytes(url),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                semanticLabel: label,
              )
            : ColoredBox(
                color: context.colors.sunken,
                child: Icon(
                  snapshot.hasError
                      ? Icons.broken_image_outlined
                      : Icons.photo_outlined,
                  semanticLabel: label,
                ),
              ),
      ),
    ),
  );
}

/// One checklist item: the finding, a note saved as the person types, the
/// move-in's finding for comparison, and photos.
class _ItemTile extends StatefulWidget {
  const _ItemTile({
    super.key,
    required this.item,
    required this.editable,
    required this.canPhoto,
    required this.missing,
    required this.onStatus,
    required this.onNote,
    required this.onPhoto,
  });

  final InspectionItem item;
  final bool editable;
  final bool canPhoto;
  final bool missing;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onNote;
  final VoidCallback onPhoto;

  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  late final _note = TextEditingController(text: widget.item.note);
  Timer? _typing;

  @override
  void dispose() {
    // A note typed just before leaving is still saved.
    if (_typing?.isActive ?? false) widget.onNote(_note.text);
    _typing?.cancel();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final i = widget.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i.label, style: text.titleSmall),
          if (i.baselineStatus != null || i.baselineNote != null)
            Text(
              'At move-in: ${i.baselineLabel ?? _findingLabel(i.baselineStatus)}'
              '${(i.baselineNote ?? '').isEmpty ? '' : ', ${i.baselineNote}'}',
              style: text.bodySmall,
            ),
          if (widget.editable) ...[
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                for (final (code, label) in _findings)
                  ChoiceChip(
                    key: Key('finding-${i.id}-$code'),
                    label: Text(label),
                    selected: i.status == code,
                    onSelected: (_) => widget.onStatus(code),
                  ),
              ],
            ),
            if (widget.missing)
              Text(
                'Needs a status',
                style: text.bodySmall?.copyWith(color: c.danger),
              ),
            TextField(
              key: Key('finding-note-${i.id}'),
              controller: _note,
              maxLength: 1000,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              onChanged: (v) {
                _typing?.cancel();
                _typing = Timer(
                  const Duration(milliseconds: 800),
                  () => widget.onNote(v),
                );
              },
              onEditingComplete: () {
                _typing?.cancel();
                widget.onNote(_note.text);
              },
            ),
          ] else ...[
            Text(
              i.statusLabel ?? _findingLabel(i.status),
              style: text.bodyMedium?.copyWith(
                color: i.status == 'DAMAGED' ? c.danger : null,
              ),
            ),
            if (i.note.isNotEmpty) Text(i.note, style: text.bodyMedium),
          ],
          if (i.photos.isNotEmpty || widget.canPhoto) ...[
            const SizedBox(height: Space.x1),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (n, p) in i.photos.indexed)
                  _Photo(p.url, label: '${i.label}, photo ${n + 1}'),
                if (widget.canPhoto)
                  TextButton.icon(
                    key: Key('finding-photo-${i.id}'),
                    onPressed: widget.onPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Photo'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One inspection: record findings (saved as you go), add photos, complete,
/// cancel and see the report. Once completed or cancelled it is read only.
class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key, required this.book, required this.id});

  final ContactBook book;
  final String id;

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  Future<Inspection>? _loading;
  Inspection? _current;
  ApiFailure? _failure;
  String? _saved;
  bool _busy = false;
  Set<String> _missing = const {};

  /// Saves go one at a time, in order.
  Future<void> _queue = Future.value();

  InspectionRepository get _repo => AppScope.of(context).inspections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<Inspection> _get() =>
      _repo.get(widget.book.id, widget.id).then((i) => _current = i);

  void _reload() => setState(() => _loading = _get());

  void _save(FindingChange change) {
    if (mounted) setState(() => _saved = 'Saving…');
    _queue = _queue.then((_) async {
      try {
        final updated = await _repo.saveFindings(widget.book.id, widget.id, [
          change,
        ]);
        if (!mounted) return;
        setState(() {
          _current = updated;
          _loading = Future.value(updated);
          _saved = 'Saved';
          _failure = null;
          _missing = {..._missing}..remove(change.itemId);
        });
      } on ApiFailure catch (failure) {
        if (!mounted) return;
        setState(() {
          _failure = failure;
          _saved = null;
        });
        if (failure.code == 'INSPECTION_CHANGED' ||
            failure.code == 'INSPECTION_CLOSED') {
          _reload();
        }
      }
    });
  }

  Future<void> _run(Future<Inspection> Function() action) async {
    await _queue;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await action();
      if (mounted) {
        setState(() {
          _current = updated;
          _loading = Future.value(updated);
        });
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        if (failure.code == 'INSPECTION_INCOMPLETE') {
          _missing = {
            for (final id in failure.details['item_ids'] as List? ?? const [])
              id as String,
          };
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(InspectionItem item) async {
    final picked = await AppScope.of(context).pickApplicationFile(
      camera: true,
      accept: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null) return;
    await _run(() async {
      await _repo.addPhoto(widget.book.id, widget.id, item.id, picked);
      return _repo.get(widget.book.id, widget.id);
    });
  }

  Future<void> _complete(Inspection i) async {
    final result = await showDialog<_SignOff>(
      context: context,
      builder: (_) => _CompleteDialog(tenants: i.tenants),
    );
    if (result == null) return;
    await _run(
      () => _repo.complete(
        widget.book.id,
        widget.id,
        summary: result.summary,
        tenantName: result.tenant,
        agentName: result.agent,
      ),
    );
  }

  Future<void> _cancel() async {
    final reason = await askForText(
      context,
      title: 'Cancel the inspection',
      label: 'Why it is cancelled',
      action: 'Cancel the inspection',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() => _repo.cancel(widget.book.id, widget.id, reason));
  }

  void _report(Inspection i) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfScreen(
        title: i.frozen && i.status == 'COMPLETED'
            ? 'Inspection report'
            : 'Inspection report (draft)',
        load: () => _repo.bytes(i.reportUrl!),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection')),
      body: AsyncView<Inspection>(
        future: _loading!,
        onRetry: _reload,
        builder: (context, loaded) {
          final i = _current ?? loaded;
          final editable = !i.frozen && i.canRecord;
          final p = i.progress;
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text('${i.typeLabel} inspection', style: text.headlineSmall),
              Text(i.place, style: text.bodyLarge),
              Text(
                '${i.reference}${i.inspectorName == null ? '' : ' · ${i.inspectorName}'}'
                '${i.templateLabel == null ? '' : ' · ${i.templateLabel}'}',
                style: text.bodySmall,
              ),
              Text(
                i.completedAt == null
                    ? 'Scheduled ${_stamp.format(i.scheduledFor)}'
                    : 'Completed ${_stamp.format(i.completedAt!)}',
                style: text.bodyMedium,
              ),
              if (i.tenants.isNotEmpty)
                Text(
                  'Tenants: ${i.tenants.join(', ')}',
                  style: text.bodyMedium,
                ),
              if (i.baselineReference != null)
                Text(
                  'Compared with move-in ${i.baselineReference}',
                  style: text.bodyMedium,
                ),
              const SizedBox(height: Space.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: InspectionStatusBadge(i),
              ),
              const SizedBox(height: Space.x3),
              Semantics(
                label: _progressText(p),
                child: LinearProgressIndicator(
                  key: const Key('inspection-progress'),
                  value: p.items == 0 ? 0 : p.done / p.items,
                ),
              ),
              const SizedBox(height: Space.x1),
              Text(_progressText(p), style: text.bodySmall),
              if (_saved != null && editable)
                Text(
                  _saved!,
                  key: const Key('inspection-saved'),
                  style: text.bodySmall,
                ),
              if (i.frozen)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x2),
                  child: Text(
                    i.status == 'COMPLETED'
                        ? 'Completed: this report can no longer change.'
                        : 'Cancelled${i.cancelReason == null ? '' : ': ${i.cancelReason}'}. '
                              'It can no longer change.',
                    key: const Key('inspection-frozen'),
                    style: text.bodyMedium,
                  ),
                ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x3),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  if (i.canStart && !i.frozen)
                    OutlinedButton(
                      key: const Key('inspection-start'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _repo.start(widget.book.id, widget.id),
                            ),
                      child: const Text('Start'),
                    ),
                  if (i.canComplete && !i.frozen)
                    FilledButton(
                      key: const Key('inspection-complete'),
                      onPressed: _busy ? null : () => _complete(i),
                      child: const Text('Complete'),
                    ),
                  if (i.reportUrl != null)
                    OutlinedButton.icon(
                      key: const Key('inspection-report'),
                      onPressed: () => _report(i),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        i.status == 'COMPLETED' ? 'Report' : 'Draft report',
                      ),
                    ),
                  if (i.canCancel && !i.frozen)
                    TextButton(
                      key: const Key('inspection-cancel'),
                      onPressed: _busy ? null : _cancel,
                      child: const Text('Cancel the inspection'),
                    ),
                ],
              ),
              for (final a in i.areas) ...[
                const SizedBox(height: Space.x4),
                SectionHeading(a.label),
                const SizedBox(height: Space.x2),
                for (final item in a.items)
                  _ItemTile(
                    key: Key('item-${item.id}-${i.frozen}'),
                    item: item,
                    editable: editable,
                    canPhoto: !i.frozen && i.canAddPhoto,
                    missing: _missing.contains(item.id),
                    onStatus: (s) => _save(FindingChange(item.id, status: s)),
                    onNote: (n) => _save(FindingChange(item.id, note: n)),
                    onPhoto: () => _photo(item),
                  ),
              ],
              if (i.summary.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('Summary'),
                Text(i.summary, style: text.bodyLarge),
              ],
              if (i.tenantSignOff != null || i.agentSignOff != null) ...[
                const SizedBox(height: Space.x3),
                Text(
                  'Signed off (typed names): '
                  '${[?i.tenantSignOff, ?i.agentSignOff].join(', ')}',
                  style: text.bodyMedium,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

typedef _SignOff = ({String summary, String tenant, String agent});

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({required this.tenants});

  final List<String> tenants;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  final _summary = TextEditingController();
  late final _tenant = TextEditingController(
    text: widget.tenants.firstOrNull ?? '',
  );
  final _agent = TextEditingController();

  @override
  void dispose() {
    _summary.dispose();
    _tenant.dispose();
    _agent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Complete the inspection'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Once completed, the report is final and the tenants can see it.',
          ),
          TextField(
            key: const Key('complete-summary'),
            controller: _summary,
            maxLength: 5000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Summary (optional)'),
          ),
          TextField(
            key: const Key('complete-tenant'),
            controller: _tenant,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Tenant\'s name, as agreed (optional)',
            ),
          ),
          TextField(
            key: const Key('complete-agent'),
            controller: _agent,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Your name (optional)',
            ),
          ),
          const Text('Typed names are a record, not signatures.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Not yet'),
      ),
      FilledButton(
        key: const Key('complete-send'),
        onPressed: () => Navigator.of(context).pop((
          summary: _summary.text,
          tenant: _tenant.text,
          agent: _agent.text,
        )),
        child: const Text('Complete'),
      ),
    ],
  );
}

/// My Tenancy, Inspections: completed reports of the tenant's tenancy.
class MyInspectionsScreen extends StatefulWidget {
  const MyInspectionsScreen({super.key, required this.tenancy});

  final Tenancy tenancy;

  @override
  State<MyInspectionsScreen> createState() => _MyInspectionsScreenState();
}

class _MyInspectionsScreenState extends State<MyInspectionsScreen> {
  Future<List<Inspection>>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).inspections.mine(widget.tenancy.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inspections')),
    body: AsyncView<List<Inspection>>(
      future: _loading!,
      onRetry: () => setState(() {
        _loading = AppScope.of(context).inspections.mine(widget.tenancy.id);
      }),
      builder: (context, items) => items.isEmpty
          ? const MessageView(
              icon: Icons.fact_check_outlined,
              title: 'No inspection reports yet',
              body:
                  'A report shows here once your landlord or agent has '
                  'completed the inspection.',
            )
          : ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _InspectionCard(
                      i,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MyInspectionScreen(
                            tenancyId: widget.tenancy.id,
                            id: i.id,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class MyInspectionScreen extends StatefulWidget {
  const MyInspectionScreen({
    super.key,
    required this.tenancyId,
    required this.id,
  });

  final String tenancyId;
  final String id;

  @override
  State<MyInspectionScreen> createState() => _MyInspectionScreenState();
}

class _MyInspectionScreenState extends State<MyInspectionScreen> {
  Future<Inspection>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).inspections
        .myInspection(widget.tenancyId, widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final repo = AppScope.of(context).inspections;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection report')),
      body: AsyncView<Inspection>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = repo.myInspection(widget.tenancyId, widget.id);
        }),
        builder: (context, i) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text('${i.typeLabel} inspection', style: text.headlineSmall),
            Text(i.place, style: text.bodyLarge),
            Text(
              '${i.reference}${i.inspectorName == null ? '' : ' · ${i.inspectorName}'}',
              style: text.bodySmall,
            ),
            if (i.completedAt != null)
              Text(
                'Completed ${_stamp.format(i.completedAt!)}',
                style: text.bodyMedium,
              ),
            if (i.baselineReference != null)
              Text(
                'Compared with move-in ${i.baselineReference}',
                style: text.bodyMedium,
              ),
            const SizedBox(height: Space.x2),
            Text(_progressText(i.progress), style: text.bodySmall),
            const SizedBox(height: Space.x2),
            if (i.reportUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('my-inspection-report'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfScreen(
                        title: 'Inspection report',
                        load: () => repo.bytes(i.reportUrl!),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Report (PDF)'),
                ),
              ),
            for (final a in i.areas) ...[
              const SizedBox(height: Space.x4),
              SectionHeading(a.label),
              const SizedBox(height: Space.x2),
              for (final item in a.items)
                _ItemTile(
                  key: Key('my-item-${item.id}'),
                  item: item,
                  editable: false,
                  canPhoto: false,
                  missing: false,
                  onStatus: (_) {},
                  onNote: (_) {},
                  onPhoto: () {},
                ),
            ],
            if (i.summary.isNotEmpty) ...[
              const SizedBox(height: Space.x4),
              const SectionHeading('Summary'),
              Text(i.summary, style: text.bodyLarge),
            ],
            if (i.tenantSignOff != null || i.agentSignOff != null) ...[
              const SizedBox(height: Space.x3),
              Text(
                'Signed off (typed names): '
                '${[?i.tenantSignOff, ?i.agentSignOff].join(', ')}',
                style: text.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
