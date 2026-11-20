import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/billing/invoices.dart';
import 'package:rightproperty365/features/billing/invoices_screens.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';

import 'support.dart';
import 'work_test.dart' show failure, serve, settle;

Map<String, dynamic> invoiceJson({
  String id = 'inv-1',
  String status = 'PART_PAID',
  String total = '115.00',
  String balance = '65.00',
  String paid = '50.00',
  bool tax = true,
  bool sample = false,
  List<Map<String, dynamic>>? payments,
}) => {
  'id': id,
  'number': 'INV-ZW-2026-000012',
  'status': status,
  'market_code': 'ZW',
  'currency_code': 'USD',
  'payer_name': 'Sample Estates',
  'plan_name': 'Agency Pro',
  'period': 'MONTHLY',
  'service_from': '2026-12-01',
  'service_to': '2026-12-31',
  'issue_on': '2026-11-20',
  'due_on': '2026-12-04',
  'terms':
      'Payment is due by the due date. Your subscription renews when payment '
      'is confirmed.',
  'subtotal': '100.00',
  'tax_name': tax ? 'VAT' : null,
  'tax_rate': tax ? '15' : null,
  'tax_inclusive': false,
  'tax_amount': tax ? '15.00' : null,
  'tax_is_sample': sample,
  'total': total,
  'amount_paid': paid,
  'amount_credited': '0.00',
  'balance': balance,
  'lines': [
    {
      'description': 'Agency Pro, December 2026',
      'quantity': '1',
      'unit_amount': '100.00',
      'amount': '100.00',
    },
  ],
  'payments':
      payments ??
      [
        {
          'id': 'pay-1',
          'amount': '50.00',
          'method': 'BANK_TRANSFER',
          'reference': 'FBC 0042',
          'received_on': '2026-11-25',
          'receipt_number': 'RCT-ZW-2026-000003',
        },
      ],
  'credit_notes': [],
  'pay_url': 'https://rightproperty365.com/account/subscriptions/sub-9',
};

/// Words that would offer payment. None may appear in the app.
final payWords = RegExp(
  r'\bpay (now|online)\b|checkout|pay_url|/subscriptions/',
  caseSensitive: false,
);

void expectNoPayment(WidgetTester tester) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final value = t.data ?? t.textSpan?.toPlainText() ?? '';
    expect(payWords.hasMatch(value), isFalse, reason: value);
  }
  for (final t in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    expect(payWords.hasMatch(t.data ?? ''), isFalse);
  }
}

