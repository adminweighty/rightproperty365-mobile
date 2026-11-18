import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import 'application_models.dart';
import 'applications_repository.dart';

/// Applying for a property: the form's sections one step at a time, then a
/// review, then the reference. Answers save themselves as they are typed
/// (a draft can be closed and reopened), files go to private storage, and
/// questions appear and disappear with the answers they depend on.
class ApplyScreen extends StatefulWidget {
  const ApplyScreen({super.key, this.slug, this.applicationId})
    : assert(slug != null || applicationId != null);

  /// Start from a listing...
  final String? slug;

  /// ...or reopen a draft or an application waiting for more information.
  final String? applicationId;

  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  Future<Application?>? _loading;
  String? _closed;
  bool _needsSignIn = false;
  bool _noForm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<Application?> _load() async {
    final services = AppScope.of(context);
    final repo = services.myApplications;
    _closed = null;
    _needsSignIn = false;
    _noForm = false;
    if (widget.applicationId != null) return repo.get(widget.applicationId!);
    if (!services.auth.signedIn) {
      _needsSignIn = true;
      return null;
    }
    final listing = await services.listings.bySlug(widget.slug!);
    final attached = await repo.formFor(widget.slug!);
    if (listing == null || attached == null) {
      _noForm = true;
      return null;
    }
    try {
      return await repo.start(listing.id);
    } on ApplicationsClosed catch (closed) {
      _closed = closed.message;
      return null;
    }
  }

  void _reload() => setState(() {
    _loading = _load();
  });

  Future<void> _signIn() async {
    await context.push(Routes.signIn);
    if (mounted && AppScope.of(context).auth.signedIn) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply')),
      body: AsyncView<Application?>(
        future: _loading!,
        onRetry: _reload,
        builder: (context, application) {
          if (_needsSignIn) {
            return MessageView(
              icon: Icons.login,
              title: 'Sign in to apply',
              body: 'Applications are kept with your account, so you can finish later and follow their status.',
              actionLabel: 'Sign in',
              onAction: _signIn,
            );
          }
          if (_closed != null) {
            return MessageView(
              icon: Icons.event_busy_outlined,
              title: 'Applications are not open',
              body: _closed!,
            );
          }
          if (_noForm || application == null || application.form == null) {
            return const MessageView(
              icon: Icons.description_outlined,
              title: 'This property takes no applications',
              body: 'Send an enquiry instead; the advertiser will reply.',
            );
          }
          return _ApplicationForm(application);
        },
      ),
    );
  }
}

class _ApplicationForm extends StatefulWidget {
  const _ApplicationForm(this.initial);

  final Application initial;

