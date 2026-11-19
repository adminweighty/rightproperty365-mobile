import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/properties/properties_repository.dart';
import 'package:rightproperty365/features/properties/rent_repository.dart';
import 'package:rightproperty365/features/properties/rent_screens.dart';

import 'api_routes.dart';
import 'properties_test.dart' show tenancyJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const org = '/v1/agent/organisations/org-1';
const tenancyPath = '$org/tenancies/t-1';

Map<String, dynamic> dueJson({
  String id = 'd-1',
  String date = '2026-10-01',
  String status = 'PAID',
  String paid = '950.00',
  String outstanding = '0.00',
  String waived = '0.00',
  bool overdue = false,
  int days = 0,
  bool tenant = false,
}) => {
  'id': id,
  'tenancy_id': 't-1',
  'sequence': 1,
  'due_date': date,
  // A monthly period: to the day before the next due.
  'period': {
    'from': date,
    'to': DateTime.parse(date)
        .copyWith(month: DateTime.parse(date).month + 1, day: 0)
        .toIso8601String()
        .substring(0, 10),
  },
  'amount': '950.00',
  'currency': 'USD',
  'minor_unit': 2,
  'paid': paid,
  'waived': waived,
  'outstanding': outstanding,
  'status': status,
  'status_label': switch (status) {
    'PAID' => 'Paid',
    'PART_PAID' => 'Part paid',
    'WAIVED' => 'Waived',
    _ => 'Due',
  },
  'overdue': overdue,
  'days_overdue': days,
  'waiver': status == 'WAIVED'
      ? {
          'at': '2026-11-10T09:00:00Z',
          if (!tenant) 'by': {'user_id': 'u-1', 'name': 'Rudo Moyo'},
          if (!tenant) 'reason': 'Storm damage',
        }
      : null,
  if (!tenant) 'can': {'waive': status == 'DUE' || status == 'PART_PAID'},
};

Map<String, dynamic> scheduleJson({bool tenant = false}) {
  final part = dueJson(
    id: 'd-2',
    date: '2026-11-01',
    status: 'PART_PAID',
    paid: '500.00',
    outstanding: '450.00',
    overdue: true,
    days: 18,
    tenant: tenant,
  );
  return {
    'items': [dueJson(tenant: tenant), part],
    'summary': {
      'currency': 'USD',
      'minor_unit': 2,
      'charged': '1900.00',
      'paid': '1450.00',
      'waived': '0.00',
      'outstanding': '450.00',
      'overdue': '450.00',
      'overdue_count': 1,
      'paid_in_advance': '0.00',
      'next_due': dueJson(
        id: 'd-3',
        date: '2026-12-01',
        status: 'DUE',
        paid: '0.00',
        outstanding: '950.00',
        tenant: tenant,
      ),
    },
    'schedule': {
      'rolling': false,
      'through': '2027-09-30',
      'count': 12,
      'rule': 'Monthly on day 1',
    },
  };
}

Map<String, dynamic> receiptJson({
  bool reversed = false,
  bool tenant = false,
}) => {
  'id': 'r-1',
  if (!tenant) 'tenancy_id': 't-1',
  'amount': '500.00',
  'currency': 'USD',
  'minor_unit': 2,
  'method': 'BANK',
  'method_label': 'Bank',
  'received_on': '2026-11-02',
  'reference': 'FNB 4471',
  if (!tenant) 'tenant': {'id': 'c-1', 'name': 'Kudzai Sithole', 'live': true},
  'status': reversed ? 'REVERSED' : 'RECORDED',
  'status_label': reversed ? 'Reversed' : 'Recorded',
  'allocations': [
    {
      'due_id': 'd-2',
      'due_date': '2026-11-01',
      'amount': '500.00',
      'currency': 'USD',
      'minor_unit': 2,
    },
  ],
  if (!tenant) ...{
    'ledger_entry_id': 'le-1',
    'ledger_status': 'USER_RECORDED_UNVERIFIED',
    'ledger_status_label': 'Recorded by you, not verified',
    'reversal': reversed
        ? {
            'ledger_entry_id': 'le-2',
            'reversed_on': '2026-11-05',
            'at': '2026-11-05T09:00:00Z',
          }
        : null,
    'recorded_by': {'user_id': 'u-1', 'name': 'Rudo Moyo'},
    'recorded_at': '2026-11-02T09:00:00Z',
    'can': {'reverse': !reversed},
  },
  if (tenant) 'reversed_on': reversed ? '2026-11-05' : null,
};

