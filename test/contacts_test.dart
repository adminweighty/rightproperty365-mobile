import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/contacts/contacts_screens.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

const base = '/v1/agent/organisations/org-1/contacts';
const book = ContactBook(
  id: 'org-1',
  name: 'Sample Estates',
  canWrite: true,
  canExport: true,
);

Map<String, dynamic> contactJson({
  String id = 'c-1',
  String name = 'Tariro Moyo',
  String stage = 'NEW',
  int due = 0,
}) => {
  'id': id,
  'name': name,
  'emails': ['tariro@example.com'],
  'phones': ['+263771234567'],
  'type': 'tenant',
  'type_label': 'Tenant',
  'stage': stage,
  'stage_label': contactStages[stage],
  'tags': ['avondale'],
  'owner_user_id': 'u-1',
  'owner_name': 'Tendai Ncube',
  'source': 'enquiry',
  'source_label': 'Enquiry',
  'marketing_permission': {
    'granted': true,
    'granted_at': '2030-03-01T08:00:00Z',
    'source': 'Asked on the phone',
    'recorded_by': 'u-1',
    'recorded_by_name': 'Tendai Ncube',
  },
  'last_contact_at': '2030-03-01T08:00:00Z',
  'created_at': '2030-02-01T08:00:00Z',
  'updated_at': '2030-03-01T08:00:00Z',
  'merged_into': null,
  'linked_listings': [
    {
      'id': 'l-10',
      'title': 'Garden cottage',
      'reference': 'RP-ZW-10010',
      'slug': null,
    },
  ],
  'reminders_due': due,
  'open_reminders': due,
  'next_reminder_at': null,
  'created_by': 'u-1',
};

Map<String, dynamic> body({String stage = 'NEW', List reminders = const []}) =>
    {
      'contact': contactJson(stage: stage, due: reminders.length),
      'linked_items': [
        {
          'kind': 'APPOINTMENT',
          'id': 'ap-6',
          'reference': 'AP-7K3M9QXD',
          'type': 'VIEWING',
          'status': 'REQUESTED',
          'title': 'Garden cottage',
          'listing_id': 'l-10',
          'created_at': '2030-03-01T08:00:00Z',
          'auto': true,
          'linked_at': '2030-03-01T08:00:00Z',
        },
      ],
      'reminders': reminders,
    };

Map<String, dynamic> reminderJson({bool done = false}) => {
  'id': 'r-1',
  'contact_id': 'c-1',
  'due_at': '2030-03-02T07:00:00Z',
  'text': 'Call back about the lease',
  'done': done,
  'done_at': null,
  'created_by': {'user_id': 'u-1', 'name': 'Tendai Ncube'},
  'created_at': '2030-03-01T08:00:00Z',
  'overdue': true,
};

final timeline = {
  'items': [
    {
      'id': 'e-2',
      'kind': 'STAGE_CHANGED',
      'at': '2030-03-01T09:00:00Z',
      'actor': {'user_id': 'u-1', 'name': 'Tendai Ncube'},
      'actor_name': 'Tendai Ncube',
      'label': 'Stage changed from New to Contacted',
      'text': 'Called her',
      'data': {},
    },
    {
      'id': 'e-1',
      'kind': 'SOMETHING_NEW',
      'at': '2030-03-01T08:00:00Z',
      'actor': null,
      'label': 'Linked to appointment AP-7K3M9QXD',
      'ref': {'kind': 'APPOINTMENT', 'id': 'ap-6', 'reference': 'AP-7K3M9QXD'},
      'data': {},
    },
  ],
};