  @override
  State<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends State<_ApplicationForm> {
  late Application _app = widget.initial;
  late final Map<String, Object?> _answers = {..._app.answers};
  final Map<String, Object?> _unsaved = {};
  final Map<String, TextEditingController> _text = {};
  Map<String, String> _errors = {};
  Timer? _autosave;
  String _saveState = '';
  int _step = 0;
  bool _busy = false;
  ApiFailure? _failure;
  String? _uploading;

  ApplicationForm get _form => _app.form!;
  MyApplicationsRepository get _repo => AppScope.of(context).myApplications;
  bool get _editable => _app.canEdit;

  @override
  void dispose() {
    _autosave?.cancel();
    // A last save of anything typed, so a closed draft keeps it.
    if (_unsaved.isNotEmpty) {
      _repo.save(_app.id, {..._unsaved}).ignore();
    }
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(FormFieldSpec field) => _text.putIfAbsent(
    field.key,
    () => TextEditingController(text: '${_answers[field.key] ?? ''}'),
  );

  void _set(String key, Object? value) {
    setState(() {
      _answers[key] = value;
      _unsaved[key] = value;
      _errors.remove(key);
      _saveState = 'Not saved yet';
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<bool> _save() async {
    _autosave?.cancel();
    if (_unsaved.isEmpty) return true;
    final batch = {..._unsaved};
    _unsaved.clear();
    setState(() => _saveState = 'Saving…');
    try {
      final saved = await _repo.save(_app.id, batch);
      if (!mounted) return true;
      setState(() {
        _app = saved;
        _saveState = 'Saved';
      });
      return true;
    } on ApiFailure catch (failure) {
      if (!mounted) return false;
      // Keep the answers to send again.
      for (final e in batch.entries) {
        _unsaved.putIfAbsent(e.key, () => e.value);
      }
      setState(() {
        _saveState = failure.isNetwork
            ? 'Not saved: no connection. It will be sent when you continue.'
            : 'Not saved';
        _errors = {
          for (final e in failure.fields.entries)
            e.key.replaceFirst('answers.', ''): e.value,
        };
      });
      return false;
    }
  }

  Future<void> _addFile(FormFieldSpec field) async {
    final services = AppScope.of(context);
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('file-from-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              key: const Key('file-from-files'),
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Choose a file'),
              subtitle: Text(
                field.accept.map((e) => e.toUpperCase()).join(', '),
              ),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    final picked = await services.pickApplicationFile(
      camera: camera,
      accept: field.accept,
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ext = picked.name.split('.').last.toLowerCase();
    final type = ext == 'jpeg' ? 'jpg' : ext;
    if (!field.accept.contains(type)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'This question takes ${field.accept.map((e) => e.toUpperCase()).join(', ')} files.',
          ),
        ),
      );
      return;
    }
    if (picked.bytes.length > maxFileBytes) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file is over 10 MB.')),
      );
      return;
    }
    await _save();
    setState(() => _uploading = field.key);
    try {
      final updated = await _repo.upload(_app.id, field.key, picked);
      if (!mounted) return;
      setState(() {
        _app = updated;
        _answers[field.key] = updated.answers[field.key];
        _errors.remove(field.key);
      });
    } on ApiFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _removeFile(FormFieldSpec field, ApplicationFile file) async {
    try {
      final updated = await _repo.removeFile(_app.id, file.id);
      if (mounted) {
        setState(() {
          _app = updated;
          _answers[field.key] = updated.answers[field.key];
        });
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  bool get _onReview => _step >= _form.sections.length;

  Future<void> _next() async {
    final section = _form.sections[_step];
    final problems = {
      for (final f in section.fields)
        if (_form.visible(f, _answers))
          if (f.problem(_answers[f.key]) case final String p) f.key: p,
    };
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
      return;
    }
    await _save();
    if (mounted) setState(() => _step++);
  }

  Future<void> _submit() async {
    final problems = _form.problems(_answers);
    if (problems.isNotEmpty) {
      _goToProblem(problems);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      if (!await _save()) return;
      final submitted = await _repo.submit(_app.id);
      if (mounted) setState(() => _app = submitted);
    } on ApplicationsClosed catch (closed) {
      if (mounted) {
        setState(
          () => _failure = ApiFailure(
            status: 409,
            code: 'APPLICATIONS_CLOSED',
            message: closed.message,
          ),
        );
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      final fields = {
        for (final e in failure.fields.entries)
          e.key.replaceFirst('answers.', ''): e.value,
      };
      if (fields.isNotEmpty) {
        _goToProblem(fields);
      } else {
        setState(() => _failure = failure);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToProblem(Map<String, String> problems) {
    final first = _form.sections.indexWhere(
      (s) => s.fields.any((f) => problems.containsKey(f.key)),
    );
    setState(() {
      _errors = problems;
      if (first >= 0) _step = first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_app.reference != null && !_editable) {
      return _Confirmation(_app);
    }
    final sections = _form.sections;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_step + 1) / (sections.length + 1),
          semanticsLabel: 'Step ${_step + 1} of ${sections.length + 1}',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text(_app.listingTitle, style: text.bodyMedium),
              Semantics(
                header: true,
                child: Text(
                  _onReview ? 'Check your answers' : sections[_step].title,
                  style: text.headlineSmall,
                ),
              ),
              Text(
                'Step ${_step + 1} of ${sections.length + 1}'
                '${_saveState.isEmpty ? '' : ' · $_saveState'}',
                style: text.bodySmall,
              ),
              if (_app.infoRequest != null && _app.status == 'MORE_INFO')
                Container(
                  margin: const EdgeInsets.only(top: Space.x3),
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(
                    color: context.colors.primarySoft,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(
                    'They asked: ${_app.infoRequest}',
                    style: text.bodyLarge,
                  ),
                ),
              const SizedBox(height: Space.x4),
              if (_onReview)
                ..._review(context)
              else ...[
                if (sections[_step].description != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: Text(
                      sections[_step].description!,
                      style: text.bodyLarge,
                    ),
                  ),
                for (final field in sections[_step].fields)
                  if (_form.visible(field, _answers))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x5),
                      child: _field(context, field),
                    ),
              ],
              if (_failure != null) FailureBox(_failure!),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Space.x3),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('apply-back'),
                      onPressed: _busy ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: Space.x3),
                Expanded(
                  child: FilledButton(
                    key: Key(_onReview ? 'apply-submit' : 'apply-next'),
                    onPressed: _busy || !_editable
                        ? null
                        : _onReview
                        ? _submit
                        : _next,
                    child: Text(
                      _onReview
                          ? (_app.status == 'MORE_INFO'
                                ? 'Send it again'
                                : 'Submit application')
                          : 'Continue',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _review(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return [
      for (final section in _form.sections) ...[
        SectionHeading(section.title),
        const SizedBox(height: Space.x2),
        for (final field in section.fields)
          if (_form.visible(field, _answers))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(field.label, style: text.titleSmall),
                  Text(_display(field), style: text.bodyLarge),
                ],
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                setState(() => _step = _form.sections.indexOf(section)),
            child: Text('Change ${section.title.toLowerCase()}'),
          ),
        ),
        const SizedBox(height: Space.x3),
      ],
      const Divider(),
      Text('Why this is asked', style: text.titleSmall),
      Text(_form.purpose, style: text.bodyMedium),
      const SizedBox(height: Space.x2),
      Text('Your privacy', style: text.titleSmall),
      Text(_form.privacyNotice, style: text.bodyMedium),
      if (_form.retentionDays != null)
        Text(
          'Your answers and files are deleted ${_form.retentionDays} days after a decision.',
          style: text.bodySmall,
        ),
      const SizedBox(height: Space.x4),
    ];
  }

  String _display(FormFieldSpec field) {
    final value = _answers[field.key];
    if (value == null || (value is List && value.isEmpty) || value == '') {
      return 'Not answered';
    }
    String label(Object? v) =>
        field.options.where((o) => o.value == v).firstOrNull?.label ?? '$v';
    return switch (field.type) {
      'single_choice' => label(value),
      'multiple_choice' => (value as List).map(label).join(', '),
      'file' => [
        for (final f in _app.files)
          if ((value as List).contains(f.id)) f.fileName,
      ].join(', '),
      'date' => _dateLabel('$value'),
      _ => '$value',
    };
  }

  static String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMMM y').format(d);
  }

  Widget _field(BuildContext context, FormFieldSpec field) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final error = _errors[field.key];
    final label = '${field.label}${field.required ? '' : ' (optional)'}';
    final help = field.help;
    Widget titled(Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.titleSmall),
        if (help != null) Text(help, style: text.bodySmall),
        child,
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(error, style: TextStyle(color: c.danger)),
          ),
      ],
    );

    switch (field.type) {
      case 'short_text' || 'long_text' || 'number':
        return TextField(
          key: Key('answer-${field.key}'),
          controller: _controller(field),
          enabled: _editable,
          maxLength: field.type == 'number' ? null : field.textLimit,
          minLines: field.type == 'long_text' ? 3 : 1,
          maxLines: field.type == 'long_text' ? 8 : 1,
          keyboardType: field.type == 'number'
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          onChanged: (v) => _set(
            field.key,
            field.type == 'number'
                ? (v.trim().isEmpty ? null : num.tryParse(v.trim()) ?? v)
                : (v.isEmpty ? null : v),
          ),
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            errorText: error,
          ),
        );
      case 'date':
        final value = _answers[field.key] as String?;
        return titled(
          OutlinedButton.icon(
            key: Key('answer-${field.key}'),
            onPressed: !_editable
                ? null
                : () async {
                    final now = DateTime.now();
                    final first =
                        DateTime.tryParse(field.minDate ?? '') ??
                        DateTime(now.year - 100);
                    final last =
                        DateTime.tryParse(field.maxDate ?? '') ??
                        DateTime(now.year + 10);
                    final initial = DateTime.tryParse(value ?? '') ?? now;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial.isBefore(first)
                          ? first
                          : initial.isAfter(last)
                          ? last
                          : initial,
                      firstDate: first,
                      lastDate: last,
                    );
                    if (picked != null) {
                      _set(field.key, DateFormat('yyyy-MM-dd').format(picked));
                    }
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(value == null ? 'Choose a date' : _dateLabel(value)),
          ),
        );
      case 'single_choice':
        return titled(
          RadioGroup<String>(
            groupValue: _answers[field.key] as String?,
            onChanged: (v) {
              if (_editable) _set(field.key, v);
            },
            child: Column(
              children: [
                for (final o in field.options)
                  RadioListTile<String>(
                    key: Key('answer-${field.key}-${o.value}'),
                    contentPadding: EdgeInsets.zero,
                    value: o.value,
                    title: Text(o.label),
                  ),
              ],
            ),
          ),
        );
      case 'multiple_choice':
        final chosen = [
          for (final v in (_answers[field.key] as List?) ?? const []) '$v',
        ];
        return titled(
          Column(
            children: [
              for (final o in field.options)
                CheckboxListTile(
                  key: Key('answer-${field.key}-${o.value}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: chosen.contains(o.value),
                  onChanged: !_editable
                      ? null
                      : (on) => _set(field.key, [
                          for (final v in field.options)
                            if (v.value == o.value
                                ? on == true
                                : chosen.contains(v.value))
                              v.value,
                        ]),
                  title: Text(o.label),
                ),
            ],
          ),
        );
      case 'file':
        final ids = [
          for (final v in (_answers[field.key] as List?) ?? const []) '$v',
        ];
        final files = [
          for (final f in _app.files)
            if (ids.contains(f.id)) f,
        ];
        return titled(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${field.accept.map((e) => e.toUpperCase()).join(', ')} · up to 10 MB each'
                '${field.maxFiles > 1 ? ' · up to ${field.maxFiles} files' : ''}',
                style: text.bodySmall,
              ),
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(f.fileName),
                  subtitle: Text('${(f.size / 1024).ceil()} KB'),
                  trailing: _editable
                      ? IconButton(
                          tooltip: 'Remove ${f.fileName}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeFile(field, f),
                        )
                      : null,
                ),
              if (_uploading == field.key)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.x2),
                  child: LinearProgressIndicator(semanticsLabel: 'Uploading'),
                )
              else if (_editable && files.length < field.maxFiles)
                OutlinedButton.icon(
                  key: Key('answer-${field.key}-add'),
                  onPressed: () => _addFile(field),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Add a file'),
                ),
              Text(
                'Files are private: only the advertiser you apply to can open them.',
                style: text.bodySmall,
              ),
            ],
          ),
        );
      default:
        return titled(
          Text(
            'This question can be answered on the website.',
            style: text.bodyMedium,
          ),
        );
    }
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation(this.application);

  final Application application;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        const SizedBox(height: Space.x6),
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: context.colors.success,
        ),
        const SizedBox(height: Space.x3),
        Semantics(
          header: true,
          child: Text('Application sent', style: text.headlineSmall),
        ),
        const SizedBox(height: Space.x2),
        Text(
          'Your reference is ${application.reference}. You can follow it in Activity, '
          'and you are told by email when it moves on.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: Space.x2),
        SelectableText(
          application.reference ?? '',
          key: const Key('application-reference'),
          style: text.titleLarge,
        ),
        const SizedBox(height: Space.x6),
        FilledButton(
          onPressed: () => context.go(Routes.activity),
          child: const Text('Go to Activity'),
        ),
      ],
    );
  }
}

