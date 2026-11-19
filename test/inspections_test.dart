import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/properties/inspection_repository.dart';
import 'package:rightproperty365/features/properties/inspection_screens.dart';
import 'package:rightproperty365/features/properties/properties_repository.dart';

import 'api_routes.dart';
import 'properties_test.dart' show propertyJson, tenancyJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const base = '/v1/agent/organisations/org-1/inspections';
const book = ContactBook(id: 'org-1', name: 'Sample Estates', canWrite: true);

Map<String, dynamic> optionsJson({bool write = true}) => {
  'types': [
    {'code': 'MOVE_IN', 'label': 'Move-in'},
    {'code': 'ROUTINE', 'label': 'Routine'},
    {'code': 'MOVE_OUT', 'label': 'Move-out'},
  ],
  'statuses': [],
  'finding_statuses': [
    {'code': 'OK', 'label': 'OK'},
    {'code': 'ATTENTION', 'label': 'Needs attention'},
    {'code': 'DAMAGED', 'label': 'Damaged'},
    {'code': 'NA', 'label': 'Not applicable'},
  ],
  'templates': [
    {
      'code': 'residential',
      'label': 'Standard residential',
      'areas': [
        {
          'code': 'residential-kitchen',
          'label': 'Kitchen',
          'items': [
            {'code': 'residential-kitchen-sink', 'label': 'Sink and taps'},
            {'code': 'residential-kitchen-oven', 'label': 'Stove and oven'},
          ],
        },
      ],
    },
  ],
  'inspectors': [
    {'user_id': 'u-1', 'name': 'Chipo Dube'},
  ],
  'transitions': {},
  'photo_rules': {},
  'limits': {},
  'permissions': {'write': write},
};

Map<String, dynamic> item(
  String id,
  String label, {
  String? status,
  String note = '',
  Map<String, dynamic>? baseline,
  bool tenant = false,
}) => {
  'id': id,
  'label': label,
  'position': 1,
  'status': status,
  'status_label': switch (status) {
    'OK' => 'OK',
    'ATTENTION' => 'Needs attention',
    'DAMAGED' => 'Damaged',
    'NA' => 'Not applicable',
    _ => null,
  },
  'note': note,
  'photos': [
    if (status == 'DAMAGED')
      {
        'id': 'ph-1',
        if (!tenant) 'item_id': id,
        'url': tenant
            ? '/v1/me/tenancies/t-1/inspections/i-1/photos/ph-1'
            : '$base/i-1/photos/ph-1',
        'content_type': 'image/jpeg',
        'width': 1600,
        'height': 1200,
      },
  ],
  'baseline': baseline,
};

