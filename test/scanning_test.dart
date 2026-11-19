// Malware scanning (API 0.41.0), against fakes. Scanning is off on every
// server until MALWARE_SCANNER is set, so the "on" states here have not
// been seen from a real scanner.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/api/scan.dart';
import 'package:rightproperty365/features/applications/application_models.dart';
import 'package:rightproperty365/features/applications/applications_repository.dart';
import 'package:rightproperty365/features/applications/apply_screen.dart';
import 'package:rightproperty365/features/applications/received_applications.dart';
import 'package:rightproperty365/features/ledger/books_screens.dart';
import 'package:rightproperty365/features/ledger/ledger_repository.dart';
import 'package:rightproperty365/features/properties/inspection_repository.dart';
import 'package:rightproperty365/features/properties/maintenance_repository.dart';
import 'package:rightproperty365/features/signing/signing_repository.dart';

import 'api_routes.dart';
import 'applications_test.dart' show appJson, formJson;
import 'ledger_test.dart' show book, entryJson;
import 'support.dart';
import 'work_test.dart' show serve, settle;

const ChosenFile photo = (bytes: [1, 2, 3], name: 'photo.jpg');

Map<String, dynamic> file(String id, String? scan) => {
  'id': id,
  'field': 'income',
  'file_name': '$id.pdf',
  'size': 2048,
  'scan_status': ?scan,
};

/// The application with only the documents question, so the file rows are
/// on the first step.
Map<String, dynamic> documentsOnly(List<Map<String, dynamic>> files) => {
  ...appJson(
    answers: {
      'income': [for (final f in files) f['id']],
    },
    files: files,
  ),
  'form': {
    ...formJson,
    'sections': [(formJson['sections'] as List).last],
  },
};