void main() {
  group('the model', () {
    test('reads an invoice; amounts stay exact strings', () {
      final i = Invoice.fromJson(invoiceJson());
      expect(i.status, InvoiceStatus.partPaid);
      expect(i.statusLabel, 'Part paid');
      expect(i.balance, '65.00');
      expect(i.payments.single.receiptNumber, 'RCT-ZW-2026-000003');
      expect(i.payments.single.methodLabel, 'Bank transfer');
      expect(invoiceMoney('1234.5', 'USD'), 'USD 1,234.50');
      // Numbers are read too.
      expect(
        Invoice.fromJson({...invoiceJson(), 'total': 115}).total,
        '115.00',
      );
    });

    test('each state has a label; an unknown one shows as sent', () {
      for (final (wire, label) in [
        ('ISSUED', 'Awaiting payment'),
        ('PART_PAID', 'Part paid'),
        ('PAID', 'Paid'),
        ('OVERDUE', 'Overdue'),
        ('VOID', 'Void'),
        ('DISPUTED', 'Disputed'),
        ('REFUNDED', 'REFUNDED'),
      ]) {
        expect(Invoice.fromJson(invoiceJson(status: wire)).statusLabel, label);
      }
      // The API's own label wins.
      expect(
        Invoice.fromJson({...invoiceJson(), 'status_label': 'Part-paid'})
            .statusLabel,
        'Part-paid',
      );
    });

    test('offered to direct owners and organisation owners and managers', () {
      Workspace org(String role) => Workspace.fromJson({
        'organisations': [
          {'id': 'o', 'name': 'O', 'role': role},
        ],
      });
      expect(org('OWNER').receivesInvoices, isTrue);
      expect(org('MANAGER').receivesInvoices, isTrue);
      expect(org('AGENT').receivesInvoices, isFalse);
      expect(org('STAFF').receivesInvoices, isFalse);
      expect(
        Workspace.fromJson({'direct_owner': true}).receivesInvoices,
        isTrue,
      );
      expect(Workspace.fromJson(const {}).receivesInvoices, isFalse);
    });
  });

  group('the screens', () {
    testWidgets('the list: status, total, balance and due date', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/invoices': (_) => {
          'items': [
            invoiceJson(),
            invoiceJson(
              id: 'inv-2',
              status: 'OVERDUE',
              balance: '115.00',
              paid: '0.00',
              payments: const [],
            ),
            invoiceJson(id: 'inv-3', status: 'PAID', balance: '0.00'),
          ],
        },
      });
      await pumpInApp(tester, test, const InvoicesScreen());
      await settle(tester);
      expect(find.text('Part paid'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Balance USD 65.00'), findsOneWidget);
      // A paid invoice has no due date line.
      expect(find.text('Due 4 Dec 2026'), findsNWidgets(2));
      expect(find.text('1 Dec 2026 to 31 Dec 2026'), findsNWidgets(3));
      expect(
        find.bySemanticsLabel(RegExp('^Invoice INV-ZW-2026-000012. Overdue')),
        findsOneWidget,
      );
      expectNoPayment(tester);
    });

    testWidgets('no invoices yet', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/invoices': (_) => {'items': []},
      });
      await pumpInApp(tester, test, const InvoicesScreen());
      await settle(tester);
      expect(find.byKey(const Key('invoices-empty')), findsOneWidget);
    });

    testWidgets('an invoice: lines, tax, receipts, and no payment', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET /v1/me/invoices/inv-1': (_) => invoiceJson()});
      await pumpInApp(tester, test, const InvoiceScreen(id: 'inv-1'));
      await settle(tester);
      expect(find.text('INV-ZW-2026-000012'), findsOneWidget);
      expect(find.text('To Sample Estates'), findsOneWidget);
      expect(find.text('Agency Pro, December 2026'), findsOneWidget);
      expect(find.text('VAT 15%'), findsOneWidget);
      expect(find.text('USD 15.00'), findsOneWidget);
      expect(find.text('USD 115.00'), findsOneWidget);
      expect(find.text('Receipt RCT-ZW-2026-000003'), findsOneWidget);
      expect(
        find.text('USD 50.00 · Bank transfer · 25 Nov 2026'),
        findsOneWidget,
      );
      expect(
        find.text('This invoice cannot be paid in the app.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('invoice-tax-sample')), findsNothing);
      // Read-only: no buttons at all, and nothing about paying.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expectNoPayment(tester);
      expect(test.opened, isEmpty);
    });

    testWidgets('no tax rule, a sample rate, overdue, void and disputed', (
      tester,
    ) async {
      final test = TestServices();
      var json = invoiceJson(tax: false);
      serve(test, {'GET /v1/me/invoices/inv-1': (_) => json});
      await pumpInApp(
        tester,
        test,
        InvoiceScreen(key: const ValueKey(1), id: 'inv-1'),
      );
      await settle(tester);
      expect(find.text('No tax for this market'), findsOneWidget);

      json = invoiceJson(sample: true, status: 'OVERDUE');
      await pumpInApp(
        tester,
        test,
        InvoiceScreen(key: const ValueKey(2), id: 'inv-1'),
      );
      await settle(tester);
      expect(find.text('Sample tax rate (test data)'), findsOneWidget);
      expect(
        find.text(
          'This invoice is overdue. This invoice cannot be paid in the app.',
        ),
        findsOneWidget,
      );

      json = invoiceJson(status: 'VOID', paid: '0.00', payments: const []);
      await pumpInApp(
        tester,
        test,
        InvoiceScreen(key: const ValueKey(3), id: 'inv-1'),
      );
      await settle(tester);
      expect(
        find.text('This invoice was cancelled and does not need to be paid.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('invoice-balance')), findsNothing);

      json = invoiceJson(status: 'DISPUTED');
      await pumpInApp(
        tester,
        test,
        InvoiceScreen(key: const ValueKey(4), id: 'inv-1'),
      );
      await settle(tester);
      expect(
        find.text(
          'This invoice is being reviewed by RightProperty365 Finance.',
        ),
        findsOneWidget,
      );
    });

    testWidgets("another payer's invoice says so", (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/invoices/inv-1': (_) => failure(404, 'NOT_FOUND'),
      });
      await expectLater(
        test.services.invoices.get('inv-1'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('owners and managers'),
          ),
        ),
      );
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/invoices': (_) => {
          'items': [invoiceJson()],
        },
        'GET /v1/me/invoices/inv-1': (_) => invoiceJson(sample: true),
      });
      await pumpInApp(tester, test, const InvoicesScreen(), textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const InvoiceScreen(id: 'inv-1'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  test('invoice and subscription links open the invoices, never the '
      'payment page', () async {
    final app = TestServices();
    Future<String> where(String link) async =>
        switch (await resolveNotificationLink(link, app.services)) {
          InApp(:final location) => location,
          OnWebsite(:final url) => 'web $url',
        };
    expect(await where('/account/invoices/inv-1'), Routes.invoice('inv-1'));
    expect(await where('/account/invoices'), Routes.invoices);
    expect(await where('/account/subscription'), Routes.invoices);
    expect(await where('/account/subscriptions/sub-9'), Routes.invoices);
  });
}
