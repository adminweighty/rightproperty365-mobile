import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../signing/pdf_pages.dart';
import 'lease_repository.dart';

final _day = DateFormat('d MMM y');
final _when = DateFormat('d MMM y, HH:mm');

BadgeTone _tone(String status) => switch (status) {
  'SIGNED' => BadgeTone.success,
  'SENT_FOR_SIGNING' => BadgeTone.primary,
  _ => BadgeTone.neutral,
};

String _rent(Lease lease) =>
    '${formatMoney(Money(lease.rentAmount, lease.rentCurrency))} ${rentPeriodLabel(lease.rentPeriod)}';

/// The leases the signed-in person may see: drafts to finish, leases out for
/// signing and signed ones.
class LeasesScreen extends StatefulWidget {
  const LeasesScreen({super.key});

  @override
  State<LeasesScreen> createState() => _LeasesScreenState();
}

class _LeasesScreenState extends State<LeasesScreen> {
  Future<List<Lease>>? _leases;
  String? _status;

  static const _filters = {
    null: 'All',
    'DRAFT': 'Drafts',
    'SENT_FOR_SIGNING': 'Out for signing',
    'SIGNED': 'Signed',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _leases ??= AppScope.of(context).leases.list();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).leases.list(status: _status);
    setState(() {
      _leases = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leases')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('lease-new'),
        onPressed: () async {
          final created = await context.push<Lease>(Routes.newLease);
          if (created != null && context.mounted) {
            await context.push(Routes.lease(created.id));
          }
          _reload();
        },
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Draft a lease'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
            child: Row(
              children: [
                for (final entry in _filters.entries) ...[
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _status == entry.key,
                    onSelected: (_) {
                      setState(() => _status = entry.key);
                      _reload();
                    },
                  ),
                  const SizedBox(width: Space.x2),
                ],
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Lease>>(
              future: _leases,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final error = snapshot.error;
                if (error != null) {
                  final forbidden = error is ApiFailure && error.status == 403;
                  return MessageView(
                    icon: forbidden
                        ? Icons.lock_outline
                        : Icons.cloud_off_outlined,
                    title: forbidden
                        ? 'Leases are for people who manage listings'
                        : 'We could not load your leases',
                    body: forbidden
                        ? 'Estate Agents, Agency Principals and approved Landlords draft leases.'
                        : 'Check your connection and try again.',
                    actionLabel: forbidden ? null : 'Try again',
                    onAction: forbidden ? null : _reload,
                  );
                }
                final leases = snapshot.data!;
                if (leases.isEmpty) {
                  return MessageView(
                    icon: Icons.description_outlined,
                    title: 'No leases yet',
                    body: 'Draft a lease from one of your templates, then send it to the landlord and tenants to sign.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Space.x4,
                      Space.x4,
                      Space.x4,
                      96,
                    ),
                    itemCount: leases.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Space.x3),
                    itemBuilder: (context, i) => _LeaseCard(
                      leases[i],
                      onTap: () async {
                        await context.push(Routes.lease(leases[i].id));
                        _reload();
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaseCard extends StatelessWidget {
  const _LeaseCard(this.lease, {required this.onTap});

  final Lease lease;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tenants = [for (final t in lease.tenants) t.name].join(', ');
    return BrandCard(
      key: Key('lease-${lease.id}'),
      onTap: onTap,
      semanticLabel:
          '${lease.title}, ${lease.statusLabel}, ${lease.reference}. Tenants $tenants',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(lease.title, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(lease.statusLabel, tone: _tone(lease.status)),
              ],
            ),
            Text(
              '${lease.reference} · ${_rent(lease)}',
              style: text.bodyMedium,
            ),
            if (tenants.isNotEmpty)
              Text('Tenants: $tenants', style: text.bodyMedium),
            Text(
              lease.periodic || lease.endDate == null
                  ? 'From ${_day.format(lease.startDate)}, periodic'
                  : '${_day.format(lease.startDate)} to ${_day.format(lease.endDate!)}',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// One lease: its terms and parties, the PDF, and what can be done next
/// (edit, send for signing, cancel, delete).
class LeaseDetailScreen extends StatefulWidget {
  const LeaseDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<LeaseDetailScreen> createState() => _LeaseDetailScreenState();
}

class _LeaseDetailScreenState extends State<LeaseDetailScreen> {
  Future<(Lease, List<LeaseEvent>)>? _lease;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lease ??= _load();
  }

  Future<(Lease, List<LeaseEvent>)> _load() async {
    final repo = AppScope.of(context).leases;
    final results = await Future.wait([
      repo.get(widget.id),
      repo
          .events(widget.id)
          .then<Object>((e) => e, onError: (_) => <LeaseEvent>[]),
    ]);
    return (results[0] as Lease, results[1] as List<LeaseEvent>);
  }

  void _reload() => setState(() {
    _lease = _load();
  });

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _say(done);
      _reload();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _say(leaseMessage(failure));
      if (failure.status == 409) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(Lease lease) async {
    final message = TextEditingController();
    var reminders = 'EVERY_3_DAYS';
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Send for signing?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The lease is frozen and emailed to '
                  '${[...lease.landlords, ...lease.tenants].map((p) => p.name).join(', ')}. '
                  'Each initials every page and signs at the end. It cannot be edited after this.',
                ),
                const SizedBox(height: Space.x3),
                TextField(
                  controller: message,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message to the signers (optional)',
                  ),
                ),
                SearchableSelectField<String>(
                  label: 'Reminders',
                  value: reminders,
                  options: const [
                    SelectOption('NONE', 'No reminders'),
                    SelectOption('DAILY', 'Every day until they sign'),
                    SelectOption(
                      'EVERY_3_DAYS',
                      'Every 3 days until they sign',
                    ),
                    SelectOption('WEEKLY', 'Every week until they sign'),
                  ],
                  onChanged: (v) => setDialog(() => reminders = v ?? reminders),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              key: const Key('lease-send-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    final text = message.text;
    message.dispose();
    if (go != true || !mounted) return;
    await _run(
      () =>
          AppScope.of(context).leases
              .send(lease.id, message: text, reminders: reminders),
      'Sent for signing. Everyone has been emailed.',
    );
  }

  Future<void> _cancel(Lease lease) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this lease?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lease.status == 'DRAFT'
                  ? 'The draft is kept but can no longer be sent.'
                  : 'The signing links stop working and nobody can sign it any more.',
            ),
            TextField(
              controller: reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel lease'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (go != true || !mounted) return;
    await _run(
      () => AppScope.of(context).leases.cancel(lease.id, reason: text),
      'Lease cancelled',
    );
  }

  Future<void> _delete(Lease lease) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'The draft, its PDF and its history are deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).leases.delete(lease.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _busy = false);
        _say(leaseMessage(failure));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Lease, List<LeaseEvent>)>(
      future: _lease,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(data?.$1.reference ?? 'Lease')),
          body: switch (snapshot) {
            AsyncSnapshot(hasError: true, :final error) => MessageView(
              icon: Icons.cloud_off_outlined,
              title: 'We could not load this lease',
              body: error is ApiFailure
                  ? leaseMessage(error)
                  : 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: _reload,
            ),
            _ when data == null => const Center(
              child: CircularProgressIndicator(),
            ),
            _ => _details(context, data.$1, data.$2),
          },
        );
      },
    );
  }

  Widget _details(BuildContext context, Lease lease, List<LeaseEvent> events) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
          ),
          Expanded(child: Text(value, style: text.bodyLarge)),
        ],
      ),
    );
    Widget party(LeaseParty p) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: text.titleSmall),
          SelectableText(
            [p.email, ?p.phone].join(' · '),
            style: text.bodyMedium,
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(lease.title, style: text.headlineSmall)),
            AppBadge(lease.statusLabel, tone: _tone(lease.status)),
          ],
        ),
        Text(
          '${lease.templateName} (version ${lease.templateVersion})'
          '${lease.organisationName == null ? '' : ' · ${lease.organisationName}'}',
          style: text.bodyMedium,
        ),
        if (lease.cancelReason != null) ...[
          const SizedBox(height: Space.x2),
          Text('Cancelled: ${lease.cancelReason}', style: text.bodyMedium),
        ],
        if (_busy) ...[
          const SizedBox(height: Space.x3),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: Space.x4),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            if (lease.hasDocument)
              OutlinedButton.icon(
                key: const Key('lease-pdf'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PdfScreen(
                      title: lease.reference,
                      load: () => AppScope.of(context).leases.pdf(lease.id),
                    ),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  lease.status == 'DRAFT' ? 'View draft PDF' : 'View PDF',
                ),
              ),
            if (lease.canEdit)
              OutlinedButton.icon(
                key: const Key('lease-edit'),
                onPressed: _busy
                    ? null
                    : () async {
                        await context.push(Routes.editLease(lease.id));
                        _reload();
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            if (lease.canSend)
              FilledButton.icon(
                key: const Key('lease-send'),
                onPressed: _busy ? null : () => _send(lease),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Send for signing'),
              ),
          ],
        ),
        const SizedBox(height: Space.x6),
        const SectionHeading('Terms'),
        const SizedBox(height: Space.x2),
        row('Property', lease.propertyAddress),
        row(
          'Term',
          lease.periodic || lease.endDate == null
              ? 'From ${_day.format(lease.startDate)}, periodic'
              : '${_day.format(lease.startDate)} to ${_day.format(lease.endDate!)}',
        ),
        row('Rent', _rent(lease)),
        row('Paid on', lease.paymentDayLabel),
        if (lease.depositAmount != null)
          row(
            'Deposit',
            formatMoney(Money(lease.depositAmount!, lease.rentCurrency)),
          ),
        row('Notice', '${lease.noticePeriodDays} days'),
        if (lease.landlordStamp) row('Stamp', 'Landlords add a company stamp'),
        if (lease.optionalClauses.isNotEmpty)
          row('Clauses', lease.optionalClauses.join(', ')),
        if ((lease.specialConditions ?? '').isNotEmpty)
          row('Special conditions', lease.specialConditions!),
        const SizedBox(height: Space.x5),
        SectionHeading(lease.landlords.length == 1 ? 'Landlord' : 'Landlords'),
        const SizedBox(height: Space.x2),
        for (final p in lease.landlords) party(p),
        const SizedBox(height: Space.x3),
        SectionHeading(lease.tenants.length == 1 ? 'Tenant' : 'Tenants'),
        const SizedBox(height: Space.x2),
        for (final p in lease.tenants) party(p),
        if (events.isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          const SectionHeading('History'),
          const SizedBox(height: Space.x2),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
              child: Text(
                '${_when.format(e.at.toLocal())} · ${leaseEventLabel(e.action)}'
                '${e.actorName.isEmpty ? '' : ' · ${e.actorName}'}',
                style: text.bodyMedium,
              ),
            ),
        ],
        const SizedBox(height: Space.x6),
        if (lease.canCancel)
          OutlinedButton(
            key: const Key('lease-cancel'),
            onPressed: _busy ? null : () => _cancel(lease),
            child: const Text('Cancel lease'),
          ),
        if (lease.canDelete) ...[
          const SizedBox(height: Space.x2),
          TextButton(
            key: const Key('lease-delete'),
            onPressed: _busy ? null : () => _delete(lease),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Delete draft'),
          ),
        ],
      ],
    );
  }
}
