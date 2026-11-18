import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/ledger/books_screens.dart';
import 'package:rightproperty365/features/ledger/ledger_repository.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const base = '/v1/agent/organisations/org-1/ledger';
const book = ContactBook(id: 'org-1', name: 'Sample Estates', canWrite: true);

Map<String, dynamic> optionsJson({bool write = true, bool export = true}) => {
  'types': [
    {
      'code': 'RENT_RECEIVED',
      'label': 'Rent received',
      'direction': 'IN',
      'cash': true,
      'category': 'rent',
    },
    {
      'code': 'EXPENSE',
      'label': 'Expense',
      'direction': 'OUT',
      'cash': true,
      'category': 'other-expense',
    },
    {
      'code': 'TRANSFER',
      'label': 'Transfer',
      'direction': null,
      'cash': true,
      'category': null,
    },
  ],
  'methods': [
    {'code': 'CASH', 'label': 'Cash'},
    {'code': 'BANK', 'label': 'Bank'},
  ],
  'statuses': [],
  'currencies': [
    {'code': 'JPY', 'minor_unit': 0},
    {'code': 'USD', 'minor_unit': 2},
    {'code': 'ZAR', 'minor_unit': 2},
  ],
  'categories': [
    {'code': 'rent', 'label': 'Rent', 'kind': 'IN'},
    {'code': 'maintenance', 'label': 'Maintenance', 'kind': 'OUT'},
  ],
  'branches': [],
  'permissions': {'write': write, 'manage': write, 'export': export},
};

Map<String, dynamic> entryJson({
  String id = 'e-1',
  String type = 'RENT_RECEIVED',
  String amount = '700.00',
  String currency = 'USD',
  bool out = false,
  bool reconciled = false,
  bool reversed = false,
  bool canReverse = true,
}) => {
  'id': id,
  'type': type,
  'type_label': type == 'REVERSAL' ? 'Reversal' : 'Rent received',
  'direction': out ? 'OUT' : 'IN',
  'category': 'rent',
  'category_label': 'Rent',
  'method': 'BANK',
  'method_label': 'Bank',
  'amount': amount,
  'signed_amount': out ? '-$amount' : amount,
  'currency': currency,
  'minor_unit': 2,
  'effective_date': '2026-11-01',
  'recorded_at': '2026-11-01T09:00:00Z',
  'author': {'user_id': 'u-1', 'name': 'Rudo Moyo'},
  'status': reconciled ? 'RECONCILED' : 'USER_RECORDED_UNVERIFIED',
  'status_label': reconciled
      ? 'Marked reconciled by your team'
      : 'Recorded by you, not verified',
  'reconciliation': reconciled
      ? {
          'at': '2026-11-05T09:00:00Z',
          'by': {'user_id': 'u-1', 'name': 'Rudo Moyo'},
          'note': 'November statement',
        }
      : null,
  'description': 'November rent, flat 4',
  'reference': 'RCPT-0012',
  'branch': null,
  'contact': {'id': 'c-1', 'name': 'Tariro Moyo'},
  'listing': null,
  'lease': null,
  'tenancy_id': null,
  'reversal_of': null,
  'reversed_by': reversed ? 'e-9' : null,
  'correction_of': null,
  'corrected_by': null,
  'transfer_pair': null,
  'settles': null,
  'reason': type == 'REVERSAL' ? 'Entered twice' : null,
  'is_reversed': reversed,
  'cash': true,
  'note_count': 0,
  'attachment_count': 0,
  'can': {
    'reverse': canReverse,
    'correct': canReverse,
    'reconcile': canReverse,
    'note': canReverse,
    'attach': canReverse,
  },
};

Map<String, dynamic> cashbookJson() => {
  'from': '2026-11-01',
  'to': '2026-11-19',
  'by': null,
  'currencies': [
    {
      'currency': 'USD',
      'minor_unit': 2,
      'opening_balance': '500.00',
      'in': '700.00',
      'out': '0.00',
      'net': '700.00',
      'closing_balance': '1200.00',
      'entry_count': 1,
      'groups': null,
      'entries': [
        {
          'entry': entryJson(),
          'currency': 'USD',
          'minor_unit': 2,
          'in': '700.00',
          'out': '0.00',
          'running_balance': '1200.00',
        },
      ],
    },
    {
      'currency': 'ZAR',
      'minor_unit': 2,
      'opening_balance': '0.00',
      'in': '0.00',
      'out': '450.00',
      'net': '-450.00',
      'closing_balance': '-450.00',
      'entry_count': 1,
      'groups': null,
      'entries': [],
    },
  ],
};

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
  'items': items,
  'page': 1,
  'page_size': 50,
  'total': items.length,
  'total_pages': 1,
};

