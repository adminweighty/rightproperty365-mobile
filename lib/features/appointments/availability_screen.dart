import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/market_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import 'availability.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// When customers may book the signed-in professional, and the
/// consultations they offer (API 0.51.0). Consultations are free.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  Future<void>? _loading;
  late AvailabilitySettings _s;
  List<ConsultationService> _services = const [];
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).availability;
    final results = await Future.wait([repo.settings(), repo.services()]);
    _s = results[0] as AvailabilitySettings;
    _services = results[1] as List<ConsultationService>;
  }

  void _set(AvailabilitySettings next) => setState(() => _s = next);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final saved = await AppScope.of(context).availability.save(_s);
      if (!mounted) return;
      setState(() => _s = saved);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Availability saved.')));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<(TimeOfDay, TimeOfDay)?> _pickRange({
    TimeOfDay from = const TimeOfDay(hour: 9, minute: 0),
    TimeOfDay to = const TimeOfDay(hour: 17, minute: 0),
  }) async {
    final opens = await showTimePicker(
      context: context,
      initialTime: from,
      helpText: 'Opens at',
    );
    if (opens == null || !mounted) return null;
    final closes = await showTimePicker(
      context: context,
      initialTime: to,
      helpText: 'Closes at',
    );
    if (closes == null) return null;
    return (opens, closes);
  }

  Future<void> _addHours(int weekday) async {
    final range = await _pickRange();
    if (range == null) return;
    final (opens, closes) = range;
    final next =
        [
          ..._s.workingHours,
          (weekday: weekday, opens: _hhmm(opens), closes: _hhmm(closes)),
        ]..sort((a, b) {
          final byDay = a.weekday.compareTo(b.weekday);
          return byDay != 0 ? byDay : a.opens.compareTo(b.opens);
        });
    _set(_s.copyWith(workingHours: next));
  }

  Future<void> _addException() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      initialDate: now.add(const Duration(days: 1)),
      helpText: 'Date with other hours',
    );
    if (date == null || !mounted) return;
    final result = await showDialog<AvailabilityException>(
      context: context,
      builder: (context) => _ExceptionDialog(date: _ymd(date)),
    );
    if (result == null) return;
    final next = [..._s.exceptions.where((e) => e.date != result.date), result]
      ..sort((a, b) => a.date.compareTo(b.date));
    _set(_s.copyWith(exceptions: next));
  }

  Future<void> _editService([ConsultationService? service]) async {
    final saved = await showModalBottomSheet<ConsultationService>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ServiceSheet(service: service),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _services = [
        for (final s in _services)
          if (s.id != saved.id) s,
        saved,
      ];
    });
  }

  Future<void> _archive(ConsultationService service) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${service.name}?'),
        content: const Text(
          'Customers can no longer choose it. Appointments already booked '
          'keep its name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('service-archive-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await AppScope.of(context).availability.archiveService(service.id);
      if (!mounted) return;
      setState(() {
        _services = [
          for (final s in _services)
            if (s.id != service.id) s,
        ];
      });
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: AsyncView<void>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = _load();
        }),
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final s = _s;
    final failure = _failure;
    const gap = SizedBox(height: Space.x4);
    Widget select(
      String key,
      String label,
      int value,
      List<int> choices,
      String Function(int) name,
      AvailabilitySettings Function(int) apply,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: SearchableSelectField<int>(
        key: Key('availability-$key'),
        label: label,
        value: value,
        options: [
          for (final n in {...choices, value}.toList()..sort())
            SelectOption(n, name(n)),
        ],
        onChanged: (n) {
          if (n != null) _set(apply(n));
        },
      ),
    );

    final active = _services.where((x) => x.active).toList();
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Text(
          'Customers booking a viewing or consultation with you pick one of '
          'these times. You can still confirm or propose any time yourself.',
          style: text.bodyLarge,
        ),
        gap,
        SwitchListTile(
          key: const Key('availability-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Offer times from my calendar'),
          subtitle: Text(
            s.enabled
                ? 'On: customers choose from your free times.'
                : 'Off: customers may ask for any time.',
          ),
          value: s.enabled,
          onChanged: (on) => _set(s.copyWith(enabled: on)),
        ),
        Text(
          'Times are in ${MarketTime.zoneName(s.timezone)} time '
          '(${s.timezone}).',
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x6),
        const SectionHeading('Working hours'),
        const SizedBox(height: Space.x2),
        for (var day = 1; day <= 7; day++)
          Padding(
            key: Key('availability-day-$day'),
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_weekdays[day - 1], style: text.titleMedium),
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final r in s.workingHours.where(
                      (r) => r.weekday == day,
                    ))
                      InputChip(
                        label: Text('${r.opens}–${r.closes}'),
                        deleteButtonTooltipMessage:
                            'Remove ${_weekdays[day - 1]} ${r.opens} to '
                            '${r.closes}',
                        onDeleted: () => _set(
                          s.copyWith(
                            workingHours: [
                              for (final x in s.workingHours)
                                if (x != r) x,
                            ],
                          ),
                        ),
                      ),
                    if (!s.workingHours.any((r) => r.weekday == day))
                      Text('Closed', style: text.bodyMedium),
                    TextButton.icon(
                      key: Key('availability-add-$day'),
                      onPressed: () => _addHours(day),
                      icon: const Icon(Icons.add),
                      label: const Text('Add hours'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.x4),
        const SectionHeading('Dates with other hours'),
        const SizedBox(height: Space.x2),
        if (s.exceptions.isEmpty)
          Text(
            'None. Add holidays or days with other hours.',
            style: text.bodyMedium,
          ),
        for (final e in s.exceptions)
          ListTile(
            key: Key('availability-exception-${e.date}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              DateFormat('EEE d MMM y').format(DateTime.parse(e.date)),
            ),
            subtitle: Text(
              [
                e.closed ? 'Closed' : '${e.opens}–${e.closes}',
                if (e.note != null && e.note!.isNotEmpty) e.note!,
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Remove this date',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _set(
                s.copyWith(
                  exceptions: [
                    for (final x in s.exceptions)
                      if (x != e) x,
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('availability-add-exception'),
            onPressed: _addException,
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text('Add a date'),
          ),
        ),
        const SizedBox(height: Space.x4),
        const SectionHeading('Booking rules'),
        const SizedBox(height: Space.x3),
        select(
          'slot',
          'Appointment length',
          s.slotMinutes,
          [for (var m = 15; m <= 240; m += 15) m],
          (n) => _plural(n, 'minute'),
          (n) => s.copyWith(slotMinutes: n),
        ),
        select(
          'buffer',
          'Break between appointments',
          s.bufferMinutes,
          const [0, 5, 10, 15, 20, 30, 45, 60, 90, 120],
          (n) => n == 0 ? 'No break' : _plural(n, 'minute'),
          (n) => s.copyWith(bufferMinutes: n),
        ),
        select(
          'lead',
          'Earliest booking',
          s.leadTimeHours,
          const [0, 1, 2, 4, 8, 12, 24, 48, 72, 168, 336],
          (n) => n == 0 ? 'Any time from now' : '${_plural(n, 'hour')} ahead',
          (n) => s.copyWith(leadTimeHours: n),
        ),
        select(
          'horizon',
          'Furthest booking',
          s.horizonDays,
          const [7, 14, 21, 30, 60, 90, 120, 180],
          (n) => '${_plural(n, 'day')} ahead',
          (n) => s.copyWith(horizonDays: n),
        ),
        select(
          'max',
          'Most appointments a day',
          s.maxPerDay,
          const [0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 50],
          (n) => n == 0 ? 'No limit' : '$n',
          (n) => s.copyWith(maxPerDay: n),
        ),
        if (failure != null) ...[
          FailureBox(failure),
          for (final f in failure.fields.entries)
            Text(
              '${f.key.replaceAll('_', ' ')}: ${f.value}',
              style: text.bodyMedium?.copyWith(color: c.danger),
            ),
          gap,
        ],
        FilledButton(
          key: const Key('availability-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save availability'),
        ),
        const SizedBox(height: Space.x8),
        const SectionHeading('Consultations you offer'),
        const SizedBox(height: Space.x2),
        Text(
          'Customers can pick one when they ask for a consultation. '
          'Consultations are free: paid consultations are not offered.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x3),
        if (active.isEmpty)
          Text(
            'No consultations yet.',
            key: const Key('services-empty'),
            style: text.bodyLarge,
          ),
        for (final service in active)
          Padding(
            key: Key('service-${service.id}'),
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: Container(
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: text.titleMedium),
                  Text(service.summary, style: text.bodyMedium),
                  if (service.location != null && service.location!.isNotEmpty)
                    Text(service.location!, style: text.bodyMedium),
                  Wrap(
                    spacing: Space.x2,
                    children: [
                      TextButton(
                        key: Key('service-edit-${service.id}'),
                        onPressed: () => _editService(service),
                        child: const Text('Edit'),
                      ),
                      TextButton(
                        key: Key('service-archive-${service.id}'),
                        onPressed: () => _archive(service),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          key: const Key('service-add'),
          onPressed: active.length >= 20 ? null : () => _editService(),
          icon: const Icon(Icons.add),
          label: const Text('Add a consultation'),
        ),
        if (active.length >= 20)
          Text('You can offer up to 20 consultations.', style: text.bodySmall),
      ],
    );
  }
}

class _ExceptionDialog extends StatefulWidget {
  const _ExceptionDialog({required this.date});

  final String date;

  @override
  State<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends State<_ExceptionDialog> {
  bool _closed = true;
  TimeOfDay _opens = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closes = const TimeOfDay(hour: 13, minute: 0);
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool opens) async {
    final t = await showTimePicker(
      context: context,
      initialTime: opens ? _opens : _closes,
    );
    if (t == null) return;
    setState(() => opens ? _opens = t : _closes = t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(DateFormat('EEE d MMM y').format(DateTime.parse(widget.date))),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('exception-closed'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Closed all day'),
            value: _closed,
            onChanged: (v) => setState(() => _closed = v),
          ),
          if (!_closed) ...[
            OutlinedButton(
              key: const Key('exception-opens'),
              onPressed: () => _pick(true),
              child: Text('Opens ${_hhmm(_opens)}'),
            ),
            const SizedBox(height: Space.x2),
            OutlinedButton(
              key: const Key('exception-closes'),
              onPressed: () => _pick(false),
              child: Text('Closes ${_hhmm(_closes)}'),
            ),
          ],
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('exception-note'),
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('exception-add'),
        onPressed: () => Navigator.pop(context, (
          date: widget.date,
          closed: _closed,
          opens: _closed ? null : _hhmm(_opens),
          closes: _closed ? null : _hhmm(_closes),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        )),
        child: const Text('Add'),
      ),
    ],
  );
}

/// Adds or changes a consultation service.
class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet({this.service});

  final ConsultationService? service;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _location = TextEditingController(text: widget.service?.location);
  late final _notes = TextEditingController(text: widget.service?.notes);
  late int _duration = widget.service?.durationMinutes ?? 30;
  late ConsultationChannel _channel =
      widget.service?.channel ?? ConsultationChannel.inPerson;
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final repo = AppScope.of(context).availability;
    try {
      final existing = widget.service;
      final saved = existing == null
          ? await repo.createService(
              name: _name.text,
              durationMinutes: _duration,
              channel: _channel,
              location: _location.text,
              notes: _notes.text,
            )
          : await repo.updateService(
              existing.id,
              name: _name.text,
              durationMinutes: _duration,
              channel: _channel,
              location: _location.text,
              notes: _notes.text,
            );
      if (mounted) Navigator.pop(context, saved);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: Space.x4,
        right: Space.x4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.x4,
      ),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              widget.service == null
                  ? 'Add a consultation'
                  : 'Change consultation',
              style: text.titleLarge,
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('service-name'),
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Give it a name' : null,
            ),
            SearchableSelectField<int>(
              key: const Key('service-duration'),
              label: 'Length',
              value: _duration,
              options: [
                for (final m in {
                  for (var m = 15; m <= 240; m += 15) m,
                  _duration,
                }.toList()..sort())
                  SelectOption(m, _plural(m, 'minute')),
              ],
              onChanged: (m) => setState(() => _duration = m ?? _duration),
            ),
            const SizedBox(height: Space.x3),
            SearchableSelectField<ConsultationChannel>(
              key: const Key('service-channel'),
              label: 'How it takes place',
              value: _channel,
              options: [
                for (final ch in ConsultationChannel.values)
                  SelectOption(ch, ch.label),
              ],
              onChanged: (ch) => setState(() => _channel = ch ?? _channel),
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('service-location'),
              controller: _location,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Where (optional)',
                helperText: 'For example the office address or "We call you".',
              ),
            ),
            TextFormField(
              key: const Key('service-notes'),
              controller: _notes,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_failure != null) ...[
              FailureBox(_failure!),
              const SizedBox(height: Space.x3),
            ],
            FilledButton(
              key: const Key('service-save'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