Map<String, dynamic> inspectionJson({
  String id = 'i-1',
  String status = 'IN_PROGRESS',
  String type = 'ROUTINE',
  bool write = true,
  bool tenant = false,
  bool allDone = false,
}) {
  final open = status == 'SCHEDULED' || status == 'IN_PROGRESS';
  final w = write && open;
  return {
    'id': id,
    'reference': 'RPI-2026-900002',
    'type': type,
    'type_label': switch (type) {
      'MOVE_IN' => 'Move-in',
      'MOVE_OUT' => 'Move-out',
      _ => 'Routine',
    },
    'status': status,
    'status_label': switch (status) {
      'SCHEDULED' => 'Scheduled',
      'COMPLETED' => 'Completed',
      'CANCELLED' => 'Cancelled',
      _ => 'In progress',
    },
    'property': tenant
        ? {'name': 'Avondale Court'}
        : {'id': 'p-1', 'name': 'Avondale Court', 'archived': false},
    'unit': tenant
        ? {'label': 'Flat 1'}
        : {'id': 'u-1', 'label': 'Flat 1', 'archived': false},
    if (!tenant) 'tenancy_id': 't-1',
    if (!tenant)
      'tenancy': {
        'id': 't-1',
        'tenants': [
          {'id': 'c-1', 'name': 'Kudzai Sithole', 'live': true},
        ],
      },
    'scheduled_for': '2026-11-26T09:00:00Z',
    'completed_at': status == 'COMPLETED' ? '2026-11-26T11:00:00Z' : null,
    'inspector': {'user_id': 'u-1', 'name': 'Chipo Dube'},
    'template': {'code': 'residential', 'label': 'Standard residential'},
    'progress': {
      'items': 2,
      'done': allDone || status == 'COMPLETED' ? 2 : 1,
      'ok': 1,
      'attention': 0,
      'damaged': allDone || status == 'COMPLETED' ? 1 : 0,
      'na': 0,
    },
    'areas': [
      {
        'id': 'a-1',
        'label': 'Kitchen',
        'position': 1,
        'items': [
          item(
            'it-1',
            'Sink and taps',
            status: 'OK',
            tenant: tenant,
            baseline: type == 'MOVE_OUT'
                ? {
                    'status': 'ATTENTION',
                    'status_label': 'Needs attention',
                    'note': 'Cold tap drips slightly',
                  }
                : null,
          ),
          item(
            'it-2',
            'Stove and oven',
            status: allDone || status == 'COMPLETED' ? 'DAMAGED' : null,
            note: allDone || status == 'COMPLETED' ? 'Door hinge broken' : '',
            tenant: tenant,
          ),
        ],
      },
    ],
    'summary': status == 'COMPLETED' ? 'Generally good.' : '',
    'sign_off': {
      'tenant_name': status == 'COMPLETED' ? 'Kudzai Sithole' : null,
      'agent_name': status == 'COMPLETED' ? 'Chipo Dube' : null,
    },
    'baseline': type == 'MOVE_OUT'
        ? {
            'id': 'i-0',
            'reference': 'RPI-2026-900001',
            'completed_at': '2026-10-01T09:00:00Z',
          }
        : null,
    'report_url': tenant
        ? '/v1/me/tenancies/t-1/inspections/$id/report.pdf'
        : '$base/$id/report.pdf',
    if (!tenant)
      'can': {
        'edit': w,
        'edit_checklist': w,
        'record_findings': w,
        'add_photo': w,
        'start': write && status == 'SCHEDULED',
        'complete': write && status == 'IN_PROGRESS',
        'cancel': w,
      },
  };
}

Map<String, dynamic> pageJson(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'page_size': 50,
  'status_counts': {
    'SCHEDULED': 1,
    'IN_PROGRESS': 0,
    'COMPLETED': 1,
    'CANCELLED': 0,
  },
};

