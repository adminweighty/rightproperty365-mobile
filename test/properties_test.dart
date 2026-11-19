import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/properties/my_tenancy.dart';
import 'package:rightproperty365/features/properties/properties_repository.dart';
import 'package:rightproperty365/features/properties/properties_screens.dart';

import 'api_routes.dart';
import 'contacts_test.dart' as crm show contactJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const base = '/v1/agent/organisations/org-1';
const book = ContactBook(id: 'org-1', name: 'Sample Estates', canWrite: true);

Map<String, dynamic> propertyJson({
  String id = 'p-1',
  String name = 'Avondale Court',
  List<Map<String, dynamic>>? units,
  int occupied = 1,
  int open = 1,
}) {
  final u =
      units ??
      [
        {
          'id': 'u-1',
          'label': 'Flat 1',
          'position': 1,
          'active_tenancy_id': 't-1',
        },
        {
          'id': 'u-2',
          'label': 'Flat 2',
          'position': 2,
          'active_tenancy_id': null,
        },
        {
          'id': 'u-3',
          'label': 'Flat 3',
          'position': 3,
          'active_tenancy_id': null,
        },
      ];
  return {
    'id': id,
    'name': name,
    'address': '12 King George Road, Avondale, Harare',
    'market_code': 'ZW',
    'listing': null,
    'notes': '',
    'units': u,
    'unit_count': u.length,
    'lettable_units': u.isEmpty ? 1 : u.length,
    'occupied_units': occupied,
    'active_tenancy_id': null,
    'open_tenancies': open,
    'created_by': {'user_id': 'u-9', 'name': 'Rudo Moyo'},
    'created_at': '2026-11-01T09:00:00Z',
    'updated_at': '2026-11-01T09:00:00Z',
    'can': {'edit': true, 'delete': open == 0},
  };
}

Map<String, dynamic> tenancyJson({
  String id = 't-1',
  String status = 'ACTIVE',
  String? endDate = '2027-09-30',
  bool mine = false,
}) => {
  'id': id,
  'status': status,
  'status_label': switch (status) {
    'DRAFT' => 'Draft',
    'ACTIVE' => 'Active',
    'ENDED' => 'Ended',
    _ => 'Terminated early',
  },
  if (mine) 'managed_by': {'kind': 'ORGANISATION', 'name': 'Sample Estates'},
  'property': {
    if (!mine) 'id': 'p-1',
    'name': 'Avondale Court',
    'address': '12 King George Road, Avondale, Harare',
    'market_code': 'ZW',
    if (!mine) 'archived': false,
  },
  'unit': mine
      ? {'label': 'Flat 1'}
      : {'id': 'u-1', 'label': 'Flat 1', 'archived': false},
  'tenants': [
    mine
        ? {'name': 'Kudzai Sithole'}
        : {'id': 'c-1', 'name': 'Kudzai Sithole', 'live': true},
  ],
  'landlords': [
    mine
        ? {'name': 'Tapiwa Chirwa'}
        : {'id': 'c-2', 'name': 'Tapiwa Chirwa', 'live': false},
  ],
  'lease': {'id': 'l-1', 'reference': 'RPL-2026-900001'},
  'rent': {
    'amount': '950.00',
    'currency': 'USD',
    'minor_unit': 2,
    'frequency': 'MONTHLY',
    'frequency_label': 'Monthly',
    'due_day': 1,
  },
  'deposit': {'amount': '950.00', 'currency': 'USD', 'minor_unit': 2},
  'start_date': '2026-10-01',
  'end_date': endDate,
  'ended_on': null,
  if (!mine) ...{
    'end_reason': null,
    'notes': 'Keys collected.',
    'created_by': {'user_id': 'u-9', 'name': 'Rudo Moyo'},
    'created_at': '2026-09-20T09:00:00Z',
    'updated_at': '2026-10-01T09:00:00Z',
    'can': {
      'edit': true,
      'activate': status == 'DRAFT',
      'end': status == 'ACTIVE',
      'delete': status == 'DRAFT',
    },
  },
};

Map<String, dynamic> optionsJson({bool write = true}) => {
  'frequencies': [
    {'code': 'WEEKLY', 'label': 'Weekly'},
    {'code': 'MONTHLY', 'label': 'Monthly'},
    {'code': 'QUARTERLY', 'label': 'Quarterly'},
    {'code': 'ANNUALLY', 'label': 'Annually'},
  ],
  'statuses': [],
  'currencies': [
    {'code': 'JPY', 'minor_unit': 0},
    {'code': 'USD', 'minor_unit': 2},
  ],
  'permissions': {'write': write},
};

Map<String, dynamic> tenancyPage(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'page_size': 50,
  'status_counts': {'DRAFT': 0, 'ACTIVE': 1, 'ENDED': 1, 'TERMINATED': 0},
};

