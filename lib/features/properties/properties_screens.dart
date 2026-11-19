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
import '../appointments/appointment_screens.dart' show askForText;
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_repository.dart' show Contact, ContactBook;
import '../markets/data/market.dart';
import 'properties_repository.dart';

final _iso = DateFormat('yyyy-MM-dd');
String day(String iso) => DateFormat('d MMM y').format(DateTime.parse(iso));

/// The status in words; active is the only green one.
class TenancyStatusBadge extends StatelessWidget {
  const TenancyStatusBadge(this.tenancy, {super.key});

  final Tenancy tenancy;

  @override
  Widget build(BuildContext context) => AppBadge(
    tenancy.statusLabel.isEmpty ? tenancy.status : tenancy.statusLabel,
    tone: switch (tenancy.status) {
      'ACTIVE' => BadgeTone.success,
      'DRAFT' => BadgeTone.primary,
      _ => BadgeTone.neutral,
    },
  );
}

/// The dates of a tenancy in words.
String tenancyDates(Tenancy t) {
  final from = 'From ${day(t.startDate)}';
  if (t.endedOn != null) return '$from, ended ${day(t.endedOn!)}';
  if (t.endDate != null) return '$from to ${day(t.endDate!)}';
  return '$from, no end date';
}

/// Properties with their units, and the tenancies, for each book the person
/// works in. Staff read; owners, managers and agents also write.
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  String _view = 'properties';
  String? _status;
  String _query = '';
  Timer? _typing;
  Future<
    ({PropertyPage properties, TenancyPage tenancies, TenancyOptions options})
  >?
  _loading;

  PropertiesRepository get _repo => AppScope.of(context).properties;

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
        final (properties, tenancies, options) = await (
          _repo.properties(book.id, query: _query),
          _repo.tenancies(book.id, status: _status),
          _repo.tenancyOptions(book.id),
        ).wait;
        return (properties: properties, tenancies: tenancies, options: options);
      }();
    });
  }

  Future<void> _newProperty() async {
    final made = await context.push<ManagedProperty>(
      Routes.newProperty(_book!.id),
      extra: _book,
    );
    if (made != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Properties')),
        body: const MessageView(
          icon: Icons.home_work_outlined,
          title: 'No properties to manage',
          body:
              'Properties belong to an organisation or a landlord\'s own book.',
        ),
      );
    }
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final canWrite = data?.options.canWrite ?? false;
        return Scaffold(
          appBar: AppBar(title: const Text('Properties')),
          floatingActionButton: canWrite && _view == 'properties'
              ? FloatingActionButton.extended(
                  key: const Key('add-property'),
                  onPressed: _newProperty,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a property'),
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
                  key: const Key('properties-book'),
                  label: 'Properties of',
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
              SegmentedButton<String>(
                key: const Key('properties-view'),
                segments: const [
                  ButtonSegment(value: 'properties', label: Text('Properties')),
                  ButtonSegment(value: 'tenancies', label: Text('Tenancies')),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              const SizedBox(height: Space.x3),
              if (data != null && !canWrite) ...[
                Text(
                  'You can see these but not change them.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.x2),
              ],
              if (_view == 'properties')
                TextField(
                  key: const Key('properties-search'),
                  decoration: const InputDecoration(
                    labelText: 'Search by name or address',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (q) {
                    _query = q;
                    _typing?.cancel();
                    _typing = Timer(const Duration(milliseconds: 400), _load);
                  },
                )
              else if (data != null)
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    for (final (code, label) in const [
                      (null, 'All'),
                      ('DRAFT', 'Draft'),
                      ('ACTIVE', 'Active'),
                      ('ENDED', 'Ended'),
                      ('TERMINATED', 'Terminated early'),
                    ])
                      ChoiceChip(
                        key: Key('tenancies-status-${code ?? 'all'}'),
                        label: Text(
                          code == null
                              ? label
                              : '$label (${data.tenancies.statusCounts[code] ?? 0})',
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
                  title: 'We could not load these',
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
              else if (_view == 'properties')
                ..._properties(data.properties, book)
              else
                ..._tenancies(data.tenancies, book),
              const SizedBox(height: Space.x4),
              Text(
                'Changing a property\'s details or a tenancy\'s terms, parties '
                'and notes is done on the website.',
                style: text.bodySmall,
              ),
              Align(
                child: TextButton(
                  key: const Key('properties-website'),
                  onPressed: () => AppScope.of(context).openLink(
                    Uri.parse(
                      '${AppConfig.webBaseUrl}/agent/${_view == 'properties' ? 'properties' : 'tenancies'}',
                    ),
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

  List<Widget> _properties(PropertyPage page, ContactBook book) {
    if (page.items.isEmpty) {
      return [
        MessageView(
          icon: Icons.home_work_outlined,
          title: _query.isEmpty ? 'No properties yet' : 'No matches',
          body: _query.isEmpty
              ? 'Add the properties you let, with their flats or units.'
              : 'Try another name or address.',
        ),
      ];
    }
    final text = Theme.of(context).textTheme;
    return [
      for (final p in page.items)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.x3),
          child: BrandCard(
            key: Key('property-${p.id}'),
            semanticLabel: '${p.name}. ${p.address}. ${p.occupancy}',
            onTap: () async {
              await context.push(
                Routes.managedProperty(book.id, p.id),
                extra: book,
              );
              _load();
            },
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: text.titleMedium),
                  Text(p.address, style: text.bodyMedium),
                  const SizedBox(height: Space.x1),
                  AppBadge(
                    p.occupancy,
                    tone: p.occupiedUnits > 0
                        ? BadgeTone.success
                        : BadgeTone.neutral,
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _tenancies(TenancyPage page, ContactBook book) {
    if (page.items.isEmpty) {
      return const [
        MessageView(
          icon: Icons.key_outlined,
          title: 'No tenancies here',
          body: 'Open a property to set up a tenancy for it.',
        ),
      ];
    }
    return [
      for (final t in page.items)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.x3),
          child: TenancyCard(
            t,
            onTap: () async {
              await context.push(Routes.tenancy(book.id, t.id), extra: book);
              _load();
            },
          ),
        ),
    ];
  }
}

class TenancyCard extends StatelessWidget {
  const TenancyCard(this.tenancy, {super.key, this.onTap});

  final Tenancy tenancy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = tenancy;
    final tenants = t.tenants.map((p) => p.name).join(', ');
    return BrandCard(
      key: Key('tenancy-${t.id}'),
      onTap: onTap,
      semanticLabel:
          '${t.place}. ${t.statusLabel}. $tenants. ${t.rent}. ${tenancyDates(t)}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.place, style: text.titleMedium),
            if (tenants.isNotEmpty) Text(tenants, style: text.bodyMedium),
            Text(t.rent.toString(), style: text.bodyMedium),
            Text(tenancyDates(t), style: text.bodySmall),
            const SizedBox(height: Space.x1),
            TenancyStatusBadge(t),
          ],
        ),
      ),
    );
  }
}

/// A new property: name, address, market and its units.
class NewPropertyScreen extends StatefulWidget {
  const NewPropertyScreen({super.key, required this.book});

  final ContactBook book;

  @override
  State<NewPropertyScreen> createState() => _NewPropertyScreenState();
}

class _NewPropertyScreenState extends State<NewPropertyScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _units = <TextEditingController>[];
  String _market = 'ZW';
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final made = await AppScope.of(context).properties.createProperty(
        widget.book.id,
        name: _name.text,
        address: _address.text,
        marketCode: _market,
        units: [for (final u in _units) u.text],
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
      appBar: AppBar(title: const Text('Add a property')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            TextFormField(
              key: const Key('property-name'),
              controller: _name,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Name, for example Avondale Court',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Give the property a name.' : null,
            ),
            TextFormField(
              key: const Key('property-address'),
              controller: _address,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the address.' : null,
            ),
            SearchableSelectField<String>(
              key: const Key('property-market'),
              label: 'Country',
              value: _market,
              options: [for (final m in markets) SelectOption(m.code, m.name)],
              onChanged: (code) => setState(() => _market = code ?? 'ZW'),
            ),
            const SizedBox(height: Space.x4),
            Text('Units', style: text.titleSmall),
            Text(
              'Flats, rooms or units let separately. Leave none for a house '
              'let as a whole.',
              style: text.bodySmall,
            ),
            for (final (i, u) in _units.indexed)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: Key('property-unit-$i'),
                      controller: u,
                      maxLength: 80,
                      decoration: InputDecoration(labelText: 'Unit ${i + 1}'),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Name the unit or remove it.'
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove unit ${i + 1}',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _units.removeAt(i)),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('property-add-unit'),
                onPressed: () =>
                    setState(() => _units.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Add a unit'),
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('property-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Add the property'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One property: its units, who lets them, and its tenancies.
class ManagedPropertyScreen extends StatefulWidget {
  const ManagedPropertyScreen({
    super.key,
    required this.book,
    required this.id,
  });

  final ContactBook book;
  final String id;

  @override
  State<ManagedPropertyScreen> createState() => _ManagedPropertyScreenState();
}

class _ManagedPropertyScreenState extends State<ManagedPropertyScreen> {
  Future<
    ({ManagedProperty property, TenancyPage tenancies, TenancyOptions options})
  >?
  _loading;
  ApiFailure? _failure;
  bool _busy = false;

  PropertiesRepository get _repo => AppScope.of(context).properties;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<
    ({ManagedProperty property, TenancyPage tenancies, TenancyOptions options})
  >
  _get() async {
    final b = widget.book.id;
    final (property, tenancies, options) = await (
      _repo.property(b, widget.id),
      _repo.tenancies(b, propertyId: widget.id),
      _repo.tenancyOptions(b),
    ).wait;
    return (property: property, tenancies: tenancies, options: options);
  }

  void _reload() => setState(() {
    _loading = _get();
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
      _reload();
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addUnit() async {
    final label = await askForText(
      context,
      title: 'Add a unit',
      label: 'For example Flat 4',
      action: 'Add',
      required: true,
      maxLength: 80,
    );
    if (label == null || label.trim().isEmpty) return;
    await _run(() => _repo.addUnit(widget.book.id, widget.id, label));
  }

  Future<void> _removeUnit(PropertyUnit unit) => _run(() async {
    try {
      await _repo.removeUnit(widget.book.id, widget.id, unit.id);
    } on ApiFailure catch (failure) {
      if (failure.code == 'UNIT_IN_USE') {
        throw failure.withMessage(
          '${unit.label} has a draft or active tenancy, so it stays.',
        );
      }
      rethrow;
    }
  });

  Future<void> _archive() async {
    final router = GoRouter.of(context);
    await _run(() async {
      await _repo.deleteProperty(widget.book.id, widget.id);
      router.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Property')),
      body: AsyncView(
        future: _loading!,
        onRetry: _reload,
        builder: (context, data) {
          final p = data.property;
          final write = data.options.canWrite;
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text(p.name, style: text.headlineSmall),
              Text(p.address, style: text.bodyLarge),
              if (p.listingTitle != null)
                Text(
                  'Listing: ${p.listingTitle} (${p.listingReference ?? ''})',
                  style: text.bodySmall,
                ),
              const SizedBox(height: Space.x2),
              AppBadge(
                p.occupancy,
                tone: p.occupiedUnits > 0
                    ? BadgeTone.success
                    : BadgeTone.neutral,
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              const SectionHeading('Units'),
              const SizedBox(height: Space.x2),
              if (p.units.isEmpty)
                Text(
                  'No units: the property is let as a whole.',
                  style: text.bodyMedium,
                ),
              for (final u in p.units)
                ListTile(
                  key: Key('unit-${u.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(u.label),
                  subtitle: Text(u.occupied ? 'Let' : 'Vacant'),
                  trailing: write && !u.occupied
                      ? IconButton(
                          key: Key('remove-unit-${u.id}'),
                          tooltip: 'Remove ${u.label}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _removeUnit(u),
                        )
                      : null,
                ),
              if (write)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add-unit'),
                    onPressed: _busy ? null : _addUnit,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a unit'),
                  ),
                ),
              const SizedBox(height: Space.x4),
              const SectionHeading('Tenancies'),
              const SizedBox(height: Space.x2),
              if (data.tenancies.items.isEmpty)
                Text('No tenancies yet.', style: text.bodyMedium),
              for (final t in data.tenancies.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x3),
                  child: TenancyCard(
                    t,
                    onTap: () async {
                      await context.push(
                        Routes.tenancy(widget.book.id, t.id),
                        extra: widget.book,
                      );
                      _reload();
                    },
                  ),
                ),
              if (write) ...[
                const SizedBox(height: Space.x2),
                FilledButton.icon(
                  key: const Key('new-tenancy'),
                  onPressed: () async {
                    final made = await context.push<Tenancy>(
                      Routes.newTenancy(widget.book.id, p.id),
                      extra: (
                        book: widget.book,
                        property: p,
                        options: data.options,
                      ),
                    );
                    if (made != null && context.mounted) {
                      _reload();
                      unawaited(
                        context.push(
                          Routes.tenancy(widget.book.id, made.id),
                          extra: widget.book,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Set up a tenancy'),
                ),
              ],
              if (write && p.canDelete) ...[
                const SizedBox(height: Space.x2),
                OutlinedButton(
                  key: const Key('archive-property'),
                  onPressed: _busy ? null : _archive,
                  child: const Text('Remove this property'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Picks a CRM contact of the book, searching as the person types.
Future<Contact?> pickContact(
  BuildContext context, {
  required ContactBook book,
  required String title,
  Set<String> exclude = const {},
}) => showModalBottomSheet<Contact>(
  context: context,
  isScrollControlled: true,
  builder: (context) =>
      _ContactPicker(book: book, title: title, exclude: exclude),
);

class _ContactPicker extends StatefulWidget {
  const _ContactPicker({
    required this.book,
    required this.title,
    required this.exclude,
  });

  final ContactBook book;
  final String title;
  final Set<String> exclude;

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  Future<List<Contact>>? _results;
  Timer? _typing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= _search('');
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  Future<List<Contact>> _search(String q) async => (await AppScope.of(
    context,
  ).contacts.list(widget.book.id, query: q)).items;

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
                  Text(widget.title, style: text.titleMedium),
                  const SizedBox(height: Space.x2),
                  TextField(
                    key: const Key('contact-search'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Search your contacts',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (q) {
                      _typing?.cancel();
                      _typing = Timer(const Duration(milliseconds: 300), () {
                        setState(() => _results = _search(q));
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Contact>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const MessageView(
                      icon: Icons.cloud_off_outlined,
                      title: 'We could not search your contacts',
                      body: 'Check your connection and try again.',
                    );
                  }
                  final items = [
                    for (final c in snapshot.data ?? const <Contact>[])
                      if (!widget.exclude.contains(c.id)) c,
                  ];
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return const MessageView(
                      icon: Icons.person_search_outlined,
                      title: 'No matching contacts',
                      body: 'Add the person to your contacts first.',
                    );
                  }
                  return ListView(
                    children: [
                      for (final c in items)
                        ListTile(
                          key: Key('pick-contact-${c.id}'),
                          title: Text(c.name),
                          subtitle: Text(c.typeLabel),
                          onTap: () => Navigator.of(context).pop(c),
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

/// Sets up a tenancy as a draft: who, where, the rent and the dates. It is
/// made active separately, once everything is agreed.
class NewTenancyScreen extends StatefulWidget {
  const NewTenancyScreen({
    super.key,
    required this.book,
    required this.property,
    required this.options,
  });

  final ContactBook book;
  final ManagedProperty property;
  final TenancyOptions options;

  @override
  State<NewTenancyScreen> createState() => _NewTenancyScreenState();
}

class _NewTenancyScreenState extends State<NewTenancyScreen> {
  final _form = GlobalKey<FormState>();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _notes = TextEditingController();
  final _tenants = <Contact>[];
  final _landlords = <Contact>[];
  String? _unit;
  late String _currency = widget.options.currencies.containsKey('USD')
      ? 'USD'
      : (widget.options.currencies.keys.firstOrNull ?? 'USD');
  String _frequency = 'MONTHLY';
  int _dueDay = 1;
  DateTime _start = DateTime.now();
  DateTime? _end;
  bool _saving = false;
  String? _partiesProblem;
  ApiFailure? _failure;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void dispose() {
    _rent.dispose();
    _deposit.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add(List<Contact> into, String title) async {
    final picked = await pickContact(
      context,
      book: widget.book,
      title: title,
      exclude: {
        for (final c in [..._tenants, ..._landlords]) c.id,
      },
    );
    if (picked != null) {
      setState(() {
        into.add(picked);
        _partiesProblem = null;
      });
    }
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    if (_tenants.isEmpty) {
      setState(() => _partiesProblem = 'Add at least one tenant.');
    }
    if (!valid || _tenants.isEmpty) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final made = await AppScope.of(context).properties.createTenancy(
        widget.book.id,
        TenancyDraft(
          propertyId: widget.property.id,
          unitId: _unit,
          tenantIds: [for (final c in _tenants) c.id],
          landlordIds: [for (final c in _landlords) c.id],
          rentAmount: _rent.text,
          currency: _currency,
          frequency: _frequency,
          dueDay: _dueDay,
          depositAmount: _deposit.text,
          startDate: _iso.format(_start),
          endDate: _end == null ? null : _iso.format(_end!),
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(made);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _parties(String heading, List<Contact> list, String add, Key key) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: text.titleSmall),
        for (final c in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(c.name),
            trailing: IconButton(
              tooltip: 'Remove ${c.name}',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => list.remove(c)),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: key,
            onPressed: () => _add(list, add),
            icon: const Icon(Icons.person_add_alt),
            label: Text(add),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final p = widget.property;
    final o = widget.options;
    final weekly = _frequency == 'WEEKLY';
    return Scaffold(
      appBar: AppBar(title: const Text('Set up a tenancy')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(
              'Saved as a draft. Make it active once it is agreed; the rent '
              'terms are fixed from then on.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.x3),
            Text(p.name, style: text.titleMedium),
            Text(p.address, style: text.bodySmall),
            const SizedBox(height: Space.x3),
            if (p.units.isNotEmpty) ...[
              SearchableSelectField<String>(
                key: const Key('tenancy-unit'),
                label: 'Unit',
                value: _unit,
                options: [
                  for (final u in p.units)
                    SelectOption(
                      u.id,
                      u.occupied ? '${u.label} (let)' : u.label,
                    ),
                ],
                onChanged: (id) => setState(() => _unit = id),
                validator: (v) => v == null ? 'Choose the unit.' : null,
              ),
              const SizedBox(height: Space.x3),
            ],
            _parties(
              'Tenants',
              _tenants,
              'Add a tenant',
              const Key('tenancy-add-tenant'),
            ),
            if (_partiesProblem != null)
              Text(
                _partiesProblem!,
                style: text.bodySmall?.copyWith(color: c.danger),
              ),
            Text(
              'A tenant whose contact has the email address they confirmed '
              'on RightProperty365 sees this tenancy in their app.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Space.x3),
            _parties(
              'Landlords (optional)',
              _landlords,
              'Add a landlord',
              const Key('tenancy-add-landlord'),
            ),
            const SizedBox(height: Space.x3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('tenancy-rent'),
                    controller: _rent,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Rent'),
                    validator: (v) => o.amountProblem(v ?? '', _currency),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  flex: 2,
                  child: SearchableSelectField<String>(
                    key: const Key('tenancy-currency'),
                    label: 'Currency',
                    value: _currency,
                    options: [
                      for (final code in o.currencies.keys)
                        SelectOption(code, code),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x3),
            SearchableSelectField<String>(
              key: const Key('tenancy-frequency'),
              label: 'Paid',
              value: _frequency,
              options: [
                for (final e in o.frequencies.entries)
                  SelectOption(e.key, e.value),
              ],
              onChanged: (v) => setState(() {
                _frequency = v ?? 'MONTHLY';
                _dueDay = 1;
              }),
            ),
            const SizedBox(height: Space.x3),
            SearchableSelectField<int>(
              key: Key('tenancy-due-day-$_frequency'),
              label: weekly ? 'Due on' : 'Due on day of the month',
              value: _dueDay,
              options: [
                if (weekly)
                  for (final (i, d) in _weekdays.indexed) SelectOption(i + 1, d)
                else
                  for (var d = 1; d <= 31; d++)
                    SelectOption(
                      d,
                      d > 28 ? '$d (the last day in shorter months)' : '$d',
                    ),
              ],
              onChanged: (v) => setState(() => _dueDay = v ?? 1),
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('tenancy-deposit'),
              controller: _deposit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Deposit in $_currency (optional)',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? null
                  : o.amountProblem(v!, _currency),
            ),
            const SizedBox(height: Space.x3),
            OutlinedButton.icon(
              key: const Key('tenancy-start'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setState(() => _start = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Starts ${DateFormat('d MMMM y').format(_start)}'),
            ),
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('tenancy-end'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _end ?? _start.add(const Duration(days: 364)),
                      firstDate: _start,
                      lastDate: _start.add(const Duration(days: 3650 * 3)),
                    );
                    if (picked != null) setState(() => _end = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _end == null
                        ? 'Agreed end date (optional)'
                        : 'Ends ${DateFormat('d MMMM y').format(_end!)}',
                  ),
                ),
                if (_end != null)
                  TextButton(
                    onPressed: () => setState(() => _end = null),
                    child: const Text('No end date'),
                  ),
              ],
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('tenancy-notes'),
              controller: _notes,
              maxLength: 5000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes for your team (optional)',
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('tenancy-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save as a draft'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tenancy for the people who manage it: the parties, rent and dates,
/// and making it active, ending it or deleting a draft.
class TenancyScreen extends StatefulWidget {
  const TenancyScreen({super.key, required this.book, required this.id});

  final ContactBook book;
  final String id;

  @override
  State<TenancyScreen> createState() => _TenancyScreenState();
}

class _TenancyScreenState extends State<TenancyScreen> {
  Future<Tenancy>? _loading;
  ApiFailure? _failure;
  bool _busy = false;
  String? _done;

  PropertiesRepository get _repo => AppScope.of(context).properties;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _repo.tenancy(widget.book.id, widget.id);
  }

  Future<void> _run(Future<Tenancy?> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
      _done = null;
    });
    try {
      final t = await action();
      if (!mounted) return;
      setState(() {
        if (t != null) _loading = Future.value(t);
        _done = done;
      });
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(Tenancy t) async {
    final date = await showDatePicker(
      context: context,
      helpText: 'Last day of the tenancy',
      initialDate: DateTime.now(),
      firstDate: DateTime.parse(t.startDate),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final reason = await askForText(
      context,
      title: 'End the tenancy',
      label: 'Why it is ending',
      action: 'End the tenancy',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _repo.end(
        widget.book.id,
        t.id,
        endDate: _iso.format(date),
        reason: reason,
      ),
      'The tenancy has ended.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tenancy')),
      body: AsyncView<Tenancy>(
        future: _loading!,
        onRetry: () => setState(() {
          _loading = _repo.tenancy(widget.book.id, widget.id);
        }),
        builder: (context, t) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            TenancyDetails(t),
            if (t.notes.isNotEmpty) ...[
              const SizedBox(height: Space.x3),
              Text('Notes', style: text.titleSmall),
              Text(t.notes, style: text.bodyMedium),
            ],
            if (_done != null) ...[
              const SizedBox(height: Space.x3),
              Text(_done!, style: text.bodyMedium),
            ],
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            if (t.canActivate)
              FilledButton(
                key: const Key('tenancy-activate'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _repo.activate(widget.book.id, t.id),
                        'The tenancy is active.',
                      ),
                child: const Text('Make it active'),
              ),
            if (t.canEnd)
              OutlinedButton(
                key: const Key('tenancy-end-now'),
                onPressed: _busy ? null : () => _end(t),
                child: const Text('End the tenancy'),
              ),
            if (t.canDelete) ...[
              const SizedBox(height: Space.x2),
              TextButton(
                key: const Key('tenancy-delete'),
                onPressed: _busy
                    ? null
                    : () {
                        final router = GoRouter.of(context);
                        _run(() async {
                          await _repo.deleteTenancy(widget.book.id, t.id);
                          router.pop();
                          return null;
                        }, 'Deleted.');
                      },
                child: const Text('Delete this draft'),
              ),
            ],
            const SizedBox(height: Space.x4),
            Text(
              'The rent terms are fixed once a tenancy is active. Parties, '
              'the deposit, the agreed end date and notes are changed on the '
              'website.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// What a tenancy says, for the manager and for the tenant alike.
class TenancyDetails extends StatelessWidget {
  const TenancyDetails(this.tenancy, {super.key});

  final Tenancy tenancy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = tenancy;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelLarge),
          Text(value, style: text.bodyLarge),
        ],
      ),
    );
    String names(List<PartyRef> parties) => parties
        .map((p) => p.live ? p.name : '${p.name} (no longer in contacts)')
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.place, style: text.headlineSmall),
        Text(
          t.propertyArchived
              ? '${t.propertyAddress} (property removed)'
              : t.propertyAddress,
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x2),
        TenancyStatusBadge(t),
        const SizedBox(height: Space.x3),
        if (t.managedBy != null) row('Managed by', t.managedBy!),
        if (t.tenants.isNotEmpty) row('Tenants', names(t.tenants)),
        if (t.landlords.isNotEmpty) row('Landlords', names(t.landlords)),
        row('Rent', t.rent.toString()),
        if (t.deposit != null) row('Deposit', t.deposit.toString()),
        row('Dates', tenancyDates(t)),
        if (t.endReason != null) row('Why it ended', t.endReason!),
        if (t.leaseReference != null) row('Lease', t.leaseReference!),
      ],
    );
  }
}