void main() {
  group('the books data', () {
    test('amounts are checked against the currency\'s decimals', () {
      final o = LedgerOptions.fromJson(optionsJson());
      expect(o.amountProblem('700', 'USD'), isNull);
      expect(o.amountProblem('700.5', 'USD'), isNull);
      expect(o.amountProblem('700.555', 'USD'), 'At most 2 decimals for USD.');
      expect(o.amountProblem('1.5', 'JPY'), 'JPY has no decimals.');
      expect(o.amountProblem('0', 'USD'), 'The amount must be more than zero.');
      expect(o.amountProblem('-5', 'USD'), contains('Enter an amount'));
    });

    test('lists, totals per currency, posts and reverses', () async {
      final (:api, :requests) = routedApi({
        'GET $base/options': (_) => optionsJson(),
        'GET $base/entries': (_) => page([entryJson()]),
        'GET $base/reports/cashbook': (_) => cashbookJson(),
        'POST $base/entries': (_) => jsonResponse(201, {
          'entry': entryJson(id: 'e-2'),
          'created': [entryJson(id: 'e-2')],
        }),
        'POST $base/entries/e-1/reverse': (_) => jsonResponse(201, {
          'entry': entryJson(id: 'e-9', type: 'REVERSAL', out: true),
          'created': [],
          'updated': [],
        }),
        'POST $base/entries/e-2/reverse': (_) =>
            apiError(409, 'LEDGER_ENTRY_ALREADY_REVERSED'),
        'GET /v1/agent/organisations/org-9/ledger/options': (_) =>
            apiError(404, 'BOOK_NOT_FOUND'),
      });
      final repo = LedgerRepository(api);
      await repo.entries('org-1', currency: 'USD', from: '2026-11-01');
      expect(requests.last.url.queryParameters, {
        'currency': 'USD',
        'from': '2026-11-01',
        'page': '1',
        'page_size': '50',
      });
      final totals = await repo.cashbook(
        'org-1',
        from: '2026-11-01',
        to: '2026-11-19',
      );
      expect(totals.map((t) => t.currency), ['USD', 'ZAR']);
      expect(totals.first.runningBalance['e-1'], '1200.00');

      await repo.create(
        'org-1',
        const LedgerDraft(
          type: 'TRANSFER',
          method: 'CASH',
          transferToMethod: 'BANK',
          amount: ' 100 ',
          currency: 'USD',
          effectiveDate: '2026-11-02',
          description: 'Banking the cash',
        ),
      );
      expect(jsonBody(requests.last), {
        'type': 'TRANSFER',
        'method': 'CASH',
        'transfer_to': {'method': 'BANK', 'branch': null},
        'amount': '100',
        'currency': 'USD',
        'effective_date': '2026-11-02',
        'description': 'Banking the cash',
      });
      final reversal = await repo.reverse('org-1', 'e-1', ' Entered twice ');
      expect(jsonBody(requests.last), {'reason': 'Entered twice'});
      expect(reversal.isReversal, isTrue);
      await expectLater(
        repo.reverse('org-1', 'e-2', 'x'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            'This entry has already been reversed.',
          ),
        ),
      );
      await expectLater(
        repo.options('org-9'),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
    });
  });

  group('the books screens', () {
    testWidgets('per-currency totals, never combined, and honest labels', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET $base/options': (_) => optionsJson(export: false),
        'GET $base/reports/cashbook': (_) => cashbookJson(),
        'GET $base/entries': (_) => page([
          entryJson(),
          entryJson(id: 'e-3', reconciled: true, amount: '120.00'),
          entryJson(
            id: 'e-4',
            currency: 'ZAR',
            amount: '450.00',
            out: true,
            reversed: true,
          ),
        ]),
      });
      await pumpInApp(tester, test, const BooksScreen(books: [book]));
      await settle(tester);
      expect(find.byKey(const Key('totals-USD')), findsOneWidget);
      expect(find.byKey(const Key('totals-ZAR')), findsOneWidget);
      expect(find.text('USD 1200.00'), findsOneWidget);
      expect(find.text('ZAR -450.00'), findsWidgets);
      expect(find.text('Recorded by you, not verified'), findsWidgets);
      expect(find.text('Marked reconciled by your team'), findsOneWidget);
      expect(
        find
            .textContaining('bank', findRichText: true)
            .evaluate()
            .where(
              (e) =>
                  (e.widget is Text) &&
                  ((e.widget as Text).data ?? '').toLowerCase().contains(
                    'verified by',
                  ),
            ),
        isEmpty,
      );
      expect(find.text('Reversed'), findsOneWidget);
      expect(find.textContaining('and so are exports'), findsNothing);
      // A running balance only once one currency is chosen.
      expect(find.textContaining('Balance USD'), findsNothing);
      expect(find.byKey(const Key('record-entry')), findsOneWidget);
    });

    testWidgets('staff see the books without recording', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $base/options': (_) => optionsJson(write: false, export: false),
        'GET $base/reports/cashbook': (_) => cashbookJson(),
        'GET $base/entries': (_) => page([entryJson(canReverse: false)]),
        'GET $base/entries/e-1': (_) => {
          'entry': entryJson(canReverse: false),
          'notes': [],
          'attachments': [],
          'related': [],
        },
      });
      await pumpInApp(tester, test, const BooksScreen(books: [book]));
      await settle(tester);
      expect(find.byKey(const Key('record-entry')), findsNothing);
      await pumpInApp(
        tester,
        test,
        const LedgerEntryScreen(book: book, id: 'e-1'),
      );
      await settle(tester);
      expect(find.byKey(const Key('entry-reverse')), findsNothing);
    });

    testWidgets('recording an expense with a receipt photo', (tester) async {
      final test = TestServices();
      test.pickedFile = (bytes: [137, 80, 78, 71], name: 'receipt.png');
      serve(test, {
        'POST $base/entries': (request) => jsonResponse(201, {
          'entry': entryJson(id: 'e-5', out: true),
          'created': [],
        }),
        'POST $base/entries/e-5/attachments': (_) =>
            jsonResponse(201, {'attachment': {}}),
      });
      await pumpInApp(
        tester,
        test,
        NewLedgerEntryScreen(
          book: book,
          options: LedgerOptions.fromJson(optionsJson()),
        ),
      );
      await settle(tester);
      expect(
        find.textContaining('Recorded by you, not verified'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('entry-amount')), '12.555');
      await tester.tap(find.byKey(const Key('entry-save')));
      await settle(tester);
      expect(find.text('At most 2 decimals for USD.'), findsOneWidget);
      expect(test.workRequests, isEmpty);

      await tester.enterText(find.byKey(const Key('entry-amount')), '12.50');
      await tester.enterText(
        find.byKey(const Key('entry-description')),
        'Light bulbs',
      );
      await tester.ensureVisible(find.byKey(const Key('receipt-camera')));
      await tester.tap(find.byKey(const Key('receipt-camera')));
      await settle(tester);
      expect(test.pickedFrom, ['camera']);
      expect(find.text('receipt.png'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('entry-save')));
      await tester.tap(find.byKey(const Key('entry-save')));
      await settle(tester);
      final posted = bodyOf(
        test.workRequests.firstWhere((r) => r.url.path.endsWith('/entries')),
      );
      expect(posted['type'], 'RENT_RECEIVED');
      expect(posted['amount'], '12.50');
      expect(posted.containsKey('direction'), isFalse);
      expect(test.workRequests.last.url.path, '$base/entries/e-5/attachments');
    });

    testWidgets('reversing asks why and keeps both entries', (tester) async {
      final test = TestServices();
      var reversed = false;
      serve(test, {
        'GET $base/entries/e-1': (_) => {
          'entry': entryJson(reversed: reversed),
          'notes': [],
          'attachments': [],
          'related': [
            if (reversed) entryJson(id: 'e-9', type: 'REVERSAL', out: true),
          ],
        },
        'POST $base/entries/e-1/reverse': (_) {
          reversed = true;
          return jsonResponse(201, {
            'entry': entryJson(id: 'e-9', type: 'REVERSAL', out: true),
            'created': [],
            'updated': [],
          });
        },
      });
      await pumpInApp(
        tester,
        test,
        const LedgerEntryScreen(book: book, id: 'e-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('entry-reverse')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('dialog-text')),
        'Entered twice',
      );
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await settle(tester);
      expect(bodyOf(test.workRequests.lastWhere((r) => r.method == 'POST')), {
        'reason': 'Entered twice',
      });
      expect(find.text('Linked entries'), findsOneWidget);
      expect(find.byKey(const Key('entry-reverse')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $base/options': (_) => optionsJson(),
        'GET $base/reports/cashbook': (_) => cashbookJson(),
        'GET $base/entries': (_) => page([entryJson()]),
      });
      await pumpInApp(
        tester,
        test,
        const BooksScreen(books: [book]),
        textScale: 2,
        size: const Size(390, 2600),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