Map<String, dynamic> statementJson() => {
  'tenancy': {},
  'from': '2026-10-01',
  'to': '2026-11-19',
  'generated_at': '2026-11-19T09:00:00Z',
  'currencies': [
    {
      'currency': 'USD',
      'minor_unit': 2,
      'opening_balance': '0.00',
      'charged': '1900.00',
      'paid': '1450.00',
      'reversed': '0.00',
      'waived': '0.00',
      'closing_balance': '450.00',
      'overdue': '450.00',
      'lines': [
        {
          'date': '2026-10-01',
          'type': 'CHARGE',
          'description': 'Rent 2026-10-01 to 2026-10-31',
          'reference': '',
          'currency': 'USD',
          'debit': '950.00',
          'credit': '0.00',
          'balance': '950.00',
          'due_id': 'd-1',
          'receipt_id': null,
        },
        {
          'date': '2026-10-01',
          'type': 'PAYMENT',
          'description': 'Payment (Bank)',
          'reference': 'FNB 4400',
          'currency': 'USD',
          'debit': '0.00',
          'credit': '950.00',
          'balance': '0.00',
          'due_id': null,
          'receipt_id': 'r-0',
        },
      ],
    },
  ],
};

Map<String, dynamic> bucket(String b, String cur, String amount, int n) => {
  'bucket': b,
  'currency': cur,
  'minor_unit': 2,
  'outstanding': amount,
  'count': n,
};

Map<String, dynamic> arrearsJson() => {
  'as_of': '2026-11-19',
  'currencies': [
    for (final cur in ['USD', 'ZAR'])
      {
        'currency': cur,
        'minor_unit': 2,
        'outstanding': cur == 'USD' ? '1150.00' : '4000.00',
        'count': 2,
        'buckets': [
          bucket(
            '0-30',
            cur,
            cur == 'USD' ? '450.00' : '0.00',
            cur == 'USD' ? 1 : 0,
          ),
          bucket(
            '31-60',
            cur,
            cur == 'USD' ? '700.00' : '4000.00',
            cur == 'USD' ? 1 : 2,
          ),
          bucket('61-90', cur, '0.00', 0),
          bucket('90+', cur, '0.00', 0),
        ],
        'tenancies': [
          {
            'tenancy': {
              'id': 't-$cur',
              'status': 'ACTIVE',
              'status_label': 'Active',
              'property': {
                'id': 'p-2',
                'name': cur == 'USD' ? 'Borrowdale Cottage' : 'Sandton Flat',
                'archived': false,
              },
              'unit': null,
              'tenants': [
                {'id': 'c-2', 'name': 'Tariro Moyo', 'live': true},
              ],
            },
            'currency': cur,
            'minor_unit': 2,
            'outstanding': cur == 'USD' ? '1150.00' : '4000.00',
            'count': 2,
            'oldest_due_date': '2026-10-05',
            'days_overdue': 45,
            'buckets': [],
          },
        ],
      },
  ],
};

final tenancy = Tenancy.fromJson(tenancyJson());

