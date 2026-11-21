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
import '../../core/widgets/searchable_select.dart';
import '../listings/data/listing.dart';
import 'saved_searches.dart';

/// The search screen for [search], with the filters the app has.
String savedSearchRoute(SavedSearch search) {
  final f = search.filters;
  return Routes.search(query: f.query, deal: f.deal, category: f.category);
}

/// "Save this search" on Search: asks for a name and how often to alert,
/// after signing in when needed.
Future<void> saveSearch(BuildContext context, ListingFilters filters) async {
  final services = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (!services.auth.signedIn) {
    final signIn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in to save searches'),
        content: const Text(
          'Saved searches are kept with your account, and we tell you when '
          'new listings match. You come straight back here after signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('save-search-sign-in'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (signIn != true || !context.mounted) return;
    await context.push(Routes.signIn);
    if (!services.auth.signedIn || !context.mounted) return;
  }
  final saved = await showDialog<SavedSearch>(
    context: context,
    builder: (context) => _SaveDialog(filters: filters),
  );
  if (saved == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          saved.frequency == AlertFrequency.off
              ? 'Search saved.'
              : 'Search saved. We tell you about new listings: '
                    '${saved.frequency.label.toLowerCase()}.',
        ),
      ),
    );
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.filters});

  final ListingFilters filters;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final _name = TextEditingController(text: searchSummary(widget.filters));
  AlertFrequency _frequency = AlertFrequency.daily;
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final saved = await AppScope.of(context).savedSearches.create(
        name: _name.text,
        filters: widget.filters,
        frequency: _frequency,
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
    final c = context.colors;
    final failure = _failure;
    return AlertDialog(
      title: const Text('Save this search'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('save-search-name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: failure?.fields['name'],
              ),
            ),
            SearchableSelectField<AlertFrequency>(
              key: const Key('save-search-frequency'),
              label: 'Tell me about new listings',
              value: _frequency,
              options: [
                for (final f in AlertFrequency.values) SelectOption(f, f.label),
              ],
              onChanged: (f) => setState(() => _frequency = f ?? _frequency),
            ),
            if (failure != null) ...[
              const SizedBox(height: Space.x3),
              Text(failure.message, style: TextStyle(color: c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-search-confirm'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// Account → Saved searches: rename, how often to alert, delete, open.
class SavedSearchesScreen extends StatefulWidget {
  const SavedSearchesScreen({super.key});

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  Future<List<SavedSearch>>? _loading;
  List<SavedSearch> _items = const [];
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<List<SavedSearch>> _load() =>
      AppScope.of(context).savedSearches.list().then((items) => _items = items);

  void _replace(SavedSearch next) => setState(() {
    _items = [for (final s in _items) s.id == next.id ? next : s];
  });

  Future<void> _change(
    SavedSearch s, {
    String? name,
    AlertFrequency? frequency,
  }) async {
    setState(() => _failure = null);
    try {
      _replace(
        await AppScope.of(context).savedSearches
            .update(s.id, name: name, frequency: frequency),
      );
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  Future<void> _rename(SavedSearch s) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(name: s.name),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _change(s, name: name);
  }

  Future<void> _delete(SavedSearch s) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${s.name}"?'),
        content: const Text('You will get no more alerts for it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-search-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await AppScope.of(context).savedSearches.delete(s.id);
      if (!mounted) return;
      setState(
        () => _items = [
          for (final x in _items)
            if (x.id != s.id) x,
        ],
      );
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved searches')),
      body: AsyncView<List<SavedSearch>>(
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
    final when = DateFormat('d MMM y, HH:mm');
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Text(
          'We tell you when new listings match a saved search. Each alert '
          'email also has a link to stop alerts for that search.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x4),
        if (_failure != null) ...[
          Text(_failure!.message, style: TextStyle(color: c.danger)),
          const SizedBox(height: Space.x3),
        ],
        if (_items.isEmpty)
          Text(
            'No saved searches yet. Search for property and choose "Save '
            'this search".',
            key: const Key('saved-searches-empty'),
            style: text.bodyLarge,
          ),
        for (final s in _items)
          Padding(
            key: Key('saved-search-${s.id}'),
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: BrandCard(
              onTap: () => context.push(savedSearchRoute(s)),
              semanticLabel:
                  '${s.name}. Alerts: ${s.frequency.label}. Opens the search',
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: text.titleMedium),
                    if (s.lastAlertAt != null)
                      Text(
                        'Last alert ${when.format(s.lastAlertAt!.toLocal())}',
                        style: text.bodyMedium,
                      ),
                    if (s.hasWebOnlyFilters)
                      Text(
                        'Some of its filters, such as price, are only on the '
                        'website. The app opens it without them.',
                        style: text.bodySmall,
                      ),
                    const SizedBox(height: Space.x2),
                    SearchableSelectField<AlertFrequency>(
                      key: Key('saved-search-frequency-${s.id}'),
                      label: 'Alerts',
                      value: s.frequency,
                      options: [
                        for (final f in AlertFrequency.values)
                          SelectOption(f, f.label),
                      ],
                      onChanged: (f) {
                        if (f != null && f != s.frequency) {
                          _change(s, frequency: f);
                        }
                      },
                    ),
                    Wrap(
                      spacing: Space.x2,
                      children: [
                        TextButton(
                          key: Key('saved-search-open-${s.id}'),
                          onPressed: () => context.push(savedSearchRoute(s)),
                          child: const Text('Open'),
                        ),
                        TextButton(
                          key: Key('saved-search-rename-${s.id}'),
                          onPressed: () => _rename(s),
                          child: const Text('Rename'),
                        ),
                        TextButton(
                          key: Key('saved-search-delete-${s.id}'),
                          onPressed: () => _delete(s),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename search'),
    content: TextField(
      key: const Key('rename-search-name'),
      controller: _name,
      maxLength: 80,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('rename-search-confirm'),
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('Rename'),
      ),
    ],
  );
}
