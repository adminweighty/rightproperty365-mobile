import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
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
import '../signing/pdf_pages.dart' show PdfScreen;
import 'properties_repository.dart';
import 'rent_repository.dart';

final _iso = DateFormat('yyyy-MM-dd');
String _day(String iso) => DateFormat('d MMM y').format(DateTime.parse(iso));

/// Receipts and payments as the ledger words them: recorded by the team,
/// never verified by a bank.
const receiptNotice =
    'A receipt is recorded by your team in its books as "Recorded by you, '
    'not verified". It is not a bank confirmation. A mistake is put right by '
    'reversing the receipt and recording it again.';

class DueStatusBadge extends StatelessWidget {
  const DueStatusBadge(this.due, {super.key});

  final RentDue due;

  @override
  Widget build(BuildContext context) => AppBadge(
    due.statusLabel.isEmpty ? due.status : due.statusLabel,
    tone: switch (due.status) {
      'PAID' => BadgeTone.success,
      'PART_PAID' => BadgeTone.accent,
      'WAIVED' => BadgeTone.neutral,
      _ => due.overdue ? BadgeTone.accent : BadgeTone.primary,
    },
  );
}

/// The rent at a glance on a tenancy: what is outstanding and overdue, and
/// what is next. One currency, the rent's.
class RentSummaryCard extends StatefulWidget {
  const RentSummaryCard({
    super.key,
    required this.scope,
    required this.tenancy,
    this.canWrite = false,
  });

  final RentScope scope;
  final Tenancy tenancy;
  final bool canWrite;

  @override
  State<RentSummaryCard> createState() => _RentSummaryCardState();
}