void main() {
  group('contact books', () {
    test('one per organisation, and an approved direct owner\'s own', () {
      const work = Workspace(
        organisations: [
          WorkOrganisation(
            id: 'org-1',
            name: 'Sample Estates',
            kind: 'AGENCY',
            marketCode: 'ZW',
            role: 'STAFF',
            roleLabel: 'Agency Staff',
          ),
        ],
      );
      final books = contactBooks(work, testUser);
      expect(books.single.canWrite, isFalse);
      expect(books.single.canExport, isFalse);

      const landlord = User(
        id: 'u-9',
        name: 'Lara Landlord',
        email: 'landlord@example.test',
        emailVerified: true,
        accountRoles: [AccountRole('LANDLORD', 'ACTIVE')],
      );
      final own = contactBooks(const Workspace(), landlord).single;
      expect(own.id, 'u-9');
      expect(own.personal, isTrue);
      expect(own.canExport, isFalse);
      expect(contactBooks(const Workspace(), testUser), isEmpty);
    });
  });

  group('the CRM API', () {
    test('lists, creates, notes, reminds, moves and links', () async {
      final (:api, :requests) = routedApi({
        'GET $base': (_) => {
          'items': [contactJson()],
          'page': 1,
          'page_size': 25,
          'total': 1,
          'total_pages': 1,
          'stage_counts': {'NEW': 1, 'CONTACTED': 0},
        },
        'POST $base': (request) =>
            request.url.queryParameters['allow_duplicate'] == 'true'
                  ? jsonResponse(201, body())
                  : apiError(409, 'CONTACT_DUPLICATE')
              ..toString(),
        'POST $base/c-1/notes': (_) => jsonResponse(201, {'id': 'n-1'}),
        'POST $base/c-1/reminders': (_) => jsonResponse(201, reminderJson()),
        'PATCH $base/c-1/reminders/r-1': (_) => reminderJson(done: true),
        'POST $base/c-1/stage': (_) => body(stage: 'CONTACTED'),
        'POST $base/from-request/req-1': (_) => jsonResponse(201, body()),
        'POST $base/from-request/req-2': (_) => body(),
        'GET $base/c-1/timeline': (_) => timeline,
      });
      final repo = ContactsRepository(api);

      final page = await repo.list('org-1', query: ' tariro ', stage: 'NEW');
      expect(requests.last.url.queryParameters, {
        'q': 'tariro',
        'stage': 'NEW',
        'page': '1',
        'page_size': '25',
      });
      expect(page.items.single.marketingGranted, isTrue);
      expect(page.stageCounts['NEW'], 1);

      const draft = ContactDraft(
        name: ' Tariro Moyo ',
        type: 'tenant',
        emails: ['tariro@example.com', ' '],
        phones: ['077 123 4567'],
        note: ' Met at the show ',
        marketingGranted: false,
        marketingSource: 'Asked',
      );
      expect(draft.toJson(), {
        'name': 'Tariro Moyo',
        'type': 'tenant',
        'emails': ['tariro@example.com'],
        'phones': ['0771234567'],
        'stage': 'NEW',
        'notes': 'Met at the show',
        'marketing_permission': {'granted': false, 'source': 'Asked'},
      });
      final created = await repo.create('org-1', draft, allowDuplicate: true);
      expect(created.linkedItems.single.auto, isTrue);

      await repo.addNote('org-1', 'c-1', ' Called ');
      expect(jsonBody(requests.last), {'text': 'Called'});
      final reminder = await repo.addReminder(
        'org-1',
        'c-1',
        DateTime.utc(2030, 3, 2, 7),
        'Call back',
      );
      expect(jsonBody(requests.last)['due_at'], '2030-03-02T07:00:00.000Z');
      expect(reminder.overdue, isTrue);
      expect(
        (await repo.setReminderDone('org-1', 'c-1', 'r-1', true)).done,
        isTrue,
      );
      final moved = await repo.moveStage(
        'org-1',
        'c-1',
        'CONTACTED',
        note: 'Called her',
      );
      expect(jsonBody(requests.last), {
        'stage': 'CONTACTED',
        'note': 'Called her',
      });
      expect(moved.contact.stageLabel, 'Contacted');

      final fresh = await repo.fromRequest(
        'org-1',
        'req-1',
        kind: 'PROPERTY_REQUEST',
      );
      expect(fresh.created, isTrue);
      expect(requests.last.url.queryParameters['kind'], 'PROPERTY_REQUEST');
      expect(
        (await repo.fromRequest('org-1', 'req-2', kind: 'APPOINTMENT')).created,
        isFalse,
      );

      final events = await repo.timeline('org-1', 'c-1');
      expect(events.first.actorName, 'Tendai Ncube');
      // An unknown kind still shows the API's own sentence.
      expect(events.last.label, 'Linked to appointment AP-7K3M9QXD');
      expect(events.last.reference, 'AP-7K3M9QXD');
    });

    test('a duplicate names the contacts that already have it', () async {
      final (:api, requests: _) = mockApi(
        (_) async => jsonResponse(409, {
          'error': {
            'code': 'CONTACT_DUPLICATE',
            'message': 'Already in the book',
            'details': {
              'duplicates': [
                {'id': 'c-1', 'name': 'Tariro Moyo'},
              ],
            },
          },
        }),
      );
      await expectLater(
        ContactsRepository(
          api,
        ).create('org-1', const ContactDraft(name: 'Tariro', type: 'tenant')),
        throwsA(
          isA<DuplicateContacts>().having(
            (d) => d.duplicates.single.name,
            'name',
            'Tariro Moyo',
          ),
        ),
      );
    });

    test('another organisation\'s book is not found', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/agent/organisations/org-9/contacts': (_) =>
            apiError(404, 'CONTACT_NOT_FOUND'),
      });
      await expectLater(
        ContactsRepository(api).list('org-9'),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
    });
  });

  group('the contact screens', () {
    testWidgets('list with stage counts, search and a due reminder', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET $base': (request) => {
          'items': [
            if (request.url.queryParameters['q'] != 'nobody')
              contactJson(due: 1),
          ],
          'page': 1,
          'page_size': 25,
          'total': request.url.queryParameters['q'] == 'nobody' ? 0 : 1,
          'total_pages': 1,
          'stage_counts': {'NEW': 1, 'CONTACTED': 3},
        },
      });
      await pumpInApp(tester, test, const ContactsScreen(books: [book]));
      await settle(tester);
      expect(find.text('Tariro Moyo'), findsOneWidget);
      expect(find.text('Contacted (3)'), findsOneWidget);
      expect(find.text('1 reminder due'), findsOneWidget);
      expect(find.byKey(const Key('new-contact')), findsOneWidget);
      expect(find.textContaining('Import, export and merge'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('contacts-search')),
        'nobody',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text('No contacts match.'), findsOneWidget);
    });

    testWidgets('staff read the book but cannot change it', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $base/c-1': (_) => body(reminders: [reminderJson()]),
        'GET $base/c-1/timeline': (_) => timeline,
      });
      await pumpInApp(
        tester,
        test,
        const ContactScreen(
          book: ContactBook(id: 'org-1', name: 'S', canWrite: false),
          id: 'c-1',
        ),
      );
      await settle(tester);
      expect(find.text('Tariro Moyo'), findsOneWidget);
      expect(find.byKey(const Key('contact-stage')), findsNothing);
      expect(find.byKey(const Key('contact-note')), findsNothing);
      expect(find.byKey(const Key('add-reminder')), findsNothing);
    });

    testWidgets('a contact: note, stage, reminder done, history', (
      tester,
    ) async {
      final test = TestServices();
      var stage = 'NEW';
      var reminders = [reminderJson()];
      serve(test, {
        'GET $base/c-1': (_) => body(stage: stage, reminders: reminders),
        'GET $base/c-1/timeline': (_) => timeline,
        'POST $base/c-1/notes': (_) => jsonResponse(201, {'id': 'n-1'}),
        'POST $base/c-1/stage': (request) {
          stage = bodyOf(request)['stage'] as String;
          return body(stage: stage);
        },
        'PATCH $base/c-1/reminders/r-1': (_) {
          reminders = [];
          return reminderJson(done: true);
        },
      });
      await pumpInApp(tester, test, const ContactScreen(book: book, id: 'c-1'));
      await settle(tester);
      expect(find.text('tariro@example.com'), findsOneWidget);
      expect(
        find.textContaining('Marketing permission: given'),
        findsOneWidget,
      );
      expect(find.textContaining('matched by email or phone'), findsOneWidget);
      expect(find.text('Stage changed from New to Contacted'), findsOneWidget);
      expect(find.text('Linked to appointment AP-7K3M9QXD'), findsOneWidget);
      expect(find.textContaining('Overdue'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('contact-note')), 'Called');
      await tester.pump();
      await tester.tap(find.byKey(const Key('contact-add-note')));
      await settle(tester);
      expect(
        test.workRequests.any((r) => r.url.path.endsWith('/notes')),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('contact-stage')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('stage-option-NEGOTIATING')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stage-confirm')));
      await settle(tester);
      expect(find.text('Negotiating'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reminder-r-1')));
      await settle(tester);
      expect(find.text('No open reminders.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a new contact shows a duplicate and can be created anyway', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/reference/contact_types': (_) => {
          'items': [
            {'code': 'buyer', 'label': 'Buyer'},
            {'code': 'tenant', 'label': 'Tenant'},
          ],
        },
        'POST $base': (request) =>
            request.url.queryParameters['allow_duplicate'] == 'true'
            ? jsonResponse(201, body())
            : jsonResponse(409, {
                'error': {
                  'code': 'CONTACT_DUPLICATE',
                  'message': 'Duplicate',
                  'details': {
                    'duplicates': [
                      {'id': 'c-1', 'name': 'Tariro Moyo'},
                    ],
                  },
                },
              }),
      });
      await pumpInApp(tester, test, const NewContactScreen(book: book));
      await settle(tester);
      await tester.tap(find.byKey(const Key('contact-save')));
      await settle(tester);
      expect(find.text('Enter the contact\'s name.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('contact-name')), 'Tariro');
      await tester.enterText(
        find.byKey(const Key('contact-email')),
        'tariro@example.com',
      );
      await tester.tap(find.byKey(const Key('contact-save')));
      await settle(tester);
      expect(find.text('Open Tariro Moyo'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('create-anyway')));
      await tester.tap(find.byKey(const Key('create-anyway')));
      await settle(tester);
      final sent = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(sent.url.queryParameters['allow_duplicate'], 'true');
      expect(bodyOf(sent)['emails'], ['tariro@example.com']);
    });

    testWidgets('holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $base/c-1': (_) => body(reminders: [reminderJson()]),
        'GET $base/c-1/timeline': (_) => timeline,
      });
      await pumpInApp(
        tester,
        test,
        const ContactScreen(book: book, id: 'c-1'),
        textScale: 2,
        size: const Size(390, 2600),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
