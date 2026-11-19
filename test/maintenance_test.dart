import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';
import 'package:rightproperty365/features/properties/maintenance_repository.dart';
import 'package:rightproperty365/features/properties/maintenance_screens.dart';
import 'package:rightproperty365/features/properties/properties_repository.dart';

import 'api_routes.dart';
import 'properties_test.dart' show propertyJson, tenancyJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, dashboard, serve, settle;

const base = '/v1/agent/organisations/org-1/maintenance';
const book = ContactBook(id: 'org-1', name: 'Sample Estates', canWrite: true);

Map<String, dynamic> optionsJson({bool write = true}) => {
  'categories': [
    {'code': 'plumbing', 'label': 'Plumbing'},
    {'code': 'electrical', 'label': 'Electrical'},
  ],
  'priorities': [
    {'code': 'low', 'label': 'Low'},
    {'code': 'normal', 'label': 'Normal'},
    {'code': 'high', 'label': 'High'},
  ],
  'statuses': [
    {'code': 'NEW', 'label': 'New'},
  ],
  'transitions': {},
  'currencies': [
    {'code': 'USD', 'minor_unit': 2},
    {'code': 'JPY', 'minor_unit': 0},
  ],
  'methods': [
    {'code': 'CASH', 'label': 'Cash'},
    {'code': 'BANK', 'label': 'Bank'},
  ],
  'photo_rules': {'max_photos': 10, 'max_bytes': 10485760, 'types': []},
  'permissions': {'write': write},
};

Map<String, dynamic> requestJson({
  String id = 'm-1',
  String status = 'ASSIGNED',
  String title = 'Kitchen tap leaking',
  bool write = true,
  bool tenant = false,
}) => {
  'id': id,
  'reference': 'RPM-2026-900001',
  'status': status,
  'status_label': switch (status) {
    'NEW' => 'New',
    'ASSIGNED' => 'Assigned',
    'IN_PROGRESS' => 'In progress',
    'CLOSED' => 'Closed',
    _ => status,
  },
  'category': {'code': 'plumbing', 'label': 'Plumbing'},
  'priority': {'code': 'high', 'label': 'High'},
  'title': title,
  'description': 'Drips all night.',
  'property': tenant
      ? {'name': 'Avondale Court'}
      : {
          'id': 'p-1',
          'name': 'Avondale Court',
          'address': '12 King George Road',
          'market_code': 'ZW',
          'archived': false,
        },
  'unit': tenant
      ? {'label': 'Flat 1'}
      : {'id': 'u-1', 'label': 'Flat 1', 'archived': false},
  'raised_by': tenant
      ? {'kind': 'TENANT', 'you': true}
      : {'kind': 'TENANT', 'user_id': 'u-7', 'name': 'Kudzai Sithole'},
  'provider': tenant
      ? {'name': 'Sample Plumbers'}
      : {
          'id': 'prov-1',
          'kind': 'service-providers',
          'slug': 'sample-plumbers',
          'name': 'Sample Plumbers',
        },
  if (!tenant) ...{
    'tenancy_id': 't-1',
    'tenancy': {
      'id': 't-1',
      'status': 'ACTIVE',
      'status_label': 'Active',
      'property': {'id': 'p-1', 'name': 'Avondale Court', 'archived': false},
      'unit': {'id': 'u-1', 'label': 'Flat 1', 'archived': false},
      'tenants': [
        {'id': 'c-1', 'name': 'Kudzai Sithole', 'live': true},
      ],
    },
    'assignment': {
      'provider': {'id': 'prov-1', 'name': 'Sample Plumbers'},
      'enquiry': {'id': 'e-1', 'reference': 'BE-RPM9TAPX'},
      'assigned_at': '2026-11-18T10:00:00Z',
      'assigned_by': {'user_id': 'u-1', 'name': 'Chipo Dube'},
    },
    'photo_count': 0,
    'comment_count': 2,
    'cost_totals': [
      {'currency': 'USD', 'minor_unit': 2, 'amount': '85.00', 'count': 1},
    ],
    'costs': [
      {
        'id': 'cost-1',
        'amount': '85.00',
        'currency': 'USD',
        'minor_unit': 2,
        'description': 'Replace kitchen tap washer',
        'method': 'BANK',
        'method_label': 'Bank',
        'incurred_on': '2026-11-18',
        'ledger_entry_id': 'le-1',
        'ledger_status': 'USER_RECORDED_UNVERIFIED',
        'ledger_status_label': 'Recorded by you, not verified',
        'reversed': false,
        'recorded_by': {'user_id': 'u-1', 'name': 'Chipo Dube'},
        'recorded_at': '2026-11-18T10:00:00Z',
      },
    ],
    'can': {
      'edit': write,
      'transitions': write ? ['IN_PROGRESS', 'CANCELLED'] : [],
      'assign': write,
      'add_cost': write,
      'comment': write,
      'add_photo': write,
    },
  },
  if (tenant) 'can': {'comment': true, 'add_photo': true},
  'photos': [],
  'timeline': [
    {
      'id': 'tl-1',
      'type': 'CREATED',
      'at': '2026-11-17T08:00:00Z',
      'actor': tenant
          ? {'kind': 'TENANT', 'name': 'Kudzai Sithole', 'you': true}
          : {'kind': 'TENANT', 'user_id': 'u-7', 'name': 'Kudzai Sithole'},
      'from_status': null,
      'to_status': 'NEW',
      'text': null,
      'internal': false,
      'details': null,
    },
    {
      'id': 'tl-2',
      'type': 'ASSIGNED',
      'at': '2026-11-18T10:00:00Z',
      'actor': {
        'kind': 'MANAGER',
        'name': tenant ? 'Sample Estates' : 'Chipo Dube',
      },
      'from_status': null,
      'to_status': null,
      'text': null,
      if (!tenant) 'internal': false,
      if (!tenant)
        'details': {
          'provider': {'name': 'Sample Plumbers'},
          'enquiry_reference': 'BE-RPM9TAPX',
        },
    },
  ],
  'created_at': '2026-11-17T08:00:00Z',
  'updated_at': '2026-11-18T10:00:00Z',
  'status_changed_at': '2026-11-18T10:00:00Z',
};