void main() {
  group('the properties API', () {
    test('reads properties and tenancies, and the tenant\'s own', () async {
      final (:api, :requests) = routedApi({
        'GET $base/properties': (_) => {
          'items': [propertyJson()],
          'total': 1,
          'page': 1,
          'page_size': 50,
        },
        'GET $base/tenancies': (_) => tenancyPage([tenancyJson()]),
        'GET /v1/me/tenancies': (_) => {
          'items': [tenancyJson(mine: true)],
        },
      });
      final repo = PropertiesRepository(api);
      final page = await repo.properties('org-1', query: 'avon');
      expect(requests.last.url.queryParameters['q'], 'avon');
      final p = page.items.single;
      expect(p.occupancy, '1 of 3 units let');
      expect(p.units.first.occupied, isTrue);
      expect(p.canDelete, isFalse);

      final t = (await repo.tenancies('org-1', status: 'ACTIVE')).items.single;
      expect(requests.last.url.queryParameters['status'], 'ACTIVE');
      expect(t.place, 'Avondale Court, Flat 1');
      expect(t.rent.toString(), 'USD 950.00 monthly, due on day 1');
      expect(t.landlords.single.live, isFalse);
      expect(t.canEnd, isTrue);

      final mine = (await repo.myTenancies()).single;
      expect(mine.managedBy, 'Sample Estates');
      expect(mine.canEnd, isFalse);
      expect(mine.notes, isEmpty);
    });

    test('a property without units is one place, let or vacant', () {
      final p = ManagedProperty.fromJson(
        propertyJson(units: const [], occupied: 0, open: 0),
      );
      expect(p.lettableUnits, 1);
      expect(p.occupancy, 'Vacant');
      expect(p.canDelete, isTrue);
    });

    test('creates a draft with the rent as a string in one currency', () async {
      final (:api, :requests) = routedApi({
        'POST $base/tenancies': (_) =>
            jsonResponse(201, {'tenancy': tenancyJson(status: 'DRAFT')}),
      });
      await PropertiesRepository(api).createTenancy(
        'org-1',
        const TenancyDraft(
          propertyId: 'p-1',
          unitId: 'u-2',
          tenantIds: ['c-1'],
          landlordIds: ['c-2'],
          rentAmount: ' 950.00 ',
          currency: 'USD',
          frequency: 'MONTHLY',
          dueDay: 1,
          depositAmount: '950.00',
          startDate: '2026-12-01',
        ),
      );
      expect(jsonBody(requests.single), {
        'property_id': 'p-1',
        'unit_id': 'u-2',
        'tenants': ['c-1'],
        'landlords': ['c-2'],
        'rent': {
          'amount': '950.00',
          'currency': 'USD',
          'frequency': 'MONTHLY',
          'due_day': 1,
        },
        'deposit': {'amount': '950.00', 'currency': 'USD'},
        'start_date': '2026-12-01',
        'end_date': null,
        'notes': '',
      });
    });

    test('says plainly when a place is already let', () async {
      final (:api, requests: _) = routedApi({
        'POST $base/tenancies/t-2/activate': (_) =>
            apiError(409, 'UNIT_OCCUPIED'),
      });
      await expectLater(
        PropertiesRepository(api).activate('org-1', 't-2'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('already has an active tenancy'),
          ),
        ),
      );
    });

    test('another organisation\'s book is not found', () async {
      final (:api, requests: _) = routedApi({
        'GET $base/properties': (_) => apiError(404, 'BOOK_NOT_FOUND'),
      });
      await expectLater(
        PropertiesRepository(api).properties('org-1'),
        throwsA(
          isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
        ),
      );
    });

    test('checks the rent against the currency\'s decimals', () {
      final o = TenancyOptions.fromJson(optionsJson());
      expect(o.amountProblem('950.00', 'USD'), isNull);
      expect(o.amountProblem('950.001', 'USD'), 'At most 2 decimals for USD.');
      expect(o.amountProblem('5000.5', 'JPY'), 'JPY has no decimals.');
      expect(o.amountProblem('0', 'USD'), 'The amount must be more than zero.');
    });
  });

  group('the properties screens', () {
    void routes(TestServices test, {bool write = true}) => serve(test, {
      'GET $base/properties': (_) => {
        'items': [
          propertyJson(),
          propertyJson(
            id: 'p-2',
            name: 'Borrowdale Cottage',
            units: const [],
            occupied: 1,
          ),
        ],
        'total': 2,
        'page': 1,
        'page_size': 50,
      },
      'GET $base/properties/p-1': (_) => {'property': propertyJson()},
      'GET $base/tenancies': (_) =>
          tenancyPage([tenancyJson(), tenancyJson(id: 't-3', status: 'ENDED')]),
      'GET $base/tenancies/options': (_) => optionsJson(write: write),
      'GET $base/tenancies/t-9': (_) => {
        'tenancy': tenancyJson(id: 't-9', status: 'DRAFT'),
      },
      'POST $base/tenancies/t-9/activate': (_) => {
        'tenancy': tenancyJson(id: 't-9'),
      },
      'GET $base/contacts': (_) => {
        'items': [crm.contactJson(id: 'c-1', name: 'Kudzai Sithole')],
        'total': 1,
        'total_pages': 1,
        'stage_counts': {},
      },
      'POST $base/tenancies': (_) =>
          jsonResponse(201, {'tenancy': tenancyJson(status: 'DRAFT')}),
    });

    testWidgets('list properties with occupancy and tenancies by status', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(tester, test, const PropertiesScreen(books: [book]));
      await settle(tester);
      expect(find.text('Avondale Court'), findsOneWidget);
      expect(find.text('1 of 3 units let'), findsOneWidget);
      expect(find.text('Let'), findsOneWidget);
      expect(find.byKey(const Key('add-property')), findsOneWidget);

      await tester.tap(find.text('Tenancies'));
      await settle(tester);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('USD 950.00 monthly, due on day 1'), findsWidgets);
      await tester.tap(find.byKey(const Key('tenancies-status-ACTIVE')));
      await settle(tester);
      final list = test.workRequests.lastWhere(
        (r) => r.url.path == '$base/tenancies',
      );
      expect(list.url.queryParameters['status'], 'ACTIVE');
    });

    testWidgets('staff see them but cannot change them', (tester) async {
      final test = TestServices();
      routes(test, write: false);
      await pumpInApp(tester, test, const PropertiesScreen(books: [book]));
      await settle(tester);
      expect(find.byKey(const Key('add-property')), findsNothing);
      expect(
        find.text('You can see these but not change them.'),
        findsOneWidget,
      );
    });

    testWidgets('a property shows its units and offers a tenancy', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const ManagedPropertyScreen(book: book, id: 'p-1'),
      );
      await settle(tester);
      expect(find.text('Flat 1'), findsOneWidget);
      // Flat 1 is let: it cannot be removed.
      expect(find.byKey(const Key('remove-unit-u-1')), findsNothing);
      expect(find.byKey(const Key('remove-unit-u-2')), findsOneWidget);
      expect(find.byKey(const Key('new-tenancy')), findsOneWidget);
      expect(find.byKey(const Key('archive-property')), findsNothing);
    });

    testWidgets('sets up a draft tenancy with a tenant from the contacts', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        NewTenancyScreen(
          book: book,
          property: ManagedProperty.fromJson(propertyJson()),
          options: TenancyOptions.fromJson(optionsJson()),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('tenancy-save')));
      await settle(tester);
      expect(find.text('Add at least one tenant.'), findsOneWidget);
      expect(find.text('Choose the unit.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tenancy-unit')));
      await settle(tester);
      await tester.tap(find.text('Flat 2').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('tenancy-add-tenant')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('pick-contact-c-1')));
      await settle(tester);
      expect(find.text('Kudzai Sithole'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tenancy-rent')), '950.005');
      await tester.tap(find.byKey(const Key('tenancy-save')));
      await settle(tester);
      expect(find.text('At most 2 decimals for USD.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('tenancy-rent')), '950.00');
      await tester.tap(find.byKey(const Key('tenancy-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      final body = bodyOf(post);
      expect(body['unit_id'], 'u-2');
      expect(body['tenants'], ['c-1']);
      expect((body['rent'] as Map)['amount'], '950.00');
      expect(body.containsKey('deposit'), isFalse);
    });

    testWidgets('makes a draft active', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(tester, test, const TenancyScreen(book: book, id: 't-9'));
      await settle(tester);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.byKey(const Key('tenancy-delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tenancy-activate')));
      await settle(tester);
      expect(find.text('The tenancy is active.'), findsOneWidget);
      expect(find.byKey(const Key('tenancy-end-now')), findsOneWidget);
      expect(find.byKey(const Key('tenancy-activate')), findsNothing);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const PropertiesScreen(books: [book]),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        NewTenancyScreen(
          book: book,
          property: ManagedProperty.fromJson(propertyJson()),
          options: TenancyOptions.fromJson(optionsJson()),
        ),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('my tenancy', () {
    testWidgets('shows the tenant\'s own tenancy, read only', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/tenancies': (_) => {
          'items': [tenancyJson(mine: true)],
        },
      });
      await pumpInApp(tester, test, const MyTenancyView());
      await settle(tester);
      expect(find.text('Avondale Court, Flat 1'), findsOneWidget);
      expect(find.text('Sample Estates'), findsOneWidget);
      expect(find.text('USD 950.00 monthly, due on day 1'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('says how a tenancy comes to show when there is none', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/tenancies': (_) => {'items': []},
      });
      await pumpInApp(tester, test, const MyTenancyView());
      await settle(tester);
      expect(find.text('No tenancy yet'), findsOneWidget);
      expect(
        find.textContaining('email address you confirmed'),
        findsOneWidget,
      );
    });

    test('nobody else\'s tenancy is found', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/me/tenancies/t-x': (_) => apiError(404, 'TENANCY_NOT_FOUND'),
      });
      await expectLater(
        PropertiesRepository(api).myTenancy('t-x'),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
    });
  });
}