void main() {
  group('the inspections API', () {
    test('reads a move-out compared with the move-in', () async {
      final (:api, requests: _) = routedApi({
        'GET $base/i-1': (_) => {
          'inspection': inspectionJson(type: 'MOVE_OUT'),
        },
      });
      final i = await InspectionRepository(api).get('org-1', 'i-1');
      expect(i.baselineReference, 'RPI-2026-900001');
      final sink = i.areas.single.items.first;
      expect(sink.baselineLabel, 'Needs attention');
      expect(sink.baselineNote, 'Cold tap drips slightly');
      expect(i.tenants, ['Kudzai Sithole']);
      expect(i.frozen, isFalse);
    });

    test('saves findings partially, only what changed', () async {
      final (:api, :requests) = routedApi({
        'PUT $base/i-1/findings': (_) => {'inspection': inspectionJson()},
      });
      await InspectionRepository(api).saveFindings('org-1', 'i-1', const [
        FindingChange('it-2', status: 'DAMAGED'),
        FindingChange('it-1', note: 'Fine'),
      ]);
      expect(jsonBody(requests.single), {
        'items': [
          {'item_id': 'it-2', 'status': 'DAMAGED'},
          {'item_id': 'it-1', 'note': 'Fine'},
        ],
      });
    });

    test('creates from a template, in UTC', () async {
      final (:api, :requests) = routedApi({
        'POST $base': (_) => jsonResponse(201, {
          'inspection': inspectionJson(status: 'SCHEDULED'),
        }),
      });
      await InspectionRepository(api).create(
        'org-1',
        propertyId: 'p-1',
        unitId: 'u-1',
        tenancyId: 't-1',
        type: 'MOVE_IN',
        scheduledFor: DateTime.utc(2026, 12, 1, 9),
        template: 'residential',
      );
      expect(jsonBody(requests.single), {
        'property_id': 'p-1',
        'unit_id': 'u-1',
        'tenancy_id': 't-1',
        'type': 'MOVE_IN',
        'scheduled_for': '2026-12-01T09:00:00.000Z',
        'checklist_template': 'residential',
      });
    });

    test('completing with items missing says how many', () async {
      final (:api, requests: _) = routedApi({
        'POST $base/i-1/complete': (_) => jsonResponse(409, {
          'error': {
            'code': 'INSPECTION_INCOMPLETE',
            'message': 'x',
            'details': {
              'missing': 1,
              'item_ids': ['it-2'],
            },
          },
        }),
        'PUT $base/i-9/findings': (_) => apiError(409, 'INSPECTION_CLOSED'),
        'POST $base/i-1/items/it-1/photos': (_) =>
            apiError(415, 'UNSUPPORTED_FILE_TYPE'),
      });
      final repo = InspectionRepository(api);
      await expectLater(
        repo.complete('org-1', 'i-1'),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.message, 'message', contains('1 item still'))
              .having((f) => f.details['item_ids'], 'ids', ['it-2']),
        ),
      );
      await expectLater(
        repo.saveFindings('org-1', 'i-9', const [FindingChange('it-1')]),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('can no longer change'),
          ),
        ),
      );
      await expectLater(
        repo.addPhoto('org-1', 'i-1', 'it-1', (bytes: [1, 2], name: 'x.gif')),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            contains('Only photos'),
          ),
        ),
      );
    });

    test('the tenant reads completed ones of their tenancy only', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/me/tenancies/t-1/inspections': (_) => {
          'items': [inspectionJson(status: 'COMPLETED', tenant: true)],
        },
        'GET /v1/me/tenancies/t-1/inspections/i-2': (_) =>
            apiError(404, 'INSPECTION_NOT_FOUND'),
      });
      final repo = InspectionRepository(api);
      final mine = (await repo.mine('t-1')).single;
      expect(mine.status, 'COMPLETED');
      expect(mine.canRecord, isFalse);
      expect(mine.reportUrl, startsWith('/v1/me/tenancies/t-1/'));
      await expectLater(
        repo.myInspection('t-1', 'i-2'),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
    });

    test('another organisation\'s book is not found', () async {
      final (:api, requests: _) = routedApi({
        'GET $base': (_) => apiError(404, 'BOOK_NOT_FOUND'),
      });
      await expectLater(
        InspectionRepository(api).list('org-1'),
        throwsA(
          isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
        ),
      );
    });
  });

  group('the inspection screens', () {
    void routes(
      TestServices test, {
      String status = 'IN_PROGRESS',
      bool write = true,
      bool completeFails = false,
    }) {
      var current = inspectionJson(status: status, write: write);
      serve(test, {
        'GET $base': (_) => pageJson([
          inspectionJson(status: 'SCHEDULED'),
          inspectionJson(id: 'i-0', status: 'COMPLETED', type: 'MOVE_IN'),
        ]),
        'GET $base/options': (_) => optionsJson(write: write),
        'GET $base/i-1': (_) => {'inspection': current},
        'PUT $base/i-1/findings': (_) {
          current = inspectionJson(allDone: true);
          return {'inspection': current};
        },
        'POST $base/i-1/complete': (_) {
          if (completeFails) {
            return jsonResponse(409, {
              'error': {
                'code': 'INSPECTION_INCOMPLETE',
                'message': 'x',
                'details': {
                  'missing': 1,
                  'item_ids': ['it-2'],
                },
              },
            });
          }
          current = inspectionJson(status: 'COMPLETED');
          return {'inspection': current};
        },
        'GET /v1/agent/organisations/org-1/properties': (_) => {
          'items': [propertyJson()],
          'total': 1,
          'page': 1,
          'page_size': 50,
        },
        'GET /v1/agent/organisations/org-1/tenancies': (_) => {
          'items': [tenancyJson(status: 'DRAFT')],
          'total': 1,
          'page': 1,
          'page_size': 50,
          'status_counts': {},
        },
        'POST $base': (_) => jsonResponse(201, {
          'inspection': inspectionJson(status: 'SCHEDULED'),
        }),
      });
    }

    testWidgets('list by status, with progress', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(tester, test, const InspectionsScreen(books: [book]));
      await settle(tester);
      expect(find.text('Scheduled (1)'), findsOneWidget);
      expect(find.text('1 of 2 items recorded'), findsOneWidget);
      expect(find.byKey(const Key('new-inspection')), findsOneWidget);
    });

    testWidgets('a finding saves as soon as it is chosen', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('finding-it-2-DAMAGED')));
      await settle(tester);
      final put = test.workRequests.lastWhere((r) => r.method == 'PUT');
      expect(bodyOf(put), {
        'items': [
          {'item_id': 'it-2', 'status': 'DAMAGED'},
        ],
      });
      expect(find.text('Saved'), findsOneWidget);
      expect(find.textContaining('2 of 2 items recorded'), findsOneWidget);
    });

    testWidgets('a note saves after typing stops', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('finding-note-it-1')),
        'Washer replaced',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(test.workRequests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final put = test.workRequests.lastWhere((r) => r.method == 'PUT');
      expect(bodyOf(put), {
        'items': [
          {'item_id': 'it-1', 'note': 'Washer replaced'},
        ],
      });
    });

    testWidgets('completing with an item missing marks it', (tester) async {
      final test = TestServices();
      routes(test, completeFails: true);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('inspection-complete')));
      await settle(tester);
      expect(find.byKey(const Key('complete-tenant')), findsOneWidget);
      await tester.tap(find.byKey(const Key('complete-send')));
      await settle(tester);
      expect(
        find.text('1 item still needs a status before it can be completed.'),
        findsOneWidget,
      );
      expect(find.text('Needs a status'), findsOneWidget);
    });

    testWidgets('once completed the screen is read only', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('inspection-complete')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('complete-agent')),
        'Chipo Dube',
      );
      await tester.tap(find.byKey(const Key('complete-send')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {
        'tenant_sign_off_name': 'Kudzai Sithole',
        'agent_sign_off_name': 'Chipo Dube',
      });
      expect(find.byKey(const Key('inspection-frozen')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('inspection-complete')), findsNothing);
      expect(find.byKey(const Key('inspection-cancel')), findsNothing);
      expect(find.text('Report'), findsOneWidget);
    });

    testWidgets('staff only read', (tester) async {
      final test = TestServices();
      routes(test, write: false);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
      );
      await settle(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('inspection-complete')), findsNothing);
      expect(find.text('Draft report'), findsOneWidget);
    });

    testWidgets('schedules one on a draft tenancy', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        NewInspectionScreen(
          book: book,
          options: InspectionOptions.fromJson(optionsJson()),
        ),
      );
      await settle(tester);
      expect(
        find.text('Standard residential (1 areas, 2 items)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('inspection-property')));
      await settle(tester);
      await tester.tap(find.text('Avondale Court').last);
      await settle(tester);
      await tester.tap(find.textContaining('Tenancy (optional)'));
      await settle(tester);
      await tester.tap(find.textContaining('(draft)').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('inspection-type')));
      await settle(tester);
      await tester.tap(find.text('Move-in').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('inspection-save')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      final body = bodyOf(post);
      expect(body['tenancy_id'], 't-1');
      expect(body['type'], 'MOVE_IN');
      expect(body['checklist_template'], 'residential');
      expect(body.containsKey('inspector_user_id'), isFalse);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      routes(test);
      await pumpInApp(
        tester,
        test,
        const InspectionsScreen(books: [book]),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await pumpInApp(
        tester,
        test,
        const InspectionScreen(book: book, id: 'i-1'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tenant\'s reports', () {
    testWidgets('completed reports, read only, with the PDF', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/tenancies/t-1/inspections': (_) => {
          'items': [inspectionJson(status: 'COMPLETED', tenant: true)],
        },
        'GET /v1/me/tenancies/t-1/inspections/i-1': (_) => {
          'inspection': inspectionJson(status: 'COMPLETED', tenant: true),
        },
      });
      await pumpInApp(
        tester,
        test,
        MyInspectionsScreen(tenancy: Tenancy.fromJson(tenancyJson(mine: true))),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('inspection-i-1')));
      await settle(tester);
      expect(find.text('Door hinge broken'), findsOneWidget);
      expect(find.byKey(const Key('my-inspection-report')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Signed off (typed names): Kudzai Sithole, Chipo Dube'),
        findsOneWidget,
      );
    });
  });
}