Map<String, dynamic> pageJson(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'page_size': 50,
  'status_counts': {
    'NEW': 1,
    'TRIAGED': 0,
    'ASSIGNED': 1,
    'IN_PROGRESS': 1,
    'RESOLVED': 0,
    'CLOSED': 1,
    'CANCELLED': 0,
  },
};

void main() {
  group('the maintenance API', () {
    test('lists with a status filter and reads a request', () async {
      final (:api, :requests) = routedApi({
        'GET $base': (_) => pageJson([requestJson()]),
        'GET $base/m-1': (_) => {'request': requestJson()},
      });
      final repo = MaintenanceRepository(api);
      final page = await repo.list('org-1', status: 'ASSIGNED', query: 'tap');
      expect(requests.last.url.queryParameters['status'], 'ASSIGNED');
      expect(requests.last.url.queryParameters['q'], 'tap');
      expect(page.statusCounts['CLOSED'], 1);
      final r = await repo.get('org-1', 'm-1');
      expect(r.place, 'Avondale Court, Flat 1');
      expect(r.enquiryReference, 'BE-RPM9TAPX');
      expect(r.costTotals.single.toString(), 'USD 85.00');
      expect(r.transitions, ['IN_PROGRESS', 'CANCELLED']);
      expect(r.timeline, hasLength(2));
    });

    test('assigns once, records a cost and moves the status', () async {
      final (:api, :requests) = routedApi({
        'POST $base/m-1/assign': (_) => {
          'request': requestJson(),
          'enquiry': {
            'id': 'e-1',
            'reference': 'BE-RPM9TAPX',
            'replayed': true,
          },
        },
        'POST $base/m-1/costs': (_) =>
            jsonResponse(201, {'cost': {}, 'request': requestJson()}),
        'POST $base/m-1/status': (_) => {'request': requestJson()},
      });
      final repo = MaintenanceRepository(api);
      final done = await repo.assign(
        'org-1',
        'm-1',
        'prov-1',
        message: ' Gate code 1234 ',
      );
      expect(jsonBody(requests[0]), {
        'directory_profile_id': 'prov-1',
        'message': 'Gate code 1234',
      });
      expect(done.enquiryReference, 'BE-RPM9TAPX');
      await repo.addCost(
        'org-1',
        'm-1',
        amount: '85.00',
        currency: 'USD',
        description: 'Washer',
        method: 'BANK',
        incurredOn: '2026-11-18',
      );
      expect(jsonBody(requests[1]), {
        'amount': '85.00',
        'currency': 'USD',
        'description': 'Washer',
        'method': 'BANK',
        'incurred_on': '2026-11-18',
      });
      await repo.setStatus('org-1', 'm-1', 'CANCELLED', note: 'Duplicate');
      expect(jsonBody(requests[2]), {
        'status': 'CANCELLED',
        'note': 'Duplicate',
      });
    });

    test('a wrong move is explained in words', () async {
      final (:api, requests: _) = routedApi({
        'POST $base/m-1/status': (_) =>
            apiError(409, 'MAINTENANCE_INVALID_TRANSITION'),
      });
      await expectLater(
        MaintenanceRepository(api).setStatus('org-1', 'm-1', 'CLOSED'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('cannot move to that status'),
          ),
        ),
      );
    });

    test('the tenant raises on their own tenancy only', () async {
      final (:api, :requests) = routedApi({
        'POST /v1/me/tenancies/t-1/maintenance': (_) => jsonResponse(201, {
          'request': requestJson(status: 'NEW', tenant: true),
        }),
        'GET /v1/me/tenancies/t-2/maintenance': (_) =>
            apiError(404, 'TENANCY_NOT_FOUND'),
        'POST /v1/me/tenancies/t-3/maintenance': (_) =>
            apiError(409, 'TENANCY_INVALID_STATE'),
      });
      final repo = MaintenanceRepository(api);
      final made = await repo.report(
        't-1',
        category: 'plumbing',
        priority: 'high',
        title: ' Kitchen tap leaking ',
      );
      expect(jsonBody(requests.first), {
        'category': 'plumbing',
        'priority': 'high',
        'title': 'Kitchen tap leaking',
        'description': '',
      });
      expect(made.raisedByYou, isTrue);
      expect(made.costs, isEmpty);
      expect(made.canAssign, isFalse);
      await expectLater(
        repo.mine('t-2'),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
      await expectLater(
        repo.report('t-3', category: 'plumbing', priority: 'low', title: 'x'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('only while the tenancy is active'),
          ),
        ),
      );
    });

    test('another organisation\'s book is not found', () async {
      final (:api, requests: _) = routedApi({
        'GET $base': (_) => apiError(404, 'BOOK_NOT_FOUND'),
      });
      await expectLater(
        MaintenanceRepository(api).list('org-1'),
        throwsA(
          isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
        ),
      );
    });
  });

  group('the maintenance screens', () {
    void routes(TestServices test, {bool write = true}) => serve(test, {
      'GET $base': (_) => pageJson([
        requestJson(write: write),
        requestJson(id: 'm-3', status: 'NEW', title: 'Oven door hinge broken'),
      ]),
      'GET $base/options': (_) => optionsJson(write: write),
      'GET $base/m-1': (_) => {'request': requestJson(write: write)},
      'GET $base/providers': (_) => {
        'items': [
          {
            'id': 'prov-2',
            'kind': 'service-providers',
            'slug': 'rapid-plumbing',
            'name': 'Rapid Plumbing',
            'trade': {'code': 'plumbing', 'label': 'Plumbing'},
            'city': 'Harare',
            'verified': true,
          },
        ],
      },
      'POST $base/m-1/assign': (_) => {
        'request': requestJson(),
        'enquiry': {'id': 'e-2', 'reference': 'BE-NEW12345', 'replayed': false},
      },
      'POST $base/m-1/status': (_) => {'request': requestJson()},
      'POST $base/m-1/costs': (_) =>
          jsonResponse(201, {'cost': {}, 'request': requestJson()}),
      'GET /v1/agent/organisations/org-1/properties': (_) => {
        'items': [propertyJson()],
        'total': 1,
        'page': 1,
        'page_size': 50,
      },
      'POST $base': (_) =>
          jsonResponse(201, {'request': requestJson(status: 'NEW')}),
    });

    testWidgets('list by status, with counts', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(tester, test, const MaintenanceScreen(books: [book]));
      await settle(tester);
      expect(find.text('Kitchen tap leaking'), findsOneWidget);
      expect(find.text('New (1)'), findsOneWidget);
      expect(find.text('With Sample Plumbers'), findsWidgets);
      expect(find.byKey(const Key('new-maintenance')), findsOneWidget);
      await tester.tap(find.byKey(const Key('maintenance-status-NEW')));
      await settle(tester);
      final list = test.workRequests.lastWhere((r) => r.url.path == base);
      expect(list.url.queryParameters['status'], 'NEW');
    });

    testWidgets('staff see the requests and nothing to change', (tester) async {
      final test = TestServices();
      routes(test, write: false);
      await pumpInApp(tester, test, const MaintenanceScreen(books: [book]));
      await settle(tester);
      expect(find.byKey(const Key('new-maintenance')), findsNothing);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
      );
      await settle(tester);
      expect(find.byKey(const Key('maintenance-assign')), findsNothing);
      expect(find.byKey(const Key('maintenance-add-cost')), findsNothing);
      expect(find.byKey(const Key('maintenance-comment')), findsNothing);
      expect(
        find.byKey(const Key('maintenance-move-IN_PROGRESS')),
        findsNothing,
      );
    });

    testWidgets('detail: timeline, costs with the ledger\'s wording', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
      );
      await settle(tester);
      expect(
        find.text('Assigned to Sample Plumbers (enquiry BE-RPM9TAPX)'),
        findsOneWidget,
      );
      expect(find.text('Recorded by you, not verified'), findsOneWidget);
      expect(find.text('Total USD 85.00'), findsOneWidget);
      expect(
        find.text(
          'Chipo Dube: Assigned it to Sample Plumbers (enquiry BE-RPM9TAPX)',
        ),
        findsOneWidget,
      );
      expect(find.text('Mark in progress'), findsOneWidget);
    });

    testWidgets('assigns a provider from the directory', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('maintenance-assign')));
      await settle(tester);
      expect(
        find.textContaining('never the tenant\'s details'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pick-provider-prov-2')));
      await settle(tester);
      await tester.tap(find.text('Send the enquiry'));
      await settle(tester);
      final assign = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(assign.url.path, '$base/m-1/assign');
      expect(bodyOf(assign), {'directory_profile_id': 'prov-2'});
      expect(
        find.textContaining('Enquiry BE-NEW12345 was sent'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling asks for the reason', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('maintenance-move-CANCELLED')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Fixed by tenant');
      await tester.tap(find.text('Cancel the request').last);
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {'status': 'CANCELLED', 'note': 'Fixed by tenant'});
    });

    testWidgets('records a cost checked against the currency', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('maintenance-add-cost')));
      await tester.tap(find.byKey(const Key('maintenance-add-cost')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('cost-amount')), '85.001');
      await tester.enterText(
        find.byKey(const Key('cost-description')),
        'Replace washer',
      );
      await tester.tap(find.byKey(const Key('cost-save')));
      await settle(tester);
      expect(find.text('At most 2 decimals for USD.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cost-amount')), '85.00');
      await tester.tap(find.byKey(const Key('cost-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '$base/m-1/costs');
      expect(bodyOf(post)['amount'], '85.00');
      expect(
        find.textContaining('Cost recorded in your books'),
        findsOneWidget,
      );
    });

    testWidgets('raises a request on a property', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        NewMaintenanceScreen(
          book: book,
          options: MaintenanceOptions.fromJson(optionsJson()),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('maintenance-save')));
      await settle(tester);
      expect(find.text('Choose the property.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('maintenance-property')));
      await settle(tester);
      await tester.tap(find.text('Avondale Court').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('maintenance-category')));
      await settle(tester);
      await tester.tap(find.text('Plumbing').last);
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('maintenance-title')),
        'Kitchen tap leaking',
      );
      await tester.tap(find.byKey(const Key('maintenance-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {
        'property_id': 'p-1',
        'unit_id': null,
        'category': 'plumbing',
        'priority': 'normal',
        'title': 'Kitchen tap leaking',
        'description': '',
      });
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MaintenanceScreen(books: [book]),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const MaintenanceRequestScreen(book: book, id: 'm-1'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tenant\'s repairs', () {
    final tenancy = Tenancy.fromJson(tenancyJson(mine: true));
    void routes(TestServices test) => serve(test, {
      'GET /v1/me/tenancies/t-1/maintenance': (_) => {
        'items': [requestJson(tenant: true)],
      },
      'GET /v1/me/tenancies/t-1/maintenance/m-1': (_) => {
        'request': requestJson(tenant: true),
      },
      'GET /v1/me/tenancies/t-1/maintenance/options': (_) => optionsJson(),
      'POST /v1/me/tenancies/t-1/maintenance': (_) => jsonResponse(201, {
        'request': requestJson(tenant: true, status: 'NEW'),
      }),
      'POST /v1/me/tenancies/t-1/maintenance/m-1/comments': (_) =>
          jsonResponse(201, {'item': {}}),
    });

    testWidgets('lists their own and reports a problem', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(tester, test, MyMaintenanceScreen(tenancy: tenancy));
      await settle(tester);
      expect(find.text('Kitchen tap leaking'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-problem')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('maintenance-category')));
      await settle(tester);
      await tester.tap(find.text('Plumbing').last);
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('maintenance-title')),
        'Kitchen tap leaking',
      );
      await tester.tap(find.byKey(const Key('report-send')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/v1/me/tenancies/t-1/maintenance');
      expect(bodyOf(post)['priority'], 'normal');
      // It opens the request they sent.
      expect(find.text('You raised this'), findsOneWidget);
    });

    testWidgets('a request: no status, assign or cost controls', (
      tester,
    ) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const MyMaintenanceRequestScreen(tenancyId: 't-1', id: 'm-1'),
      );
      await settle(tester);
      expect(find.text('Being handled by Sample Plumbers'), findsOneWidget);
      expect(find.text('You: Raised the request'), findsOneWidget);
      expect(find.byKey(const Key('maintenance-assign')), findsNothing);
      expect(find.byKey(const Key('maintenance-add-cost')), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
      await tester.tap(find.byKey(const Key('my-comment')));
      await settle(tester);
      expect(find.byKey(const Key('comment-internal')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('comment-text')),
        'Still dripping',
      );
      await tester.tap(find.byKey(const Key('comment-send')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {'text': 'Still dripping'});
    });

    testWidgets('an ended tenancy cannot report new problems', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        MyMaintenanceScreen(
          tenancy: Tenancy.fromJson(tenancyJson(mine: true, status: 'ENDED')),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('report-problem')), findsNothing);
    });
  });

  group('maintenance notification links', () {
    test('open the request in the book that has it', () async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/dashboard': (_) => dashboard,
        'GET $base/m-1': (_) => {'request': requestJson()},
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      final target = await resolveNotificationLink(
        '/agent/maintenance/m-1',
        test.services,
      );
      expect((target as InApp).location, '/maintenance/org-1/m-1');
      final tenant = await resolveNotificationLink(
        '/account/tenancies/t-1',
        test.services,
      );
      expect((tenant as InApp).location, '/activity?tab=tenancy');
    });
  });
}