void main() {
  group('the rent API', () {
    test('reads the schedule per currency, never combined', () async {
      final (:api, :requests) = routedApi({
        'GET $tenancyPath/dues': (_) => scheduleJson(),
      });
      final s = await RentRepository(
        api,
      ).schedule(const RentScope.manager('org-1', 't-1'), status: 'PART_PAID');
      expect(requests.single.url.queryParameters['status'], 'PART_PAID');
      expect(s.rule, 'Monthly on day 1');
      expect(s.summary.outstanding.toString(), 'USD 450.00');
      expect(s.summary.nextDue!.dueDate, '2026-12-01');
      expect(s.dues.last.canWaive, isTrue);
      expect(s.dues.first.canWaive, isFalse);
    });

    test('the tenant reads only their own, from their own path', () async {
      final (:api, :requests) = routedApi({
        'GET /v1/me/tenancies/t-1/dues': (_) => scheduleJson(tenant: true),
        'GET /v1/me/tenancies/t-1/receipts': (_) => {
          'items': [receiptJson(tenant: true, reversed: true)],
        },
        'GET /v1/me/tenancies/t-2/dues': (_) =>
            apiError(404, 'TENANCY_NOT_FOUND'),
      });
      final rent = RentRepository(api);
      const mine = RentScope.tenant('t-1');
      final s = await rent.schedule(mine);
      expect(s.dues.last.canWaive, isFalse);
      final r = (await rent.receipts(mine)).single;
      expect(r.reversed, isTrue);
      expect(r.reversedOn, '2026-11-05');
      expect(r.ledgerEntryId, isNull);
      await expectLater(
        rent.schedule(const RentScope.tenant('t-2')),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
    });

    test(
      'records a receipt in the rent\'s currency, oldest dues first',
      () async {
        final (:api, :requests) = routedApi({
          'POST $tenancyPath/receipts': (_) => jsonResponse(201, {
            'receipt': receiptJson(),
            'dues': [dueJson(id: 'd-2', status: 'PAID')],
          }),
        });
        final done = await RentRepository(api).record(
          'org-1',
          't-1',
          amount: ' 500.00 ',
          currency: 'USD',
          method: 'BANK',
          receivedOn: '2026-11-02',
          reference: 'FNB 4471',
          tenantContactId: 'c-1',
        );
        expect(jsonBody(requests.single), {
          'amount': '500.00',
          'currency': 'USD',
          'method': 'BANK',
          'received_on': '2026-11-02',
          'reference': 'FNB 4471',
          'tenant_contact_id': 'c-1',
        });
        expect(done.receipt.ledgerStatusLabel, 'Recorded by you, not verified');
        expect(done.dues.single.status, 'PAID');
      },
    );

    test('waives with a reason; a paid due says why it cannot be', () async {
      final (:api, :requests) = routedApi({
        'POST $org/dues/d-2/waive': (_) => {
          'due': dueJson(id: 'd-2', status: 'WAIVED', waived: '450.00'),
        },
        'POST $org/dues/d-1/waive': (_) =>
            apiError(409, 'RENT_DUE_NOT_WAIVABLE'),
      });
      final rent = RentRepository(api);
      final due = await rent.waive('org-1', 'd-2', ' Storm damage ');
      expect(jsonBody(requests.first), {'reason': 'Storm damage'});
      expect(due.waiverReason, 'Storm damage');
      await expectLater(
        rent.waive('org-1', 'd-1', 'x'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('already paid or waived'),
          ),
        ),
      );
    });

    test('arrears come per currency with the four age bands', () async {
      final (:api, requests: _) = routedApi({
        'GET $org/arrears': (_) => arrearsJson(),
      });
      final a = await RentRepository(api).arrears('org-1');
      expect(a.currencies.map((c) => c.currency), ['USD', 'ZAR']);
      expect(a.currencies.first.buckets.map((b) => b.bucket), [
        '0-30',
        '31-60',
        '61-90',
        '90+',
      ]);
      expect(a.currencies.first.tenancies.single.daysOverdue, 45);
    });

    test('another organisation\'s book is not found', () async {
      final (:api, requests: _) = routedApi({
        'GET $org/arrears': (_) => apiError(404, 'BOOK_NOT_FOUND'),
      });
      await expectLater(
        RentRepository(api).arrears('org-1'),
        throwsA(
          isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
        ),
      );
    });
  });

  group('the rent screens', () {
    void routes(TestServices test, {bool reversed = false}) => serve(test, {
      'GET $tenancyPath/dues': (_) => scheduleJson(),
      'GET $tenancyPath/receipts': (_) => {
        'items': [receiptJson(reversed: reversed)],
      },
      'GET $tenancyPath/statement': (_) => statementJson(),
      'POST $org/dues/d-2/waive': (_) => {
        'due': dueJson(id: 'd-2', status: 'WAIVED', waived: '450.00'),
      },
      'POST $org/ledger/entries/le-1/reverse': (_) => {
        'entry': {
          'id': 'le-2',
          'type': 'REVERSAL',
          'type_label': 'Reversal',
          'direction': 'OUT',
          'amount': '500.00',
          'signed_amount': '-500.00',
          'currency': 'USD',
          'minor_unit': 2,
          'effective_date': '2026-11-05',
          'status': 'USER_RECORDED_UNVERIFIED',
          'status_label': 'Recorded by you, not verified',
        },
        'created': true,
      },
      'POST $tenancyPath/receipts': (_) => jsonResponse(201, {
        'receipt': receiptJson(),
        'dues': [dueJson(id: 'd-2', status: 'PAID')],
      }),
    });

    testWidgets('the summary shows outstanding and overdue in one currency', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: RentSummaryCard(
            scope: const RentScope.manager('org-1', 't-1'),
            tenancy: tenancy,
            canWrite: true,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('USD 450.00'), findsNWidgets(2));
      expect(find.text('Overdue (1 due)'), findsOneWidget);
      expect(find.text('Next due 1 Dec 2026'), findsOneWidget);
    });

    testWidgets('waives a due with a reason', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        RentScreen(
          scope: const RentScope.manager('org-1', 't-1'),
          tenancy: tenancy,
          canWrite: true,
        ),
      );
      await settle(tester);
      expect(
        find.text('Outstanding USD 450.00, 18 days overdue'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('waive-d-1')), findsNothing);
      await tester.tap(find.byKey(const Key('waive-d-2')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Storm damage');
      await tester.tap(find.text('Waive').last);
      await settle(tester);
      final waive = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(waive.url.path, '$org/dues/d-2/waive');
      expect(bodyOf(waive), {'reason': 'Storm damage'});
    });

    testWidgets('receipts carry the ledger\'s wording and reverse there', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        RentScreen(
          scope: const RentScope.manager('org-1', 't-1'),
          tenancy: tenancy,
          canWrite: true,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Receipts'));
      await settle(tester);
      expect(find.text('Recorded by you, not verified'), findsOneWidget);
      expect(
        find.textContaining('It is not a bank confirmation'),
        findsOneWidget,
      );
      expect(
        find.text('Against the due of 1 Nov 2026 (USD 500.00)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reverse-r-1')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Bounced');
      await tester.tap(find.text('Reverse').last);
      await settle(tester);
      final reverse = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(reverse.url.path, '$org/ledger/entries/le-1/reverse');
    });

    testWidgets('records a receipt in the rent\'s currency only', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        RecordReceiptScreen(book: 'org-1', tenancy: tenancy),
      );
      await settle(tester);
      expect(find.textContaining('Other currencies'), findsOneWidget);
      // There is no currency to choose: the rent's is the only one.
      expect(find.byKey(const Key('receipt-currency')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('receipt-amount')),
        '500.001',
      );
      await tester.tap(find.byKey(const Key('receipt-save')));
      await settle(tester);
      expect(find.text('At most 2 decimals for USD.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('receipt-amount')), '500');
      await tester.enterText(
        find.byKey(const Key('receipt-reference')),
        'FNB 4471',
      );
      await tester.tap(find.byKey(const Key('receipt-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post)['currency'], 'USD');
      expect(bodyOf(post)['amount'], '500');
      expect(bodyOf(post)['tenant_contact_id'], 'c-1');
      expect(bodyOf(post).containsKey('allocations'), isFalse);
    });

    testWidgets('the statement shows each currency\'s own balance', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        RentScreen(
          scope: const RentScope.manager('org-1', 't-1'),
          tenancy: tenancy,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Statement'));
      await settle(tester);
      expect(find.byKey(const Key('statement-USD')), findsOneWidget);
      expect(find.text('USD 450.00'), findsWidgets);
      expect(find.byKey(const Key('record-receipt')), findsNothing);
    });

    testWidgets('the tenant reads, with nothing to change', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/tenancies/t-1/dues': (_) => scheduleJson(tenant: true),
        'GET /v1/me/tenancies/t-1/receipts': (_) => {
          'items': [receiptJson(tenant: true)],
        },
      });
      await pumpInApp(
        tester,
        test,
        RentScreen(scope: const RentScope.tenant('t-1'), tenancy: tenancy),
      );
      await settle(tester);
      expect(find.byKey(const Key('record-receipt')), findsNothing);
      expect(find.text('Waive'), findsNothing);
      await tester.tap(find.text('Payments'));
      await settle(tester);
      expect(find.text('Reverse'), findsNothing);
      expect(find.text('Recorded by you, not verified'), findsNothing);
    });

    testWidgets('arrears: one table per currency, never a total', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET $org/arrears': (_) => arrearsJson()});
      final opened = <String>[];
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: SingleChildScrollView(
            child: ArrearsView(book: 'org-1', onOpen: opened.add),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('arrears-USD')), findsOneWidget);
      expect(find.byKey(const Key('arrears-ZAR')), findsOneWidget);
      expect(find.text('31-60 days'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('arrears-tenancy-t-USD')));
      expect(opened, ['t-USD']);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        RentScreen(
          scope: const RentScope.manager('org-1', 't-1'),
          tenancy: tenancy,
          canWrite: true,
        ),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Receipts'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        RecordReceiptScreen(book: 'org-1', tenancy: tenancy),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
