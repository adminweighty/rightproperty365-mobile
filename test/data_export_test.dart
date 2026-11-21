import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/features/auth/data/data_export.dart';
import 'package:rightproperty365/features/auth/presentation/data_export_screen.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';

import 'support.dart';
import 'work_test.dart' show failure, serve, settle;

Map<String, dynamic> exportJson(String status) => {
  'id': 'ex-1',
  'status': status,
  'requested_at': '2030-03-01T08:00:00Z',
  'ready_at': status == 'READY' ? '2030-03-01T08:02:00Z' : null,
  'expires_at': status == 'READY' ? '2030-03-08T08:02:00Z' : null,
  'size_bytes': status == 'READY' ? 2516582 : null,
  'downloads': 0,
};

void main() {
  test('reads the export and its size', () {
    final e = DataExport.fromJson(exportJson('READY'));
    expect(e.status, ExportStatus.ready);
    expect(e.sizeLabel, '2.4 MB');
    expect(
      DataExport.fromJson({...exportJson('READY'), 'size_bytes': 850000})
          .sizeLabel,
      '831 KB',
    );
    expect(ExportStatus.building.pending, isTrue);
  });

  testWidgets('none yet: ask, then it is being prepared', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/me/data-export': (_) => {'export': null},
      'POST /v1/me/data-export': (_) =>
          http.Response(jsonEncode({'export': exportJson('REQUESTED')}), 202),
    });
    await pumpInApp(tester, test, const DataExportScreen());
    await settle(tester);
    expect(find.byKey(const Key('export-state')), findsNothing);
    await tester.tap(find.byKey(const Key('export-request')));
    await settle(tester);
    expect(find.textContaining('Being prepared'), findsOneWidget);
    expect(find.byKey(const Key('export-request')), findsNothing);
    expect(find.byKey(const Key('export-refresh')), findsOneWidget);
  });

  testWidgets('ready: downloaded through the API and saved', (tester) async {
    final test = TestServices();
    final zip = [0x50, 0x4b, 0x03, 0x04, 1, 2, 3];
    serve(test, {
      'GET /v1/me/data-export': (_) => {'export': exportJson('READY')},
      'GET /v1/me/data-export/download': (_) => http.Response.bytes(
        zip,
        200,
        headers: {'content-type': 'application/zip'},
      ),
    });
    await pumpInApp(tester, test, const DataExportScreen());
    await settle(tester);
    expect(find.textContaining('Ready until 8 Mar 2030'), findsOneWidget);
    expect(find.textContaining('2.4 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-download')));
    await settle(tester);
    final saved = test.savedFiles.single;
    expect(saved.name, 'rightproperty365-data.zip');
    expect(saved.mimeType, 'application/zip');
    expect(saved.bytes, zip);
    // The token goes in the header, never in the address.
    final get = test.workRequests.last;
    expect(get.url.path, '/v1/me/data-export/download');
    expect(get.url.query, isEmpty);
    expect(find.text('Your data is saved on this phone.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a cancelled save says nothing', (tester) async {
    final test = TestServices()..saveAccepted = false;
    serve(test, {
      'GET /v1/me/data-export': (_) => {'export': exportJson('READY')},
      'GET /v1/me/data-export/download': (_) => http.Response.bytes([1], 200),
    });
    await pumpInApp(tester, test, const DataExportScreen());
    await settle(tester);
    await tester.tap(find.byKey(const Key('export-download')));
    await settle(tester);
    expect(find.text('Your data is saved on this phone.'), findsNothing);
  });

  testWidgets('asking twice in a day says why', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/me/data-export': (_) => {'export': exportJson('EXPIRED')},
      'POST /v1/me/data-export': (_) => failure(409, 'EXPORT_RECENT'),
    });
    await pumpInApp(tester, test, const DataExportScreen());
    await settle(tester);
    expect(find.textContaining('has expired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-request')));
    await settle(tester);
    expect(find.textContaining('in the last 24 hours'), findsOneWidget);
  });

  testWidgets('holds at 200% text', (tester) async {
    final test = TestServices();
    serve(test, {
      'GET /v1/me/data-export': (_) => {'export': exportJson('READY')},
    });
    await pumpInApp(tester, test, const DataExportScreen(), textScale: 2);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('export-download'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  test('the ready notice opens the screen', () async {
    final app = TestServices();
    final where = await resolveNotificationLink(
      '/account/data-export',
      app.services,
    );
    expect((where as InApp).location, Routes.dataExport);
  });
}
