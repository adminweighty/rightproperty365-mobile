/// Renewal invoices issued to the signed-in payer (API 0.47.0), read-only.
/// Payment is never offered in the app: `pay_url` is not used, because
/// store billing rules keep payment on the website.
library;

import 'package:intl/intl.dart' show NumberFormat;

import '../../core/api/api_client.dart';

final _cents = NumberFormat('#,##0.00', 'en');

/// An exact amount as the API sends it (a decimal string, or a number).
String _amount(Object? value) => switch (value) {
  final String s => s,
  final num n => n.toStringAsFixed(2),
  _ => '0.00',
};

/// "USD 1,234.50": invoices show cents.
String invoiceMoney(String amount, String currency) =>
    '$currency ${_cents.format(double.tryParse(amount) ?? 0)}';

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

enum InvoiceStatus {
  issued('ISSUED', 'Awaiting payment'),
  partPaid('PART_PAID', 'Part paid'),
  paid('PAID', 'Paid'),
  overdue('OVERDUE', 'Overdue'),
  voided('VOID', 'Void'),
  disputed('DISPUTED', 'Disputed'),
  other('', '');

  const InvoiceStatus(this.wire, this.label);
  final String wire;
  final String label;

  static InvoiceStatus from(Object? wire) => values.firstWhere(
    (s) => s.wire == wire && s != other,
    orElse: () => other,
  );
}

class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.quantity,
    required this.amount,
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    description: json['description'] as String? ?? '',
    quantity: _amount(json['quantity']),
    amount: _amount(json['amount']),
  );

  final String description;
  final String quantity;
  final String amount;
}

/// A payment recorded against the invoice, with its receipt.
class InvoicePayment {
  const InvoicePayment({
    required this.id,
    required this.amount,
    required this.method,
    this.receiptNumber,
    this.receivedOn,
  });

  factory InvoicePayment.fromJson(Map<String, dynamic> json) => InvoicePayment(
    id: json['id'] as String? ?? '',
    amount: _amount(json['amount']),
    method: json['method'] as String? ?? '',
    receiptNumber: json['receipt_number'] as String?,
    receivedOn: _date(json['received_on'] ?? json['created_at']),
  );

  final String id;
  final String amount;

  /// BANK_TRANSFER, CASH, CARD_OFFLINE, GATEWAY or OTHER.
  final String method;
  final String? receiptNumber;
  final DateTime? receivedOn;

  String get methodLabel => switch (method) {
    'BANK_TRANSFER' => 'Bank transfer',
    'CASH' => 'Cash',
    'CARD_OFFLINE' => 'Card',
    'GATEWAY' => 'Online payment',
    _ => 'Other',
  };
}

class CreditNote {
  const CreditNote({required this.number, required this.amount, this.at});

  factory CreditNote.fromJson(Map<String, dynamic> json) => CreditNote(
    number: json['number'] as String? ?? '',
    amount: _amount(json['amount']),
    at: _date(json['created_at']),
  );

  final String number;
  final String amount;
  final DateTime? at;
}

/// An issued invoice (never a draft) as its payer sees it.
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.status,
    required this.statusLabel,
    required this.currency,
    required this.total,
    required this.balance,
    this.subtotal,
    this.amountPaid,
    this.amountCredited,
    this.planName,
    this.payerName,
    this.serviceFrom,
    this.serviceTo,
    this.issueOn,
    this.dueOn,
    this.terms,
    this.taxName,
    this.taxRate,
    this.taxAmount,
    this.taxInclusive = false,
    this.taxIsSample = false,
    this.lines = const [],
    this.payments = const [],
    this.creditNotes = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final status = InvoiceStatus.from(json['status']);
    String? text(String key) => json[key] as String?;
    String? money(String key) => json[key] == null ? null : _amount(json[key]);
    return Invoice(
      id: json['id'] as String,
      number: text('number') ?? '',
      status: status,
      statusLabel:
          text('status_label') ??
          (status == InvoiceStatus.other
              ? (json['status'] as String? ?? '')
              : status.label),
      currency: text('currency_code') ?? text('currency') ?? '',
      total: _amount(json['total']),
      balance: _amount(json['balance'] ?? json['total']),
      subtotal: money('subtotal'),
      amountPaid: money('amount_paid'),
      amountCredited: money('amount_credited'),
      planName: text('plan_name'),
      payerName: text('payer_name'),
      serviceFrom: _date(json['service_from']),
      serviceTo: _date(json['service_to']),
      issueOn: _date(json['issue_on']),
      dueOn: _date(json['due_on']),
      terms: text('terms'),
      taxName: text('tax_name'),
      taxRate: json['tax_rate'] == null ? null : _amount(json['tax_rate']),
      taxAmount: money('tax_amount'),
      taxInclusive: json['tax_inclusive'] == true,
      taxIsSample: json['tax_is_sample'] == true,
      lines: [
        for (final l in (json['lines'] as List?) ?? const [])
          InvoiceLine.fromJson(l as Map<String, dynamic>),
      ],
      payments: [
        for (final p in (json['payments'] as List?) ?? const [])
          InvoicePayment.fromJson(p as Map<String, dynamic>),
      ],
      creditNotes: [
        for (final c in (json['credit_notes'] as List?) ?? const [])
          CreditNote.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String number;
  final InvoiceStatus status;
  final String statusLabel;
  final String currency;
  final String total;
  final String balance;
  final String? subtotal;
  final String? amountPaid;
  final String? amountCredited;
  final String? planName;
  final String? payerName;
  final DateTime? serviceFrom;
  final DateTime? serviceTo;
  final DateTime? issueOn;
  final DateTime? dueOn;
  final String? terms;

  /// Null when the market has no tax rule: no tax line.
  final String? taxName;
  final String? taxRate;
  final String? taxAmount;
  final bool taxInclusive;

  /// The rate is sample test data, and the document says so.
  final bool taxIsSample;
  final List<InvoiceLine> lines;
  final List<InvoicePayment> payments;
  final List<CreditNote> creditNotes;

  bool get settled =>
      status == InvoiceStatus.paid || status == InvoiceStatus.voided;
}

class InvoicesRepository {
  InvoicesRepository(this._api);

  final ApiClient _api;

  /// The payer's issued invoices, newest first.
  Future<List<Invoice>> list() async {
    final body = (await _api.get('/v1/me/invoices?limit=50')).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        Invoice.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Invoice> get(String id) async {
    try {
      final body = (await _api.get(
        '/v1/me/invoices/${Uri.encodeComponent(id)}',
      )).body;
      return Invoice.fromJson(
        (body['invoice'] ?? body) as Map<String, dynamic>,
      );
    } on ApiFailure catch (failure) {
      throw failure.status == 404
          ? failure.withMessage(
              'This invoice is not one of yours. Invoices of an organisation '
              'are shown to its owners and managers.',
            )
          : failure;
    }
  }
}
