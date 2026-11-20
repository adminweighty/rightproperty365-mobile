import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import 'invoices.dart';

final _day = DateFormat('d MMM y');

// Due and service dates are calendar dates: shown as sent, not shifted.
String _on(DateTime d) => _day.format(DateTime(d.year, d.month, d.day));

BadgeTone invoiceTone(InvoiceStatus s) => switch (s) {
  InvoiceStatus.paid => BadgeTone.success,
  InvoiceStatus.overdue || InvoiceStatus.disputed => BadgeTone.accent,
  InvoiceStatus.voided => BadgeTone.neutral,
  _ => BadgeTone.primary,
};

String? _period(Invoice i) => i.serviceFrom == null || i.serviceTo == null
    ? null
    : '${_on(i.serviceFrom!)} to ${_on(i.serviceTo!)}';

/// The payer's renewal invoices: read-only. Paying is not offered in the app.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  Future<List<Invoice>>? _invoices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invoices ??= AppScope.of(context).invoices.list();
  }

  void _reload() => setState(() {
    _invoices = AppScope.of(context).invoices.list();
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: AsyncView<List<Invoice>>(
        future: _invoices!,
        onRetry: _reload,
        builder: (context, invoices) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            if (invoices.isEmpty)
              Text(
                'No invoices yet. Renewal invoices for your subscription '
                'appear here.',
                key: const Key('invoices-empty'),
                style: text.bodyLarge,
              ),
            for (final invoice in invoices)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x3),
                child: InvoiceCard(
                  invoice,
                  onTap: () => context.push(Routes.invoice(invoice.id)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InvoiceCard extends StatelessWidget {
  const InvoiceCard(this.invoice, {super.key, required this.onTap});

  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final i = invoice;
    final total = invoiceMoney(i.total, i.currency);
    final balance = i.settled || i.balance == i.total
        ? null
        : 'Balance ${invoiceMoney(i.balance, i.currency)}';
    final due = i.dueOn == null || i.settled ? null : 'Due ${_on(i.dueOn!)}';
    final period = _period(i);
    return BrandCard(
      key: Key('invoice-${i.id}'),
      onTap: onTap,
      semanticLabel: [
        'Invoice ${i.number}',
        i.statusLabel,
        total,
        ?balance,
        ?due,
        ?period,
      ].join('. '),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(i.number, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(i.statusLabel, tone: invoiceTone(i.status)),
              ],
            ),
            if (i.planName != null) Text(i.planName!, style: text.bodyMedium),
            if (period != null) Text(period, style: text.bodyMedium),
            const SizedBox(height: Space.x1),
            Text(total, style: text.titleSmall),
            if (balance != null) Text(balance, style: text.bodyMedium),
            if (due != null)
              Text(
                due,
                style: text.bodyMedium?.copyWith(
                  color: i.status == InvoiceStatus.overdue ? c.danger : null,
                  fontWeight: i.status == InvoiceStatus.overdue
                      ? FontWeight.w600
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One invoice: lines, tax, totals, payments with their receipts, credit
/// notes and terms.
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key, required this.id});

  final String id;

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Future<Invoice>? _invoice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invoice ??= AppScope.of(context).invoices.get(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: AsyncView<Invoice>(
        future: _invoice!,
        onRetry: () => setState(() {
          _invoice = AppScope.of(context).invoices.get(widget.id);
        }),
        builder: (context, i) => _body(context, i),
      ),
    );
  }

  Widget _body(BuildContext context, Invoice i) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    String m(String amount) => invoiceMoney(amount, i.currency);
    Widget row(String label, String value, {Key? key, bool strong = false}) {
      final style = strong ? text.titleMedium : text.bodyLarge;
      return MergeSemantics(
        child: Padding(
          key: key,
          padding: const EdgeInsets.only(bottom: Space.x1),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: Space.x3,
            children: [
              Text(label, style: style),
              Text(value, style: style),
            ],
          ),
        ),
      );
    }

    final period = _period(i);
    final note = switch (i.status) {
      InvoiceStatus.voided =>
        'This invoice was cancelled and does not need to be paid.',
      InvoiceStatus.disputed =>
        'This invoice is being reviewed by RightProperty365 Finance.',
      InvoiceStatus.paid => null,
      _ => 'This invoice cannot be paid in the app.',
    };
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(i.number, style: text.headlineSmall),
              ),
            ),
            const SizedBox(width: Space.x2),
            AppBadge(i.statusLabel, tone: invoiceTone(i.status)),
          ],
        ),
        if (i.payerName != null)
          Text(
            'To ${i.payerName}',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        const SizedBox(height: Space.x3),
        if (i.planName != null) row('Plan', i.planName!),
        if (period != null) row('Service period', period),
        if (i.issueOn != null) row('Issued', _on(i.issueOn!)),
        if (i.dueOn != null)
          row('Due', _on(i.dueOn!), key: const Key('invoice-due')),
        if (note != null) ...[
          const SizedBox(height: Space.x3),
          Container(
            key: const Key('invoice-note'),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: i.status == InvoiceStatus.overdue
                  ? c.dangerSoft
                  : c.infoSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              i.status == InvoiceStatus.overdue
                  ? 'This invoice is overdue. $note'
                  : note,
              style: text.bodyLarge,
            ),
          ),
        ],
        const SizedBox(height: Space.x5),
        const SectionHeading('Lines'),
        const SizedBox(height: Space.x2),
        for (final l in i.lines)
          row(
            l.quantity == '1' || l.quantity == '1.00'
                ? l.description
                : '${l.description} × ${l.quantity}',
            m(l.amount),
          ),
        const Divider(),
        if (i.subtotal != null) row('Subtotal', m(i.subtotal!)),
        if (i.taxName != null && i.taxAmount != null)
          row(
            '${i.taxName}${i.taxRate == null ? '' : ' ${_rate(i.taxRate!)}%'}'
            '${i.taxInclusive ? ' (included)' : ''}',
            m(i.taxAmount!),
            key: const Key('invoice-tax'),
          )
        else
          row('Tax', 'No tax for this market', key: const Key('invoice-tax')),
        if (i.taxIsSample)
          Text(
            'Sample tax rate (test data)',
            key: const Key('invoice-tax-sample'),
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        row('Total', m(i.total), strong: true),
        if (i.amountPaid != null && i.amountPaid != '0.00')
          row('Paid', m(i.amountPaid!)),
        if (i.amountCredited != null && i.amountCredited != '0.00')
          row('Credited', m(i.amountCredited!)),
        if (i.status != InvoiceStatus.voided)
          row(
            'Balance',
            m(i.balance),
            strong: true,
            key: const Key('invoice-balance'),
          ),
        if (i.payments.isNotEmpty) ...[
          const SizedBox(height: Space.x5),
          const SectionHeading('Payments and receipts'),
          const SizedBox(height: Space.x2),
          for (final p in i.payments)
            Padding(
              key: Key('invoice-payment-${p.id}'),
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.receiptNumber == null
                          ? 'Payment'
                          : 'Receipt ${p.receiptNumber}',
                      style: text.titleSmall,
                    ),
                    Text(
                      [
                        m(p.amount),
                        p.methodLabel,
                        if (p.receivedOn != null) _on(p.receivedOn!),
                      ].join(' · '),
                      style: text.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (i.creditNotes.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          const SectionHeading('Credit notes'),
          const SizedBox(height: Space.x2),
          for (final n in i.creditNotes) row(n.number, m(n.amount)),
        ],
        if (i.terms != null && i.terms!.trim().isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          const SectionHeading('Terms'),
          const SizedBox(height: Space.x2),
          Text(i.terms!, style: text.bodyMedium),
        ],
      ],
    );
  }

  /// "15" from "15.00", "7.5" from "7.50".
  static String _rate(String rate) {
    final r = double.tryParse(rate);
    if (r == null) return rate;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  }
}