class _RentSummaryCardState extends State<RentSummaryCard> {
  Future<RentSchedule>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).rent.schedule(widget.scope);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return FutureBuilder<RentSchedule>(
      future: _loading,
      builder: (context, snapshot) {
        final s = snapshot.data;
        Widget row(
          String label,
          String value, {
          Key? key,
          bool strong = false,
        }) => Wrap(
          key: key,
          alignment: WrapAlignment.spaceBetween,
          spacing: Space.x2,
          children: [
            Text(label, style: text.bodyLarge),
            Text(value, style: strong ? text.titleMedium : text.bodyLarge),
          ],
        );
        return Container(
          key: const Key('rent-summary'),
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: c.sunken,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Rent', style: text.titleMedium),
              const SizedBox(height: Space.x2),
              if (snapshot.hasError)
                Text('We could not load the rent.', style: text.bodyMedium)
              else if (s == null)
                const Center(child: CircularProgressIndicator())
              else if (s.rule == null)
                Text(
                  'The rent schedule starts when the tenancy is made active.',
                  style: text.bodyMedium,
                )
              else ...[
                Text(
                  '${s.rule}, ${s.rolling ? 'rolling to' : 'through'} '
                  '${_day(s.through!)}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.x2),
                row(
                  'Outstanding',
                  s.summary.outstanding.toString(),
                  key: const Key('rent-outstanding'),
                  strong: true,
                ),
                row(
                  s.summary.overdueCount == 1
                      ? 'Overdue (1 due)'
                      : 'Overdue (${s.summary.overdueCount} dues)',
                  s.summary.overdue.toString(),
                ),
                if (s.summary.paidInAdvance.amount != '0.00' &&
                    s.summary.paidInAdvance.amount != '0')
                  row('Paid in advance', s.summary.paidInAdvance.toString()),
                if (s.summary.nextDue != null)
                  row(
                    'Next due ${_day(s.summary.nextDue!.dueDate)}',
                    s.summary.nextDue!.outstanding.toString(),
                  ),
              ],
              const SizedBox(height: Space.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('open-rent'),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RentScreen(
                          scope: widget.scope,
                          tenancy: widget.tenancy,
                          canWrite: widget.canWrite,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {
                      _loading = AppScope.of(context).rent
                          .schedule(widget.scope);
                    });
                  },
                  child: Text(
                    widget.scope.tenant
                        ? 'Dues, payments and statement'
                        : 'Schedule, receipts and statement',
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

/// A tenancy's rent: the schedule of dues, the receipts and the statement.
/// Managers with write access record receipts, waive dues and reverse
/// receipts; the tenant only reads.
class RentScreen extends StatefulWidget {
  const RentScreen({
    super.key,
    required this.scope,
    required this.tenancy,
    this.canWrite = false,
  });

  final RentScope scope;
  final Tenancy tenancy;
  final bool canWrite;

  @override
  State<RentScreen> createState() => _RentScreenState();
}

class _RentScreenState extends State<RentScreen> {
  int _version = 0;

  bool get _write => widget.canWrite && !widget.scope.tenant;

  Future<void> _record() async {
    final done = await Navigator.of(context).push<RecordedReceipt>(
      MaterialPageRoute(
        builder: (_) => RecordReceiptScreen(
          book: widget.scope.book!,
          tenancy: widget.tenancy,
        ),
      ),
    );
    if (done != null && mounted) {
      setState(() => _version++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded ${done.receipt.amount}'
            '${done.dues.isEmpty ? '' : ' against ${done.dues.length == 1 ? 'the due of ${_day(done.dues.single.dueDate)}' : '${done.dues.length} dues'}'}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.tenancy.place),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Schedule'),
              Tab(text: widget.scope.tenant ? 'Payments' : 'Receipts'),
              const Tab(text: 'Statement'),
            ],
          ),
        ),
        floatingActionButton: _write
            ? FloatingActionButton.extended(
                key: const Key('record-receipt'),
                onPressed: _record,
                icon: const Icon(Icons.add),
                label: const Text('Record a receipt'),
              )
            : null,
        body: TabBarView(
          children: [
            _DuesView(
              key: ValueKey('dues-$_version'),
              scope: widget.scope,
              canWrite: _write,
              onChanged: () => setState(() => _version++),
            ),
            _ReceiptsView(
              key: ValueKey('receipts-$_version'),
              scope: widget.scope,
              onChanged: () => setState(() => _version++),
            ),
            _StatementView(
              key: ValueKey('statement-$_version'),
              scope: widget.scope,
              tenancy: widget.tenancy,
            ),
          ],
        ),
      ),
    );
  }
}

class _DuesView extends StatefulWidget {
  const _DuesView({
    super.key,
    required this.scope,
    required this.canWrite,
    required this.onChanged,
  });

  final RentScope scope;
  final bool canWrite;
  final VoidCallback onChanged;

  @override
  State<_DuesView> createState() => _DuesViewState();
}

class _DuesViewState extends State<_DuesView> {
  String? _status;
  Future<RentSchedule>? _loading;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<RentSchedule> _get() =>
      AppScope.of(context).rent.schedule(widget.scope, status: _status);

  Future<void> _waive(RentDue due) async {
    final rent = AppScope.of(context).rent;
    final reason = await askForText(
      context,
      title: 'Waive ${due.outstanding} due ${_day(due.dueDate)}',
      label: 'Why it is waived',
      action: 'Waive',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await rent.waive(widget.scope.book!, due.id, reason);
      widget.onChanged();
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AsyncView<RentSchedule>(
      future: _loading!,
      onRetry: () => setState(() => _loading = _get()),
      builder: (context, s) => ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.x4,
          Space.x4,
          Space.x4,
          Space.x10 * 2,
        ),
        children: [
          if (s.rule != null)
            Text(
              '${s.rule}, ${s.rolling ? 'rolling to' : 'through'} ${_day(s.through!)}. '
              'Each due is the full rent.',
              style: text.bodyMedium,
            ),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final (code, label) in const [
                (null, 'All'),
                ('DUE', 'Due'),
                ('PART_PAID', 'Part paid'),
                ('PAID', 'Paid'),
                ('WAIVED', 'Waived'),
              ])
                ChoiceChip(
                  key: Key('dues-status-${code ?? 'all'}'),
                  label: Text(label),
                  selected: _status == code,
                  onSelected: (_) => setState(() {
                    _status = code;
                    _loading = _get();
                  }),
                ),
            ],
          ),
          if (_failure != null) ...[
            const SizedBox(height: Space.x3),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x3),
          if (s.dues.isEmpty)
            MessageView(
              icon: Icons.event_note_outlined,
              title: s.rule == null ? 'No schedule yet' : 'No dues here',
              body: s.rule == null
                  ? 'The schedule starts when the tenancy is made active.'
                  : 'Try another status.',
            ),
          for (final d in s.dues)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: _DueCard(
                d,
                onWaive: widget.canWrite && d.canWaive ? () => _waive(d) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard(this.due, {this.onWaive});

  final RentDue due;
  final VoidCallback? onWaive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final d = due;
    return BrandCard(
      key: Key('due-${d.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Space.x2,
              children: [
                Text('Due ${_day(d.dueDate)}', style: text.titleMedium),
                Text(d.amount.toString(), style: text.titleMedium),
              ],
            ),
            Text(
              'For ${_day(d.periodFrom)} to ${_day(d.periodTo)}',
              style: text.bodySmall,
            ),
            if (d.paid.amount != '0.00' && d.paid.amount != '0')
              Text('Paid ${d.paid}', style: text.bodyMedium),
            if (d.waived.amount != '0.00' && d.waived.amount != '0')
              Text(
                'Waived ${d.waived}'
                '${d.waiverReason == null ? '' : ': ${d.waiverReason}'}',
                style: text.bodyMedium,
              ),
            if (d.status != 'PAID' && d.status != 'WAIVED')
              Text(
                'Outstanding ${d.outstanding}'
                '${d.overdue ? ', ${d.daysOverdue} days overdue' : ''}',
                style: text.bodyMedium?.copyWith(
                  color: d.overdue ? c.danger : null,
                ),
              ),
            const SizedBox(height: Space.x1),
            Wrap(
              spacing: Space.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DueStatusBadge(d),
                if (onWaive != null)
                  TextButton(
                    key: Key('waive-${d.id}'),
                    onPressed: onWaive,
                    child: const Text('Waive'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptsView extends StatefulWidget {
  const _ReceiptsView({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  final RentScope scope;
  final VoidCallback onChanged;

  @override
  State<_ReceiptsView> createState() => _ReceiptsViewState();
}

class _ReceiptsViewState extends State<_ReceiptsView> {
  Future<List<RentReceipt>>? _loading;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).rent.receipts(widget.scope);
  }

  Future<void> _reverse(RentReceipt r) async {
    final ledger = AppScope.of(context).ledger;
    final reason = await askForText(
      context,
      title: 'Reverse the receipt of ${r.amount}',
      label: 'Why it is reversed',
      action: 'Reverse',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ledger.reverse(widget.scope.book!, r.ledgerEntryId!, reason);
      widget.onChanged();
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tenant = widget.scope.tenant;
    return AsyncView<List<RentReceipt>>(
      future: _loading!,
      onRetry: () => setState(() {
        _loading = AppScope.of(context).rent.receipts(widget.scope);
      }),
      builder: (context, items) => ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.x4,
          Space.x4,
          Space.x4,
          Space.x10 * 2,
        ),
        children: [
          Text(
            tenant
                ? 'Payments your landlord or agent has recorded. Ask them '
                      'about any that is missing.'
                : receiptNotice,
            style: text.bodySmall,
          ),
          if (_failure != null) ...[
            const SizedBox(height: Space.x3),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x3),
          if (items.isEmpty)
            MessageView(
              icon: Icons.receipt_long_outlined,
              title: tenant ? 'No payments recorded yet' : 'No receipts yet',
              body: tenant
                  ? 'They show here once recorded.'
                  : 'Record rent as it is received.',
            ),
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: BrandCard(
                key: Key('receipt-${r.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(Space.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: Space.x2,
                        children: [
                          Text(
                            'Received ${_day(r.receivedOn)}',
                            style: text.titleMedium,
                          ),
                          Text(
                            r.amount.toString(),
                            style: text.titleMedium?.copyWith(
                              decoration: r.reversed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        [
                          r.methodLabel,
                          ?r.reference,
                          if (r.tenant != null) r.tenant!.name,
                        ].join(' · '),
                        style: text.bodyMedium,
                      ),
                      if (r.allocations.isNotEmpty)
                        Text(
                          '${r.reversed ? 'Was against' : 'Against'} '
                          '${r.allocations.map((a) => 'the due of ${_day(a.dueDate)} (${a.amount})').join(', ')}',
                          style: text.bodySmall,
                        ),
                      if (r.reversedOn != null)
                        Text(
                          'Reversed ${_day(r.reversedOn!)}',
                          style: text.bodySmall,
                        ),
                      const SizedBox(height: Space.x1),
                      Wrap(
                        spacing: Space.x2,
                        runSpacing: Space.x1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppBadge(
                            r.statusLabel,
                            tone: r.reversed
                                ? BadgeTone.neutral
                                : BadgeTone.success,
                          ),
                          if (!tenant && r.ledgerStatusLabel != null)
                            AppBadge(r.ledgerStatusLabel!),
                          if (!tenant &&
                              r.canReverse &&
                              r.ledgerEntryId != null)
                            TextButton(
                              key: Key('reverse-${r.id}'),
                              onPressed: () => _reverse(r),
                              child: const Text('Reverse'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatementView extends StatefulWidget {
  const _StatementView({super.key, required this.scope, required this.tenancy});

  final RentScope scope;
  final Tenancy tenancy;

  @override
  State<_StatementView> createState() => _StatementViewState();
}

class _StatementViewState extends State<_StatementView> {
  String _period = 'all';
  Future<RentStatement>? _loading;

  ({String? from, String? to}) get _range {
    final now = DateTime.now();
    return switch (_period) {
      'quarter' => (
        from: _iso.format(DateTime(now.year, now.month - 3, now.day)),
        to: _iso.format(now),
      ),
      'year' => (from: _iso.format(DateTime(now.year)), to: _iso.format(now)),
      _ => (from: null, to: null),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<RentStatement> _get() {
    final r = _range;
    return AppScope.of(context).rent
        .statement(widget.scope, from: r.from, to: r.to);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rent = AppScope.of(context).rent;
    return AsyncView<RentStatement>(
      future: _loading!,
      onRetry: () => setState(() => _loading = _get()),
      builder: (context, st) => ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          SegmentedButton<String>(
            key: const Key('statement-period'),
            segments: const [
              ButtonSegment(value: 'all', label: Text('Whole tenancy')),
              ButtonSegment(value: 'quarter', label: Text('3 months')),
              ButtonSegment(value: 'year', label: Text('This year')),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _period = s.first;
              _loading = _get();
            }),
          ),
          const SizedBox(height: Space.x3),
          Text('${_day(st.from)} to ${_day(st.to)}', style: text.titleSmall),
          const SizedBox(height: Space.x2),
          if (st.currencies.isEmpty)
            const MessageView(
              icon: Icons.description_outlined,
              title: 'Nothing on the statement',
              body: 'Dues and payments show here once there are some.',
            ),
          for (final cur in st.currencies) _StatementTable(cur),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            children: [
              OutlinedButton.icon(
                key: const Key('statement-pdf'),
                onPressed: () {
                  final r = _range;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfScreen(
                        title: 'Statement',
                        load: () => rent.statementPdf(
                          widget.scope,
                          from: r.from,
                          to: r.to,
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('View as PDF'),
              ),
              if (!widget.scope.tenant)
                TextButton(
                  key: const Key('statement-website'),
                  onPressed: () => AppScope.of(context).openLink(
                    Uri.parse(
                      '${AppConfig.webBaseUrl}/agent/tenancies/${Uri.encodeComponent(widget.tenancy.id)}',
                    ),
                  ),
                  child: const Text('CSV download on the website'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatementTable extends StatelessWidget {
  const _StatementTable(this.cur);

  final StatementCurrency cur;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    Widget row(String label, String value, {bool strong = false}) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: Space.x2,
      children: [
        Text(label, style: strong ? text.titleSmall : text.bodyMedium),
        Text(value, style: strong ? text.titleSmall : text.bodyMedium),
      ],
    );
    return Container(
      key: Key('statement-${cur.currency}'),
      margin: const EdgeInsets.only(bottom: Space.x3),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(cur.currency, style: text.titleMedium),
          row('Opening balance', cur.opening.toString()),
          for (final l in cur.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(
                      '${_day(l.date)}  ${l.description}',
                      l.credit.amount != '0.00' && l.credit.amount != '0'
                          ? '- ${l.credit}'
                          : '+ ${l.debit}',
                    ),
                    Text(
                      'Balance ${l.balance}',
                      style: text.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ),
          const Divider(),
          row('Charged', cur.charged.toString()),
          row('Paid', cur.paid.toString()),
          if (cur.reversed.amount != '0.00' && cur.reversed.amount != '0')
            row('Payments reversed', cur.reversed.toString()),
          if (cur.waived.amount != '0.00' && cur.waived.amount != '0')
            row('Waived', cur.waived.toString()),
          row('Closing balance', cur.closing.toString(), strong: true),
          row('Overdue', cur.overdue.toString()),
        ],
      ),
    );
  }
}

/// Records rent received for a tenancy, in the rent's currency only.
class RecordReceiptScreen extends StatefulWidget {
  const RecordReceiptScreen({
    super.key,
    required this.book,
    required this.tenancy,
  });

  final String book;
  final Tenancy tenancy;

  @override
  State<RecordReceiptScreen> createState() => _RecordReceiptScreenState();
}

class _RecordReceiptScreenState extends State<RecordReceiptScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'BANK';
  DateTime _received = DateTime.now();
  late String? _tenant = widget.tenancy.tenants
      .where((p) => p.live && p.id != null)
      .firstOrNull
      ?.id;
  bool _saving = false;
  ApiFailure? _failure;

  static const _methods = {
    'CASH': 'Cash',
    'BANK': 'Bank',
    'MOBILE_MONEY': 'Mobile money',
    'OTHER': 'Other',
  };

  String get _currency => widget.tenancy.rent.money.currency;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  String? _amountProblem(String value) {
    final a = value.trim();
    if (!RegExp(r'^\d{1,16}(\.\d+)?$').hasMatch(a)) {
      return 'Enter an amount, for example ${widget.tenancy.rent.money.amount}.';
    }
    if (double.parse(a) <= 0) return 'The amount must be more than zero.';
    final rent = widget.tenancy.rent.money.amount;
    final allowed = rent.contains('.') ? rent.split('.').last.length : 0;
    final decimals = a.contains('.') ? a.split('.').last.length : 0;
    if (decimals > allowed) {
      return allowed == 0
          ? '$_currency has no decimals.'
          : 'At most $allowed decimals for $_currency.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final done = await AppScope.of(context).rent.record(
        widget.book,
        widget.tenancy.id,
        amount: _amount.text,
        currency: _currency,
        method: _method,
        receivedOn: _iso.format(_received),
        reference: _reference.text,
        tenantContactId: _tenant,
      );
      if (mounted) Navigator.of(context).pop(done);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = widget.tenancy;
    final tenants = [
      for (final p in t.tenants)
        if (p.live && p.id != null) p,
    ];
    final start = DateTime.parse(t.startDate);
    return Scaffold(
      appBar: AppBar(title: const Text('Record a receipt')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(t.place, style: text.titleMedium),
            Text('Rent ${t.rent}', style: text.bodyMedium),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('receipt-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount received',
                suffixText: _currency,
                helperText:
                    'In $_currency, the rent\'s currency. Other currencies '
                    'cannot be recorded against this rent.',
                helperMaxLines: 3,
              ),
              validator: (v) => _amountProblem(v ?? ''),
            ),
            const SizedBox(height: Space.x3),
            SearchableSelectField<String>(
              key: const Key('receipt-method'),
              label: 'Paid by',
              value: _method,
              options: [
                for (final e in _methods.entries) SelectOption(e.key, e.value),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'BANK'),
            ),
            if (tenants.length > 1) ...[
              const SizedBox(height: Space.x3),
              SearchableSelectField<String>(
                key: const Key('receipt-tenant'),
                label: 'From',
                value: _tenant,
                options: [for (final p in tenants) SelectOption(p.id!, p.name)],
                onChanged: (v) => setState(() => _tenant = v),
              ),
            ],
            const SizedBox(height: Space.x3),
            OutlinedButton.icon(
              key: const Key('receipt-date'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _received,
                  firstDate: start.isAfter(now) ? now : start,
                  lastDate: now,
                );
                if (picked != null) setState(() => _received = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                'Received ${DateFormat('d MMMM y').format(_received)}',
              ),
            ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('receipt-reference'),
              controller: _reference,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Bank or receipt reference (optional)',
              ),
            ),
            Text(
              'It goes to the oldest unpaid dues first. To split it '
              'differently, record it on the website.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Space.x2),
            Text(receiptNotice, style: text.bodySmall),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('receipt-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Recording…' : 'Record the receipt'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rent arrears by age, one table per currency, never combined.
class ArrearsView extends StatefulWidget {
  const ArrearsView({super.key, required this.book, required this.onOpen});

  final String book;
  final void Function(String tenancyId) onOpen;

  @override
  State<ArrearsView> createState() => _ArrearsViewState();
}

class _ArrearsViewState extends State<ArrearsView> {
  Future<({String asOf, List<CurrencyArrears> currencies})>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).rent.arrears(widget.book);
  }

  @override
  void didUpdateWidget(ArrearsView old) {
    super.didUpdateWidget(old);
    if (old.book != widget.book) {
      _loading = AppScope.of(context).rent.arrears(widget.book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MessageView(
            icon: Icons.cloud_off_outlined,
            title: 'We could not load the arrears',
            body: 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: () => setState(() {
              _loading = AppScope.of(context).rent.arrears(widget.book);
            }),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Padding(
            padding: EdgeInsets.all(Space.x6),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (data.currencies.isEmpty) {
          return const MessageView(
            icon: Icons.check_circle_outline,
            title: 'No rent in arrears',
            body: 'Every due before today is paid or waived.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('As of ${_day(data.asOf)}', style: text.bodySmall),
            const SizedBox(height: Space.x2),
            for (final cur in data.currencies) ...[
              Container(
                key: Key('arrears-${cur.currency}'),
                padding: const EdgeInsets.all(Space.x4),
                decoration: BoxDecoration(
                  color: c.sunken,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(cur.currency, style: text.titleMedium),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: Space.x2,
                      children: [
                        Text(
                          '${cur.count} ${cur.count == 1 ? 'due' : 'dues'} '
                          'in arrears',
                          style: text.bodyLarge,
                        ),
                        Text(
                          cur.outstanding.toString(),
                          style: text.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    for (final b in cur.buckets)
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: Space.x2,
                        children: [
                          Text(b.label, style: text.bodyMedium),
                          Text(
                            '${b.outstanding} (${b.count})',
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.x3),
              for (final t in cur.tenancies)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x3),
                  child: BrandCard(
                    key: Key('arrears-tenancy-${t.tenancyId}'),
                    onTap: () => widget.onOpen(t.tenancyId),
                    semanticLabel:
                        '${t.place}. ${t.tenants}. ${t.outstanding} in arrears, '
                        '${t.daysOverdue} days overdue',
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: Space.x2,
                            children: [
                              Text(t.place, style: text.titleMedium),
                              Text(
                                t.outstanding.toString(),
                                style: text.titleMedium?.copyWith(
                                  color: c.danger,
                                ),
                              ),
                            ],
                          ),
                          if (t.tenants.isNotEmpty)
                            Text(t.tenants, style: text.bodyMedium),
                          Text(
                            'Oldest due ${_day(t.oldestDueDate)}, '
                            '${t.daysOverdue} days overdue',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