/// One of the person's applications: where it stands, its history, and
/// what they can do next.
class MyApplicationScreen extends StatefulWidget {
  const MyApplicationScreen({super.key, required this.id});

  final String id;

  @override
  State<MyApplicationScreen> createState() => _MyApplicationScreenState();
}

class _MyApplicationScreenState extends State<MyApplicationScreen> {
  Future<Application>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).myApplications.get(widget.id);
  }

  void _reload() => setState(() {
    _loading = AppScope.of(context).myApplications.get(widget.id);
  });

  Future<void> _withdraw(Application a) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: const Text('The advertiser is told. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const Key('withdraw-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await AppScope.of(context).myApplications.withdraw(a.id);
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stamp = DateFormat('d MMM y, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Your application')),
      body: AsyncView<Application>(
        future: _loading!,
        onRetry: _reload,
        builder: (context, a) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Semantics(
              header: true,
              child: Text(a.listingTitle, style: text.headlineSmall),
            ),
            Text(
              '${a.statusLabel}${a.reference == null ? '' : ' · ${a.reference}'}',
              style: text.titleMedium,
            ),
            if (a.infoRequest != null && a.status == 'MORE_INFO')
              Padding(
                padding: const EdgeInsets.only(top: Space.x3),
                child: Text(
                  'They asked for more information: ${a.infoRequest}',
                  style: text.bodyLarge,
                ),
              ),
            if (a.erased)
              Padding(
                padding: const EdgeInsets.only(top: Space.x3),
                child: Text(
                  'Your answers and files have been deleted, as the form said they would be.',
                  style: text.bodyMedium,
                ),
              ),
            const SizedBox(height: Space.x4),
            if (a.canEdit)
              FilledButton(
                key: const Key('application-continue'),
                onPressed: () async {
                  await context.push(Routes.continueApplication(a.id));
                  if (mounted) _reload();
                },
                child: Text(
                  a.status == 'MORE_INFO'
                      ? 'Add what they asked for'
                      : 'Continue the application',
                ),
              ),
            if (a.canWithdraw)
              TextButton(
                key: const Key('application-withdraw'),
                onPressed: () => _withdraw(a),
                child: const Text('Withdraw the application'),
              ),
            if (a.listingSlug != null)
              TextButton(
                onPressed: () => context.push(
                  Routes.listing(a.listingSlug!, heroScope: 'application'),
                ),
                child: const Text('View the property'),
              ),
            const SizedBox(height: Space.x4),
            const SectionHeading('History'),
            const SizedBox(height: Space.x2),
            for (final e in a.timeline.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.label, style: text.bodyLarge),
                    if (e.message != null) Text(e.message!),
                    Text(stamp.format(e.at.toLocal()), style: text.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "My Applications" in Activity.
class MyApplicationsView extends StatefulWidget {
  const MyApplicationsView({super.key});

  @override
  State<MyApplicationsView> createState() => _MyApplicationsViewState();
}

class _MyApplicationsViewState extends State<MyApplicationsView> {
  Future<List<Application>>? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _list ??= AppScope.of(context).myApplications.list();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).myApplications.list();
    setState(() {
      _list = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AsyncView<List<Application>>(
      future: _list!,
      onRetry: _reload,
      builder: (context, items) {
        if (items.isEmpty) {
          return MessageView(
            icon: Icons.assignment_outlined,
            title: 'No applications yet',
            body:
                'Properties that take applications show "Apply" on their page.',
            actionLabel: 'Find a property',
            onAction: () => context.go(Routes.search()),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x3),
                  child: BrandCard(
                    key: Key('application-${a.id}'),
                    emphasised: a.status == 'MORE_INFO',
                    semanticLabel:
                        '${a.listingTitle}. ${a.statusLabel}${a.reference == null ? '' : '. ${a.reference}'}',
                    onTap: () async {
                      await context.push(Routes.myApplication(a.id));
                      if (mounted) _reload();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.listingTitle, style: text.titleMedium),
                          Text(a.statusLabel, style: text.titleSmall),
                          Text(
                            a.reference ?? 'Draft: not sent yet',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
