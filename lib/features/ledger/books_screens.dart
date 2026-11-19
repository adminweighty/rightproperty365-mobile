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
import '../applications/applications_repository.dart' show ChosenFile;
import 'ledger_repository.dart';

final _iso = DateFormat('yyyy-MM-dd');
String _day(String iso) => DateFormat('d MMM y').format(DateTime.parse(iso));

/// The status in words. Never suggests a bank or anyone else verified it.
class EntryStatusBadge extends StatelessWidget {
  const EntryStatusBadge(this.entry, {super.key});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) => AppBadge(
    entry.statusLabel,
    tone: entry.reconciled ? BadgeTone.success : BadgeTone.neutral,
  );
}

/// The organisation's own cashbook: per-currency totals for a period (one
/// table per currency, never combined), the entries with a running balance
/// when one currency is chosen, and recording and reversing entries.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  String _period = 'month';
  String? _currency;
  String? _type;
  Future<
    (
      LedgerOptions,
      List<CashbookCurrency>,
      ({List<LedgerEntry> items, int total}),
    )
  >?
  _loading;

  LedgerRepository get _repo => AppScope.of(context).ledger;

  ({String from, String to}) get _range {
    final now = DateTime.now();
    final from = switch (_period) {
      'last' => DateTime(now.year, now.month - 1),
      'year' => DateTime(now.year),
      _ => DateTime(now.year, now.month),
    };
    final to = _period == 'last' ? DateTime(now.year, now.month, 0) : now;
    return (from: _iso.format(from), to: _iso.format(to));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading == null) _load();
  }

  void _load() {
    final book = _book;
    if (book == null) return;
    final r = _range;
    final next = () async {
      final results = await Future.wait([
        _repo.options(book.id),
        _repo.cashbook(book.id, from: r.from, to: r.to, currency: _currency),
        _repo.entries(
          book.id,
          currency: _currency,
          type: _type,
          from: r.from,
          to: r.to,
        ),
      ]);
      return (
        results[0] as LedgerOptions,
        results[1] as List<CashbookCurrency>,
        results[2] as ({List<LedgerEntry> items, int total}),
      );
    }();
    setState(() {
      _loading = next;
    });
  }

  Future<void> _record(LedgerOptions options) async {
    final created = await context.push<bool>(
      Routes.newLedgerEntry(_book!.id),
      extra: (book: _book!, options: options),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Books')),
        body: const MessageView(
          icon: Icons.lock_outline,
          title: 'No books on this account',
          body: 'Books open for agencies, businesses and approved landlords and sellers.',
        ),
      );
    }
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final options = data?.$1;
        return Scaffold(
          appBar: AppBar(title: const Text('Books')),
          floatingActionButton: options?.canWrite == true
              ? FloatingActionButton.extended(
                  key: const Key('record-entry'),
                  onPressed: () => _record(options!),
                  icon: const Icon(Icons.add),
                  label: const Text('Record an entry'),
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
              Text(
                'Your organisation\'s own books. Separate from your RightProperty365 subscription '
                'invoices. Entries you record are marked "Recorded by you, not verified".',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.x3),
              if (widget.books.length > 1) ...[
                SearchableSelectField<String>(
                  key: const Key('books-book'),
                  label: 'Books of',
                  value: book.id,
                  options: [
                    for (final b in widget.books) SelectOption(b.id, b.name),
                  ],
                  onChanged: (id) {
                    _book = widget.books.firstWhere((b) => b.id == id);
                    _currency = null;
                    _load();
                  },
                ),
                const SizedBox(height: Space.x3),
              ],
              SegmentedButton<String>(
                key: const Key('books-period'),
                segments: const [
                  ButtonSegment(value: 'month', label: Text('This month')),
                  ButtonSegment(value: 'last', label: Text('Last month')),
                  ButtonSegment(value: 'year', label: Text('This year')),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _period = s.first;
                  _load();
                },
              ),
              const SizedBox(height: Space.x3),
              if (options != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (_) => SearchableSelectField<String>(
                        key: Key('books-currency-$_currency'),
                        label: 'Currency',
                        anyLabel: 'Every currency',
                        value: _currency,
                        options: [
                          for (final c in options.currencies.keys)
                            SelectOption(c, c),
                        ],
                        onChanged: (c) {
                          _currency = c;
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(height: Space.x2),
                    Builder(
                      builder: (_) => SearchableSelectField<String>(
                        key: Key('books-type-$_type'),
                        label: 'Type',
                        anyLabel: 'Every type',
                        value: _type,
                        options: [
                          for (final t in options.types)
                            SelectOption(t.code, t.label),
                          const SelectOption('REVERSAL', 'Reversal'),
                        ],
                        onChanged: (t) {
                          _type = t;
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: Space.x4),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.error != null)
                Text(
                  snapshot.error is ApiFailure &&
                          (snapshot.error as ApiFailure).status == 404
                      ? 'These books are not open to your account.'
                      : 'We could not load the books.',
                  style: text.titleMedium,
                )
              else ...[
                for (final c in data!.$2) _CurrencyTotals(c),
                if (data.$2.isEmpty)
                  Text(
                    'No money in or out in this period.',
                    style: text.bodyLarge,
                  ),
                const SizedBox(height: Space.x4),
                SectionHeading(
                  data.$3.total == 1 ? '1 entry' : '${data.$3.total} entries',
                ),
                const SizedBox(height: Space.x2),
                for (final e in data.$3.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _EntryCard(
                      e,
                      // A running balance only makes sense in one currency.
                      balance: _currency == null
                          ? null
                          : data.$2
                                .where((c) => c.currency == e.currency)
                                .firstOrNull
                                ?.runningBalance[e.id],
                      onTap: () async {
                        await context.push(
                          Routes.ledgerEntry(book.id, e.id),
                          extra: book,
                        );
                        if (mounted) _load();
                      },
                    ),
                  ),
                const SizedBox(height: Space.x3),
                Text(
                  'Reports (categories, statements, money owed) and corrections are on the website'
                  '${data.$1.canExport ? ', and so are exports' : ''}.',
                  style: text.bodySmall,
                ),
                TextButton(
                  onPressed: () => AppScope.of(
                    context,
                  ).openLink(Uri.parse('${AppConfig.webBaseUrl}/agent/books')),
                  child: const Text('Open the books on the website'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CurrencyTotals extends StatelessWidget {
  const _CurrencyTotals(this.totals);

  final CashbookCurrency totals;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final t = totals;
    Widget row(String label, String amount, {bool strong = false}) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: Space.x2,
      children: [
        Text(label, style: strong ? text.titleMedium : text.bodyLarge),
        Text(
          '${t.currency} $amount',
          style: strong ? text.titleMedium : text.bodyLarge,
        ),
      ],
    );
    return Semantics(
      container: true,
      label:
          '${t.currency}: opening ${t.opening}, in ${t.moneyIn}, out ${t.moneyOut}, closing ${t.closing}',
      excludeSemantics: true,
      child: Container(
        key: Key('totals-${t.currency}'),
        margin: const EdgeInsets.only(bottom: Space.x3),
        padding: const EdgeInsets.all(Space.x4),
        decoration: BoxDecoration(
          color: c.sunken,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.currency, style: text.titleLarge),
            const SizedBox(height: Space.x1),
            row('Opening balance', t.opening),
            row('Money in', t.moneyIn),
            row('Money out', t.moneyOut),
            const Divider(),
            row('Closing balance', t.closing, strong: true),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry, {required this.onTap, this.balance});

  final LedgerEntry entry;
  final VoidCallback onTap;
  final String? balance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final e = entry;
    final out = e.signedAmount.startsWith('-');
    final title = e.description?.isNotEmpty == true
        ? e.description!
        : e.typeLabel;
    return BrandCard(
      key: Key('entry-${e.id}'),
      onTap: onTap,
      semanticLabel:
          '$title. ${e.typeLabel}. ${e.currency} ${e.signedAmount}. ${_day(e.effectiveDate)}. ${e.statusLabel}'
          '${e.isReversed ? '. Reversed' : ''}',
      child: Opacity(
        opacity: e.isReversed ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: Space.x2,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(
                    '${e.currency} ${e.signedAmount}',
                    style: text.titleMedium?.copyWith(
                      color: out ? c.danger : c.success,
                      decoration: e.isReversed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ],
              ),
              Text(
                [
                  e.typeLabel,
                  ?e.categoryLabel,
                  ?e.methodLabel,
                  _day(e.effectiveDate),
                ].join(' · '),
                style: text.bodyMedium,
              ),
              if (!e.cash)
                Text(
                  'Owed, not yet paid: no balance moves',
                  style: text.bodySmall,
                ),
              if (e.isReversal && e.reason != null)
                Text('Reversal: ${e.reason}', style: text.bodySmall),
              if (e.isReversed) Text('Reversed', style: text.bodySmall),
              const SizedBox(height: Space.x1),
              Wrap(
                spacing: Space.x3,
                runSpacing: Space.x1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  EntryStatusBadge(e),
                  if (balance != null)
                    Text(
                      'Balance ${e.currency} $balance',
                      style: text.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recording an entry. It is posted at once and can only be undone by a
/// reversal; a receipt can be added straight after.
class NewLedgerEntryScreen extends StatefulWidget {
  const NewLedgerEntryScreen({
    super.key,
    required this.book,
    required this.options,
  });

  final ContactBook book;
  final LedgerOptions options;

  @override
  State<NewLedgerEntryScreen> createState() => _NewLedgerEntryScreenState();
}

class _NewLedgerEntryScreenState extends State<NewLedgerEntryScreen> {
  late String _type = widget.options.types.firstOrNull?.code ?? 'INCOME';
  String _direction = 'IN';
  String? _category;
  late String? _method = widget.options.methods.firstOrNull?.code;
  String? _transferTo;
  late String _currency = widget.options.currencies.containsKey('USD')
      ? 'USD'
      : widget.options.currencies.keys.firstOrNull ?? 'USD';
  DateTime _date = DateTime.now();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  ChosenFile? _receipt;
  bool _busy = false;
  bool _tried = false;
  ApiFailure? _failure;

  ({String code, String label, String? direction, bool cash, String? category})?
  get _typeSpec =>
      widget.options.types.where((t) => t.code == _type).firstOrNull;

  String get _effectiveDirection =>
      _typeSpec?.direction ?? (_type == 'TRANSFER' ? 'OUT' : _direction);

  bool get _memo => _type == 'RECEIVABLE' || _type == 'PAYABLE';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt(bool camera) async {
    final picked = await AppScope.of(context).pickApplicationFile(
      camera: camera,
      accept: const ['pdf', 'jpg', 'png', 'webp'],
    );
    if (picked != null && mounted) setState(() => _receipt = picked);
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    final amountProblem = widget.options.amountProblem(_amount.text, _currency);
    if (amountProblem != null || (_type == 'TRANSFER' && _transferTo == null)) {
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final repo = AppScope.of(context).ledger;
    try {
      final entry = await repo.create(
        widget.book.id,
        LedgerDraft(
          type: _type,
          direction: _typeSpec?.direction == null && _type == 'OPENING_BALANCE'
              ? _direction
              : null,
          category: _category,
          method: _memo ? null : _method,
          transferToMethod: _transferTo,
          amount: _amount.text,
          currency: _currency,
          effectiveDate: _iso.format(_date),
          description: _description.text,
          reference: _reference.text,
        ),
      );
      final receipt = _receipt;
      if (receipt != null) {
        try {
          await repo.attach(widget.book.id, entry.id, receipt);
        } on ApiFailure catch (failure) {
          // The entry is posted; say the receipt did not go, and stay.
          if (mounted) {
            setState(
              () => _failure = failure.withMessage(
                'The entry is recorded, but the receipt was not added: ${failure.message} '
                'Add it from the entry.',
              ),
            );
          }
          return;
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.options;
    final fields = _failure?.fields ?? const {};
    final direction = _effectiveDirection;
    final categories = [
      for (final c in o.categories)
        if (c.kind == 'ANY' || c.kind == direction) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Record an entry')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Text(
            'Recorded by you, not verified. A recorded entry cannot be edited or deleted; '
            'a mistake is put right by reversing it.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.x4),
          SearchableSelectField<String>(
            key: const Key('entry-type'),
            label: 'Type',
            value: _type,
            options: [for (final t in o.types) SelectOption(t.code, t.label)],
            onChanged: (v) => setState(() {
              _type = v ?? _type;
              _category = null;
            }),
          ),
          if (_type == 'OPENING_BALANCE') ...[
            const SizedBox(height: Space.x3),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'IN', label: Text('Money held')),
                ButtonSegment(value: 'OUT', label: Text('Overdrawn')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
          ],
          const SizedBox(height: Space.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('entry-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    errorText: _tried
                        ? o.amountProblem(_amount.text, _currency) ??
                              fields['amount']
                        : fields['amount'],
                  ),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                flex: 2,
                child: SearchableSelectField<String>(
                  key: const Key('entry-currency'),
                  label: 'Currency',
                  value: _currency,
                  options: [
                    for (final c in o.currencies.keys) SelectOption(c, c),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? _currency),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          if (!_memo)
            SearchableSelectField<String>(
              key: const Key('entry-method'),
              label: _type == 'TRANSFER' ? 'From' : 'Paid by',
              value: _method,
              options: [
                for (final m in o.methods) SelectOption(m.code, m.label),
              ],
              onChanged: (v) => setState(() => _method = v),
            ),
          if (_type == 'TRANSFER') ...[
            const SizedBox(height: Space.x3),
            SearchableSelectField<String>(
              key: const Key('entry-transfer-to'),
              label: 'To',
              value: _transferTo,
              options: [
                for (final m in o.methods)
                  if (m.code != _method) SelectOption(m.code, m.label),
              ],
              helperText: _tried && _transferTo == null
                  ? 'Choose where the money went.'
                  : null,
              onChanged: (v) => setState(() => _transferTo = v),
            ),
          ],
          if (_type != 'TRANSFER' && _type != 'OPENING_BALANCE') ...[
            const SizedBox(height: Space.x3),
            SearchableSelectField<String>(
              key: Key('entry-category-$_type'),
              label: 'Category',
              anyLabel: _typeSpec?.category == null ? null : 'The usual one',
              value: _category,
              options: [
                for (final c in categories) SelectOption(c.code, c.label),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ],
          const SizedBox(height: Space.x3),
          OutlinedButton.icon(
            key: const Key('entry-date'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 366)),
              );
              if (picked != null) setState(() => _date = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Date: ${DateFormat('d MMMM y').format(_date)}'),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('entry-description'),
            controller: _description,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Description',
              errorText: fields['description'],
            ),
          ),
          TextField(
            key: const Key('entry-reference'),
            controller: _reference,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Receipt or reference number (optional)',
            ),
          ),
          if (!_memo) ...[
            Text('Receipt (optional)', style: text.titleSmall),
            if (_receipt != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(_receipt!.name),
                trailing: IconButton(
                  tooltip: 'Remove the receipt',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _receipt = null),
                ),
              )
            else
              Wrap(
                spacing: Space.x2,
                children: [
                  TextButton.icon(
                    key: const Key('receipt-camera'),
                    onPressed: () => _pickReceipt(true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Photograph it'),
                  ),
                  TextButton.icon(
                    key: const Key('receipt-file'),
                    onPressed: () => _pickReceipt(false),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose a file'),
                  ),
                ],
              ),
          ],
          if (_failure != null) ...[
            const SizedBox(height: Space.x3),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('entry-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Record the entry'),
          ),
        ],
      ),
    );
  }
}

/// One entry: its details, status, what it is linked to (a reversal, a
/// correction, a transfer's other leg), notes and receipts, and Reverse.
class LedgerEntryScreen extends StatefulWidget {
  const LedgerEntryScreen({super.key, required this.book, required this.id});

  final ContactBook book;
  final String id;

  @override
  State<LedgerEntryScreen> createState() => _LedgerEntryScreenState();
}

class _LedgerEntryScreenState extends State<LedgerEntryScreen> {
  Future<LedgerEntryDetail>? _loading;
  ApiFailure? _failure;
  bool _busy = false;

  LedgerRepository get _repo => AppScope.of(context).ledger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _repo.entry(widget.book.id, widget.id);
  }

  void _reload() => setState(() {
    _loading = _repo.entry(widget.book.id, widget.id);
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

  Future<void> _reverse(LedgerEntry e) async {
    final reason = await askForText(
      context,
      title: 'Reverse this entry?',
      label: 'Why (kept with both entries)',
      action: 'Reverse',
      required: true,
    );
    if (reason == null || !mounted) return;
    await _run(
      () => _repo.reverse(widget.book.id, e.id, reason),
      e.transferPair == null
          ? 'Reversed. Both entries stay in the books.'
          : 'Reversed, with the other side of the transfer.',
    );
  }

  Future<void> _addReceipt(bool camera) async {
    final picked = await AppScope.of(context).pickApplicationFile(
      camera: camera,
      accept: const ['pdf', 'jpg', 'png', 'webp'],
    );
    if (picked == null || !mounted) return;
    await _run(
      () => _repo.attach(widget.book.id, widget.id, picked),
      'Receipt added.',
    );
  }

  Future<void> _note() async {
    final text = await askForText(
      context,
      title: 'Add a note',
      label: 'Notes cannot be edited',
      action: 'Add note',
      required: true,
    );
    if (text == null || !mounted) return;
    await _run(
      () => _repo.addNote(widget.book.id, widget.id, text),
      'Note added.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stamp = DateFormat('d MMM y, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Entry')),
      body: AsyncView<LedgerEntryDetail>(
        future: _loading!,
        onRetry: _reload,
        builder: (context, d) {
          final e = d.entry;
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${e.currency} ${e.signedAmount}',
                  style: text.headlineMedium,
                ),
              ),
              Text(
                e.description?.isNotEmpty == true
                    ? e.description!
                    : e.typeLabel,
                style: text.titleMedium,
              ),
              Text(
                [
                  e.typeLabel,
                  ?e.categoryLabel,
                  ?e.methodLabel,
                  _day(e.effectiveDate),
                ].join(' · '),
                style: text.bodyMedium,
              ),
              if (e.reference != null) Text('Reference ${e.reference}'),
              if (e.contactName != null) Text('Contact: ${e.contactName}'),
              if (e.listingTitle != null) Text('Property: ${e.listingTitle}'),
              if (e.authorName != null) Text('Recorded by ${e.authorName}'),
              const SizedBox(height: Space.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: EntryStatusBadge(e),
              ),
              if (e.reconciled)
                Text(
                  'Your team marked this as matching its own statement'
                  '${e.reconciledBy == null ? '' : ' (${e.reconciledBy})'}'
                  '${e.reconciledNote == null ? '' : ': ${e.reconciledNote}'}.',
                  style: text.bodySmall,
                ),
              if (e.reason != null)
                Text('Reason: ${e.reason}', style: text.bodyLarge),
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x3),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  if (e.canReverse && !e.isReversed && !e.isReversal)
                    OutlinedButton(
                      key: const Key('entry-reverse'),
                      onPressed: _busy ? null : () => _reverse(e),
                      child: const Text('Reverse'),
                    ),
                  if (e.canAttach)
                    OutlinedButton.icon(
                      key: const Key('entry-add-receipt'),
                      onPressed: _busy ? null : () => _addReceipt(true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Photograph a receipt'),
                    ),
                  if (e.canAttach)
                    TextButton(
                      onPressed: _busy ? null : () => _addReceipt(false),
                      child: const Text('Add a file'),
                    ),
                  if (e.canNote)
                    TextButton(
                      key: const Key('entry-note'),
                      onPressed: _busy ? null : _note,
                      child: const Text('Add a note'),
                    ),
                ],
              ),
              if (d.related.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('Linked entries'),
                const SizedBox(height: Space.x2),
                for (final r in d.related)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${r.typeLabel}: ${r.currency} ${r.signedAmount}',
                    ),
                    subtitle: Text(
                      '${_day(r.effectiveDate)}${r.reason == null ? '' : ' · ${r.reason}'}',
                    ),
                    onTap: () => context.pushReplacement(
                      Routes.ledgerEntry(widget.book.id, r.id),
                      extra: widget.book,
                    ),
                  ),
              ],
              if (d.attachments.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('Receipts'),
                for (final a in d.attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.scan.isInfected
                          ? Icons.gpp_bad_outlined
                          : a.scan.isPending
                          ? Icons.hourglass_top
                          : Icons.receipt_long_outlined,
                    ),
                    title: Text(a.fileName),
                    subtitle: a.scan.notice == null
                        ? null
                        : Text(a.scan.notice!),
                  ),
                if (d.attachments.any((a) => a.scan.isPending))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('receipts-check'),
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check again'),
                    ),
                  ),
                Text('Open receipts on the website.', style: text.bodySmall),
              ],
              if (d.notes.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('Notes'),
                for (final n in d.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x2),
                    child: Text(
                      '${n.text}\n${n.author} · ${stamp.format(n.at.toLocal())}',
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
