import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/applications/application_models.dart';
import 'package:rightproperty365/features/applications/applications_repository.dart';
import 'package:rightproperty365/features/applications/apply_screen.dart';
import 'package:rightproperty365/features/applications/received_applications.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';

import 'api_routes.dart';
import 'support.dart';
import 'work_test.dart' show bodyOf, serve, settle;

final formJson = {
  'id': 'form-2',
  'family_id': 'fam-1',
  'version': 2,
  'name': 'Rental application',
  'market_code': 'ZW',
  'purpose': 'To choose a tenant.',
  'privacy_notice': 'Only Sample Estates sees your answers.',
  'retention_days': 365,
  'expires_at': null,
  'sections': [
    {
      'key': 'household',
      'title': 'Your household',
      'description': null,
      'fields': [
        {
          'key': 'people',
          'type': 'number',
          'label': 'How many people will live there?',
          'required': true,
          'min': 1,
          'max': 12,
        },
        {
          'key': 'pets',
          'type': 'single_choice',
          'label': 'Do you have pets?',
          'required': true,
          'options': [
            {'value': 'yes', 'label': 'Yes'},
            {'value': 'no', 'label': 'No'},
          ],
        },
        {
          'key': 'pets_details',
          'type': 'long_text',
          'label': 'Describe them',
          'required': true,
          'visible_if': {'field': 'pets', 'equals': 'yes'},
        },
      ],
    },
    {
      'key': 'documents',
      'title': 'Documents',
      'description': 'A recent payslip or bank statement.',
      'fields': [
        {
          'key': 'income',
          'type': 'file',
          'label': 'Proof of income',
          'required': true,
          'accept': ['pdf', 'jpg', 'png'],
          'max_files': 2,
        },
      ],
    },
  ],
};

Map<String, dynamic> appJson({
  String status = 'DRAFT',
  Map<String, dynamic> answers = const {},
  List files = const [],
  String? reference,
  String? infoRequest,
}) => {
  'id': 'app-1',
  'reference': reference,
  'status': status,
  'status_label': switch (status) {
    'SUBMITTED' => 'Submitted',
    'MORE_INFO' => 'More information requested',
    'WITHDRAWN' => 'Withdrawn',
    _ => 'Draft',
  },
  'listing_id': 'listing-1',
  'listing': {
    'slug': 'garden-cottage',
    'reference': 'RP-ZW-10009',
    'title': 'Garden cottage',
  },
  'listing_available': true,
  'form': formJson,
  'answers': answers,
  'files': files,
  'missing_required': [],
  'info_request': infoRequest == null
      ? null
      : {'message': infoRequest, 'requested_at': '2030-03-01T08:00:00Z'},
  'timeline': [
    {
      'id': 't-1',
      'kind': 'CREATED',
      'status': 'DRAFT',
      'label': 'Application started',
      'message': null,
      'at': '2030-03-01T08:00:00Z',
    },
  ],
  'can_edit': status == 'DRAFT' || status == 'MORE_INFO',
  'can_submit': status == 'DRAFT' || status == 'MORE_INFO',
  'can_withdraw': status != 'WITHDRAWN',
  'erased': false,
  'created_at': '2030-03-01T08:00:00Z',
  'updated_at': '2030-03-01T08:00:00Z',
  'submitted_at': null,
  'decided_at': null,
};