void main() {
  group('scan_status', () {
    test('absent and LEGACY_UNSCANNED change nothing', () {
      for (final value in [
        null,
        'LEGACY_UNSCANNED',
        'CLEAN',
        'SOMETHING_NEW',
      ]) {
        final status = ScanStatus.parse(value);
        expect(status.notice, isNull, reason: '$value');
        expect(status.isPending || status.isInfected, isFalse);
      }
      expect(ApplicationFile.fromJson(file('f-1', null)).scan, ScanStatus.none);
      expect(
        ApplicationFile.fromJson(file('f-1', 'LEGACY_UNSCANNED')).scan,
        ScanStatus.legacy,
      );
    });

    test('PENDING and INFECTED are said plainly', () {
      expect(ScanStatus.parse('PENDING').notice, 'Being checked for viruses…');
      expect(ScanStatus.parse('INFECTED').notice, startsWith('Removed'));
    });
  });

  group('image uploads', () {
    ({ApiClient api, List<http.Request> requests}) answering(
      http.Response response,
    ) => mockApi((_) async => response);

    test('422 FILE_INFECTED: the file, not saved', () async {
      final infected = apiError(422, 'FILE_INFECTED');
      final uploads = <Future<void> Function()>[
        () =>
            MaintenanceRepository(answering(infected).api)
                .addPhoto('org-1', 'r-1', photo),
        () =>
            InspectionRepository(answering(apiError(422, 'FILE_INFECTED')).api)
                .addPhoto('org-1', 'i-1', 'it-1', photo),
        () =>
            ApiSigningRepository(answering(apiError(422, 'FILE_INFECTED')).api)
                .save(
                  signature: AdoptedSignature.image(
                    SignatureKind.drawn,
                    Uint8List.fromList([1, 2]),
                  ),
                ),
      ];
      for (final upload in uploads) {
        await expectLater(
          upload(),
          throwsA(
            isA<ApiFailure>()
                .having((f) => f.status, 'status', 422)
                .having((f) => f.code, 'code', 'FILE_INFECTED')
                .having(
                  (f) => f.message,
                  'message',
                  allOf(
                    contains('failed our virus check'),
                    contains('not saved'),
                  ),
                ),
          ),
        );
      }
    });

    test('503 SCANNER_UNAVAILABLE: try later, the file is fine', () async {
      for (final upload in <Future<void> Function()>[
        () => MaintenanceRepository(
          answering(
            apiError(
              503,
              'SCANNER_UNAVAILABLE',
              headers: {'retry-after': '60'},
            ),
          ).api,
        ).addPhoto('org-1', 'r-1', photo),
        () => InspectionRepository(
          answering(apiError(503, 'SCANNER_UNAVAILABLE')).api,
        ).addPhoto('org-1', 'i-1', 'it-1', photo),
      ]) {
        await expectLater(
          upload(),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.message,
              'message',
              allOf(
                contains('try again in a few minutes'),
                contains('not a problem with your file'),
              ),
            ),
          ),
        );
      }
    });

    test('a document read while being checked keeps the API wording', () async {
      final (:api, requests: _) = mockApi(
        (_) async => apiError(409, 'FILE_SCAN_PENDING'),
      );
      await expectLater(
        api.get('/v1/me/applications/app-1/files/f-1'),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.message,
            'message',
            'API says FILE_SCAN_PENDING',
          ),
        ),
      );
    });
  });

  group('application files', () {
    testWidgets('no scan_status: as before', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/applications/app-1': (_) => {
          'application': documentsOnly([
            file('f-1', null),
            file('f-2', 'LEGACY_UNSCANNED'),
            file('f-3', 'CLEAN'),
          ]),
        },
      });
      await pumpInApp(tester, test, const ApplyScreen(applicationId: 'app-1'));
      await settle(tester);
      expect(find.text('f-1.pdf'), findsOneWidget);
      expect(find.text('2 KB'), findsNWidgets(3));
      expect(find.textContaining('virus'), findsNothing);
      expect(find.byKey(const Key('answer-income-check')), findsNothing);
    });

    testWidgets('PENDING shows being checked, then the outcome', (
      tester,
    ) async {
      final test = TestServices();
      var reads = 0;
      serve(test, {
        'GET /v1/me/applications/app-1': (_) {
          reads++;
          return {
            'application': documentsOnly([
              file('f-1', reads < 3 ? 'PENDING' : 'CLEAN'),
              file('f-2', reads < 3 ? 'PENDING' : 'INFECTED'),
            ]),
          };
        },
      });
      await pumpInApp(tester, test, const ApplyScreen(applicationId: 'app-1'));
      await settle(tester);
      expect(find.text('Being checked for viruses…'), findsNWidgets(2));
      // A refresh by hand.
      await tester.tap(find.byKey(const Key('answer-income-check')));
      await settle(tester);
      expect(reads, 2);
      // And on its own a few seconds later.
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(reads, 3);
      expect(find.text('Being checked for viruses…'), findsNothing);
      expect(find.textContaining('Removed: it failed'), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
      expect(find.byKey(const Key('answer-income-check')), findsNothing);
      // An infected file can still be removed and replaced.
      expect(find.byTooltip('Remove f-2.pdf'), findsOneWidget);
      // Nothing is read again once nothing is being checked.
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 3);
    });

    testWidgets('the advertiser sees the same states', (tester) async {
      final test = TestServices();
      const base = '/v1/agent/organisations/org-1/applications';
      serve(test, {
        'GET $base/app-1': (_) => {
          'application': {
            ...appJson(status: 'SUBMITTED'),
            'applicant': {'user_id': 'u-7', 'name': 'Tom Tenant'},
            'rendered': [
              {
                'key': 'documents',
                'title': 'Documents',
                'fields': [
                  {
                    'key': 'income',
                    'label': 'Proof of income',
                    'type': 'file',
                    'visible': true,
                    'files': [
                      file('f-1', null),
                      file('f-2', 'PENDING'),
                      file('f-3', 'INFECTED'),
                      file('f-4', 'LEGACY_UNSCANNED'),
                    ],
                  },
                ],
              },
            ],
            'notes': [],
            'allowed_transitions': [],
          },
        },
      });
      await pumpInApp(
        tester,
        test,
        const ReceivedApplicationScreen(organisationId: 'org-1', id: 'app-1'),
      );
      await settle(tester);
      expect(find.text('f-1.pdf'), findsOneWidget);
      expect(find.text('f-4.pdf'), findsOneWidget);
      expect(find.text('f-2.pdf\nBeing checked for viruses…'), findsOneWidget);
      expect(find.textContaining('f-3.pdf\nRemoved'), findsOneWidget);
    });
  });

  group('ledger receipts', () {
    testWidgets('each state, and a refresh while one is checked', (
      tester,
    ) async {
      final test = TestServices();
      var reads = 0;
      serve(test, {
        'GET /v1/agent/organisations/org-1/ledger/entries/e-1': (_) {
          reads++;
          return {
            'entry': entryJson(),
            'notes': [],
            'attachments': [
              {'id': 'a-1', 'file_name': 'old.pdf'},
              {
                'id': 'a-2',
                'file_name': 'new.pdf',
                'scan_status': reads == 1 ? 'PENDING' : 'CLEAN',
              },
              {'id': 'a-3', 'file_name': 'bad.pdf', 'scan_status': 'INFECTED'},
            ],
            'related': [],
          };
        },
      });
      await pumpInApp(
        tester,
        test,
        const LedgerEntryScreen(book: book, id: 'e-1'),
      );
      await settle(tester);
      expect(find.text('old.pdf'), findsOneWidget);
      expect(find.text('Being checked for viruses…'), findsOneWidget);
      expect(find.textContaining('Removed: it failed'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('receipts-check')));
      await tester.tap(find.byKey(const Key('receipts-check')));
      await settle(tester);
      expect(reads, 2);
      expect(find.text('Being checked for viruses…'), findsNothing);
      expect(find.byKey(const Key('receipts-check')), findsNothing);
    });

    test('the entry detail keeps the status', () async {
      final (:api, requests: _) = routedApi({
        'GET /v1/agent/organisations/org-1/ledger/entries/e-1': (_) => {
          'entry': entryJson(),
          'notes': [],
          'attachments': [
            {'id': 'a-1', 'file_name': 'r.pdf', 'scan_status': 'PENDING'},
            {'id': 'a-2', 'file_name': 's.pdf'},
          ],
          'related': [],
        },
      });
      final detail = await LedgerRepository(api).entry('org-1', 'e-1');
      expect(detail.attachments.map((a) => a.scan), [
        ScanStatus.pending,
        ScanStatus.none,
      ]);
    });
  });
}