void main() {
  final form = ApplicationForm.fromJson(formJson);

  group('the form', () {
    test('shows a question only when its condition holds', () {
      final details = form.fields.firstWhere((f) => f.key == 'pets_details');
      expect(form.visible(details, {'pets': 'no'}), isFalse);
      expect(form.visible(details, {'pets': 'yes'}), isTrue);
      expect(
        const VisibleIf(field: 'x', anyOf: ['a', 'b']).matches(['c', 'b']),
        isTrue,
      );
    });

    test('checks answers as the API does, hidden questions excluded', () {
      expect(
        form.problems({
          'people': 3,
          'pets': 'no',
          'income': ['f'],
        }),
        isEmpty,
      );
      final problems = form.problems({'people': 20, 'pets': 'yes'});
      expect(problems['people'], 'The highest allowed is 12.');
      expect(problems['pets_details'], 'This question needs an answer.');
      expect(problems['income'], 'This question needs an answer.');
      expect(
        const FormFieldSpec(
          key: 'k',
          type: 'multiple_choice',
          label: 'L',
          max: 2,
        ).problem(['a', 'b', 'c']),
        'Choose at most 2.',
      );
      expect(
        const FormFieldSpec(
          key: 'k',
          type: 'short_text',
          label: 'L',
        ).problem('x' * 201),
        'Keep it to 200 characters.',
      );
    });
  });

  group('the applications API', () {
    test('starts, saves, uploads, submits; closed intake says why', () async {
      final (:api, :requests) = routedApi({
        'POST /v1/me/applications': (request) =>
            jsonBody(request)['listing_id'] == 'closed'
            ? http.Response(
                '{"error":{"code":"APPLICATIONS_CLOSED","message":"Applications for this property are paused.","details":{"reason":"PAUSED","closes_at":null}}}',
                409,
              )
            : jsonResponse(201, {'application': appJson(), 'created': true}),
        'PATCH /v1/me/applications/app-1': (request) => {
          'application': appJson(
            answers: Map<String, dynamic>.from(
              jsonBody(request)['answers'] as Map,
            ),
          ),
        },
        'POST /v1/me/applications/app-1/files': (_) => jsonResponse(201, {
          'file_id': 'f-1',
          'application': appJson(
            answers: {
              'income': ['f-1'],
            },
            files: [
              {
                'id': 'f-1',
                'field': 'income',
                'file_name': 'payslip.pdf',
                'content_type': 'application/pdf',
                'size': 2048,
                'uploaded_at': '2030-03-01T08:00:00Z',
              },
            ],
          ),
        }),
        'POST /v1/me/applications/app-1/submit': (_) => {
          'application': appJson(
            status: 'SUBMITTED',
            reference: 'RPA-APP-2030-000001',
          ),
        },
      });
      final repo = MyApplicationsRepository(api);

      final draft = await repo.start('listing-1');
      expect(draft.form!.version, 2);
      await expectLater(
        repo.start('closed'),
        throwsA(
          isA<ApplicationsClosed>()
              .having((c) => c.reason, 'reason', 'PAUSED')
              .having((c) => c.message, 'message', contains('paused')),
        ),
      );

      final saved = await repo.save('app-1', {'pets': 'yes', 'old': null});
      expect(jsonBody(requests.last), {
        'answers': {'pets': 'yes', 'old': null},
      });
      expect(saved.answers['pets'], 'yes');

      final uploaded = await repo.upload('app-1', 'income', (
        bytes: [37, 80, 68, 70],
        name: 'payslip.pdf',
      ));
      final upload = requests.last;
      expect(upload.url.queryParameters['field'], 'income');
      expect(upload.headers['content-type'], startsWith('multipart/form-data'));
      expect(uploaded.files.single.fileName, 'payslip.pdf');

      final sent = await repo.submit('app-1');
      expect(sent.reference, 'RPA-APP-2030-000001');
    });

    test(
      'the agent side decides, asks for more and words a conflict',
      () async {
        const base = '/v1/agent/organisations/org-1/applications';
        final (:api, :requests) = routedApi({
          'GET $base': (_) => {
            'items': [appJson(status: 'SUBMITTED')],
            'page': 1,
            'page_size': 50,
            'total': 1,
            'total_pages': 1,
            'status_counts': {'SUBMITTED': 1},
          },
          'POST $base/app-1/status': (request) =>
              jsonBody(request)['status'] == 'ACCEPTED'
              ? apiError(409, 'INVALID_APPLICATION_TRANSITION')
              : {'application': appJson(status: 'SUBMITTED')},
          'POST $base/app-1/request-info': (_) => {
            'application': appJson(status: 'MORE_INFO', infoRequest: 'Payslip'),
          },
          'GET $base/other': (_) => apiError(404, 'APPLICATION_NOT_FOUND'),
        });
        final repo = AgentApplicationsRepository(api);
        final page = await repo.list('org-1', status: 'SUBMITTED');
        expect(page.counts['SUBMITTED'], 1);
        expect(requests.last.url.queryParameters['status'], 'SUBMITTED');

        await repo.decide('org-1', 'app-1', 'SHORTLISTED', note: ' Good fit ');
        expect(jsonBody(requests.last), {
          'status': 'SHORTLISTED',
          'note': 'Good fit',
        });
        await expectLater(
          repo.decide('org-1', 'app-1', 'ACCEPTED'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              contains('has changed since you opened it'),
            ),
          ),
        );
        final asked = await repo.requestInfo('org-1', 'app-1', 'A payslip');
        expect(asked.infoRequest, 'Payslip');
        await expectLater(
          repo.get('org-1', 'other'),
          throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
        );
      },
    );
  });

  group('applying in the app', () {
    testWidgets('steps, a conditional question, autosave, a file, review '
        'and the reference', (tester) async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      var answers = <String, dynamic>{};
      var files = <Map<String, dynamic>>[];
      serve(test, {
        'GET /v1/listings/${listing.slug}/application-form': (_) => {
          'form': formJson,
          'intake': {
            'status': 'OPEN',
            'closes_at': null,
            'closed_reason': null,
          },
        },
        'POST /v1/me/applications': (_) =>
            jsonResponse(201, {'application': appJson(), 'created': true}),
        'PATCH /v1/me/applications/app-1': (request) {
          answers = {
            ...answers,
            ...(bodyOf(request)['answers'] as Map<String, dynamic>),
          };
          return {'application': appJson(answers: answers, files: files)};
        },
        'POST /v1/me/applications/app-1/files': (_) {
          files = [
            {
              'id': 'f-1',
              'field': 'income',
              'file_name': 'payslip.pdf',
              'content_type': 'application/pdf',
              'size': 2048,
              'uploaded_at': '2030-03-01T08:00:00Z',
            },
          ];
          answers = {
            ...answers,
            'income': ['f-1'],
          };
          return jsonResponse(201, {
            'file_id': 'f-1',
            'application': appJson(answers: answers, files: files),
          });
        },
        'POST /v1/me/applications/app-1/submit': (_) => {
          'application': appJson(
            status: 'SUBMITTED',
            reference: 'RPA-APP-2030-000001',
          ),
        },
      });
      test.pickedFile = (bytes: [37, 80, 68, 70], name: 'payslip.pdf');
      await test.auth.signIn('tenant@example.test', 'pw');
      await pumpInApp(tester, test, ApplyScreen(slug: listing.slug));
      await settle(tester);

      expect(find.text('Your household'), findsOneWidget);
      expect(find.text('Describe them'), findsNothing);
      await tester.enterText(find.byKey(const Key('answer-people')), '3');
      await tester.tap(find.byKey(const Key('answer-pets-yes')));
      await tester.pump();
      expect(find.text('Describe them'), findsOneWidget);

      await tester.tap(find.byKey(const Key('apply-next')));
      await settle(tester);
      expect(find.text('This question needs an answer.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('answer-pets_details')),
        'One old cat',
      );
      await tester.pump(const Duration(milliseconds: 900));
      await settle(tester);
      expect(answers['pets_details'], 'One old cat');
      expect(answers['people'], 3);
      expect(find.textContaining('Saved'), findsOneWidget);

      await tester.tap(find.byKey(const Key('apply-next')));
      await settle(tester);
      expect(find.text('Documents'), findsOneWidget);
      await tester.tap(find.byKey(const Key('answer-income-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('file-from-files')));
      await settle(tester);
      expect(test.pickedFrom, ['files']);
      expect(find.text('payslip.pdf'), findsOneWidget);

      await tester.tap(find.byKey(const Key('apply-next')));
      await settle(tester);
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('One old cat'), findsOneWidget);
      expect(
        find.text('Only Sample Estates sees your answers.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('apply-submit')));
      await settle(tester);
      expect(find.text('Application sent'), findsOneWidget);
      expect(find.text('RPA-APP-2030-000001'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('closed intake and signed-out visitors are told plainly', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      serve(test, {
        'GET /v1/listings/${listing.slug}/application-form': (_) => {
          'form': formJson,
          'intake': {'status': 'PAUSED'},
        },
        'POST /v1/me/applications': (_) => http.Response(
          '{"error":{"code":"APPLICATIONS_CLOSED","message":"Applications for this property are paused. Please check back later.","details":{"reason":"PAUSED"}}}',
          409,
        ),
      });
      await pumpInApp(tester, test, ApplyScreen(slug: listing.slug));
      await settle(tester);
      expect(find.text('Sign in to apply'), findsOneWidget);

      await test.auth.signIn('tenant@example.test', 'pw');
      await tester.pumpWidget(const SizedBox());
      await pumpInApp(tester, test, ApplyScreen(slug: listing.slug));
      await settle(tester);
      expect(find.text('Applications are not open'), findsOneWidget);
      expect(find.textContaining('paused'), findsOneWidget);
    });

    testWidgets('a listing that takes applications shows Apply', (
      tester,
    ) async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      serve(test, {
        'GET /v1/listings/${listing.slug}': (_) => {
          'listing': {
            'slug': listing.slug,
            'applications': {
              'open': true,
              'closes_at': null,
              'form_name': 'Rental application',
            },
          },
        },
      });
      await pumpInApp(tester, test, ListingDetailScreen(slug: listing.slug));
      await settle(tester);
      expect(find.byKey(const Key('apply')), findsOneWidget);
      expect(find.textContaining('(Rental application)'), findsOneWidget);
    });

    testWidgets('the form holds at 200% text size', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/applications/app-1': (_) => {
          'application': appJson(answers: {'pets': 'yes'}),
        },
      });
      await pumpInApp(
        tester,
        test,
        const ApplyScreen(applicationId: 'app-1'),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      expect(find.text('Describe them'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an application waiting for more information', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/applications/app-1': (_) => {
          'application': appJson(
            status: 'MORE_INFO',
            reference: 'RPA-APP-2030-000001',
            infoRequest: 'A second payslip, please',
          ),
        },
        'POST /v1/me/applications/app-1/withdraw': (_) => {
          'application': appJson(status: 'WITHDRAWN'),
        },
      });
      await pumpInApp(tester, test, const MyApplicationScreen(id: 'app-1'));
      await settle(tester);
      expect(find.textContaining('A second payslip, please'), findsOneWidget);
      expect(find.text('Add what they asked for'), findsOneWidget);
      await tester.tap(find.byKey(const Key('application-withdraw')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('withdraw-confirm')));
      await settle(tester);
      expect(
        test.workRequests.any((r) => r.url.path.endsWith('/withdraw')),
        isTrue,
      );
    });
  });

  group('an organisation\'s applications', () {
    testWidgets('answers, a decision and a request for more', (tester) async {
      final test = TestServices();
      const base = '/v1/agent/organisations/org-1/applications';
      final received = {
        ...appJson(status: 'SUBMITTED', reference: 'RPA-APP-2030-000001'),
        'applicant': {
          'user_id': 'u-7',
          'name': 'Tom Tenant',
          'email': 'tenant@example.test',
        },
        'rendered': [
          {
            'key': 'household',
            'title': 'Your household',
            'description': null,
            'fields': [
              {
                'key': 'pets',
                'label': 'Do you have pets?',
                'type': 'single_choice',
                'visible': true,
                'answer': 'yes',
                'display': 'Yes',
                'files': [],
              },
              {
                'key': 'hidden',
                'label': 'Hidden one',
                'type': 'short_text',
                'visible': false,
                'answer': null,
                'display': null,
                'files': [],
              },
            ],
          },
        ],
        'notes': [],
        'allowed_transitions': [
          'UNDER_REVIEW',
          'MORE_INFO',
          'SHORTLISTED',
          'ACCEPTED',
          'REJECTED',
        ],
      };
      serve(test, {
        'GET $base/app-1': (_) => {'application': received},
        'POST $base/app-1/status': (_) => {
          'application': {
            ...received,
            'status': 'SHORTLISTED',
            'status_label': 'Shortlisted',
            'allowed_transitions': ['ACCEPTED', 'REJECTED'],
          },
        },
        'POST $base/app-1/request-info': (_) => {'application': received},
      });
      await pumpInApp(
        tester,
        test,
        const ReceivedApplicationScreen(organisationId: 'org-1', id: 'app-1'),
      );
      await settle(tester);
      expect(find.text('Tom Tenant'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('Hidden one'), findsNothing);

      await tester.tap(find.byKey(const Key('request-info')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('dialog-text')), 'A payslip');
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last), {'message': 'A payslip'});

      await tester.tap(find.byKey(const Key('decide-SHORTLISTED')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await settle(tester);
      expect(bodyOf(test.workRequests.last)['status'], 'SHORTLISTED');
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.byKey(const Key('request-info')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('another organisation\'s application is not found', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/organisations/org-1/applications/x': (_) =>
            apiError(404, 'APPLICATION_NOT_FOUND'),
      });
      await pumpInApp(
        tester,
        test,
        const ReceivedApplicationScreen(organisationId: 'org-1', id: 'x'),
      );
      await settle(tester);
      expect(find.text('Application not found'), findsOneWidget);
    });
  });
}
