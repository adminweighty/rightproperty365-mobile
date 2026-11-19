// Renders the app's real screens to PNG for the pitch deck. Skipped unless
// RENDER_PITCH is set:
//
//   RENDER_PITCH=1 flutter test test/pitch/render_pitch_screens_test.dart
//
// Output: build/pitch-screens/NN-feature-what.png, 390 x 844 logical pixels
// at 3x (1170 x 2532), from the actual widgets, router and theme, with the
// Roboto and Material Icons fonts from the Flutter SDK (what an Android
// phone shows: the brand's Inter is not bundled yet) and sample data served
// by a fake API. Nothing touches the network: map tiles are drawn stand-ins
// and the YouTube poster is a bundled sample photo.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/app_scope.dart';
import 'package:rightproperty365/app/theme/app_theme.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/core/location.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/venues/venue_repository.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../analytics_test.dart' as analytics show reportJson;
import '../applications_test.dart' as apps show appJson;
import '../contacts_test.dart' as crm show contactJson;
import '../ledger_test.dart'
    as ledger
    show cashbookJson, entryJson, optionsJson, page;
import '../map_search_test.dart' as maps show apiListing;
import '../notifications_test.dart'
    as notes
    show FakePush, itemJson, pageJson, preferencesJson;
import '../saved_listings_test.dart' as saved show page;
import '../support.dart';
import '../video_tour_test.dart' as tours show video;
import '../work_test.dart' show serve;

final _out = Directory('build/pitch-screens');
final _skip = Platform.environment['RENDER_PITCH'] == null
    ? 'Set RENDER_PITCH=1 to render the pitch screens'
    : null;

const _org = WorkOrganisation(
  id: 'org-1',
  name: 'Sample Estates',
  kind: 'AGENCY',
  marketCode: 'ZW',
  role: 'OWNER',
  roleLabel: 'Agency Principal',
  canManageListings: true,
);

Future<void> _loadFonts() async {
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final fonts = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
    'roboto-black.ttf',
    'roboto-italic.ttf',
  ]);
  // Text without a font family falls back to the system font on a phone
  // (Roboto on Android); in tests the fallback is the block test font.
  for (final family in ['FlutterTest', 'Ahem']) {
    await load(family, [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]);
  }
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

/// A stand-in map tile: a light street-grid pattern, drawn locally.
Future<Uint8List> _tilePng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()..color = const Color(0xFFF2EFE9),
  );
  final road = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 6;
  final minor = Paint()
    ..color = const Color(0xFFE4E0D8)
    ..strokeWidth = 2;
  for (var i = 0; i <= 256; i += 32) {
    canvas.drawLine(Offset(i.toDouble(), 0), Offset(i.toDouble(), 256), minor);
    canvas.drawLine(Offset(0, i.toDouble()), Offset(256, i.toDouble()), minor);
  }
  canvas.drawLine(const Offset(0, 96), const Offset(256, 120), road);
  canvas.drawLine(const Offset(140, 0), const Offset(110, 256), road);
  canvas.drawRect(
    const Rect.fromLTWH(170, 150, 60, 50),
    Paint()..color = const Color(0xFFD8E8C8),
  );
  final image = await recorder.endRecording().toImage(256, 256);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

class _Tiles extends TileProvider {
  _Tiles(this.png);
  final Uint8List png;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(png);
}

/// Serves a bundled sample photo for every network image (the YouTube
/// poster), so nothing is fetched.
class _LocalImages extends HttpOverrides {
  _LocalImages(this.bytes);
  final Uint8List bytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(bytes);
}

class _Client implements HttpClient {
  _Client(this.bytes);
  final Uint8List bytes;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final Uint8List bytes;

  @override
  Future<HttpClientResponse> close() async => _Response(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final Uint8List bytes;

  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _boundary = GlobalKey();

/// The app's theme with Roboto named wherever a style names no family.
/// On a phone such text falls back to the system font, Roboto on Android;
/// in tests the fallback is a block font that cannot be replaced, so this
/// names it. Nothing else differs from AppTheme.light().
ThemeData _withRoboto(ThemeData t) {
  TextStyle? r(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? b(ButtonStyle? s) => s?.copyWith(
    textStyle: s.textStyle == null
        ? null
        : WidgetStateProperty.resolveWith(
            (states) => r(s.textStyle!.resolve(states)),
          ),
  );
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle: r(t.appBarTheme.titleTextStyle),
    ),
    chipTheme: t.chipTheme.copyWith(labelStyle: r(t.chipTheme.labelStyle)),
    filledButtonTheme: FilledButtonThemeData(
      style: b(t.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: b(t.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(style: b(t.textButtonTheme.style)),
  );
}

/// Pumps the app as RightPropertyApp builds it (AppScope, router, theme) as
/// a phone.
Future<void> _pumpApp(WidgetTester tester, TestServices test) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  // flutter_test draws shadows as solid outlines unless they are enabled.
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: AppScope(
        services: test.services,
        child: MaterialApp.router(
          title: 'RightProperty365',
          debugShowCheckedModeBanner: false,
          theme: _withRoboto(AppTheme.light()),
          routerConfig: buildRouter(),
        ),
      ),
    ),
  );
  await _settle(tester);
}

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

/// Lets asset and network images decode, then settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = (element.widget as Image).image;
        try {
          await precacheImage(image, element);
        } on Object {
          // A failed image shows its fallback, as on a phone.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await _settle(tester);
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  // ignore: avoid_print
  print('rendered ${_out.path}/$name.png');
}

Map<String, dynamic> _fakeContact(
  String id,
  String name,
  String stage, {
  int due = 0,
  String type = 'tenant',
  String typeLabel = 'Tenant',
}) {
  final c = crm.contactJson(id: id, name: name, stage: stage, due: due);
  final first = name.split(' ').first.toLowerCase();
  return {
    ...c,
    'emails': ['$first@example.com'],
    'phones': ['+263770000${100 + id.hashCode % 800}'],
    'type': type,
    'type_label': typeLabel,
    'last_contact_at':
        '2026-11-${(18 - id.hashCode % 9).toString().padLeft(2, '0')}T08:00:00Z',
    'owner_name': 'Rudo Moyo',
    'tags': [if (stage == 'NEGOTIATING') 'avondale' else 'harare'],
  };
}

void main() {
  setUpAll(() async {
    if (_skip != null) return;
    await _loadFonts();
  });

  testWidgets('00 home and search', (tester) async {
    final test = TestServices();
    await _pumpApp(tester, test);
    await _shoot(tester, '00-home');
    _router(tester).go(Routes.search(query: ''));
    await _settle(tester);
    await _shoot(tester, '00-search-results');
  }, skip: _skip != null);

  testWidgets('01 saved properties', (tester) async {
    final test = TestServices();
    final ids = [for (final l in test.listings.listings.take(4)) l.id];
    serve(test, {
      'GET /v1/me/saved-listings/ids': (_) => {'ids': ids},
      'GET /v1/me/saved-listings': (_) => saved.page([
        for (final l in test.listings.listings.take(3))
          {
            'listing_id': l.id,
            'saved_at': '2026-11-15T08:00:00Z',
            'available': true,
            'unavailable_reason': null,
            'unavailable_label': null,
            'listing': {
              'slug': l.slug,
              'reference': l.reference,
              'title': l.title,
              'price': {'amount': l.price.amount, 'currency': l.price.currency},
            },
          },
        {
          'listing_id': 'gone',
          'saved_at': '2026-10-02T08:00:00Z',
          'available': false,
          'unavailable_reason': 'LET',
          'unavailable_label': 'Let',
          'listing': {
            'slug': null,
            'reference': 'RP-ZW-10031',
            'title': 'Two-bedroom cottage with garden',
            'price': {'amount': '650.00', 'currency': 'USD'},
            'price_period': 'month',
            'city': {'code': 'harare', 'label': 'Harare'},
            'country': {'code': 'ZW', 'name': 'Zimbabwe'},
          },
        },
      ]),
      'GET /v1/me/property-requests': (_) => {
        'items': [],
        'page': 1,
        'page_size': 50,
        'total': 0,
        'total_pages': 0,
        'status_counts': [],
      },
    });
    await test.auth.signIn('tenant@example.test', 'pw');
    await _pumpApp(tester, test);
    _router(tester).go(Routes.activity);
    await _settle(tester);
    await tester.ensureVisible(find.text('Saved Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved Properties'));
    await _shoot(tester, '01-saved-properties');
  }, skip: _skip != null);

  testWidgets('02 listing with a video tour', (tester) async {
    final poster = File('assets/images/listing-house-borrowdale.jpg')
        .readAsBytesSync();
    await HttpOverrides.runWithHttpOverrides(() async {
      final test = TestServices();
      final listing = test.listings.listings.first;
      serve(test, {
        'GET /v1/listings/${listing.slug}': (_) => {
          'listing': {'slug': listing.slug, 'video': tours.video()},
        },
      });
      await _pumpApp(tester, test);
      _router(tester).push(Routes.listing(listing.slug));
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('Video tour'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 120));
      await _shoot(tester, '02-listing-video-tour');
    }, _LocalImages(poster));
  }, skip: _skip != null);

  testWidgets('03 map search', (tester) async {
    final tile = (await tester.runAsync(_tilePng))!;
    final test = TestServices(
      mapTiles: MapTiles(
        urlTemplate: 'https://tiles.example/{z}/{x}/{y}.png',
        attribution: '© OpenStreetMap contributors',
        tileProvider: _Tiles(tile),
      ),
    );
    final spots = [
      (-17.7700, 31.0700, 'EXACT', 'Four-bedroom house with pool'),
      (-17.8000, 31.0300, 'EXACT', 'Two-bedroom garden apartment'),
      (-17.8150, 31.0900, 'APPROXIMATE', 'One-acre plot'),
      (-17.7850, 31.1100, 'EXACT', 'Modern townhouse'),
      (-17.8300, 31.0550, 'EXACT', 'Office suite in the CBD'),
    ];
    serve(test, {
      'GET /v1/listings': (request) {
        final items = [
          for (var i = 0; i < spots.length; i++)
            {
              ...maps.apiListing(
                '0${i + 1}',
                precision: spots[i].$3,
                photo:
                    '/assets/images/${['listing-house-highlands.jpg', 'listing-apartment-avondale.jpg', 'listing-plot-mutare.jpg', 'listing-townhouse-mount-pleasant.jpg', 'listing-office-cbd.jpg'][i]}',
              ),
              'title': spots[i].$4,
              'location': {
                'latitude': spots[i].$1,
                'longitude': spots[i].$2,
                'precision': spots[i].$3,
              },
            },
        ];
        return {
          'items': request.url.queryParameters['page_size'] == '1' ? [] : items,
          'page': 1,
          'page_size': 48,
          'total': 6,
          'total_pages': 1,
          'mappable_total': 5,
          'facets': {},
        };
      },
    });
    await _pumpApp(tester, test);
    _router(tester).go(Routes.search(query: ''));
    await _settle(tester);
    await tester.tap(find.text('Map'));
    await _shoot(tester, '03-map-search');
  }, skip: _skip != null);

  testWidgets('04 listing statistics', (tester) async {
    final test = TestServices();
    final report = analytics.reportJson();
    final days = [
      for (var i = 0; i < 30; i++)
        {
          'date': DateTime.utc(
            2026,
            10,
            20,
          ).add(Duration(days: i)).toIso8601String().substring(0, 10),
          'views': 4 + (i * 7) % 13 + i ~/ 3,
          'unique_views': 3 + (i * 5) % 9 + i ~/ 4,
          'impressions': 30 + i * 2,
          'contact_clicks': i % 4,
          'saves': i % 3,
          'enquiries': i % 5 == 0 ? 1 : 0,
        },
    ];
    serve(test, {
      'GET /v1/analytics/organisations/org-1': (_) => {
        ...report,
        'refreshed_at': '2026-11-18T10:15:00Z',
        'scope': 'organisation',
        'from': '2026-10-20',
        'to': '2026-11-18',
        'daily': days,
        'top_listings': [
          for (final l in test.listings.listings.take(3))
            {
              'listing_id': l.id,
              'title': l.title,
              'reference': l.reference,
              'slug': l.slug,
              'market_code': 'ZW',
              'views': 120 - test.listings.listings.indexOf(l) * 31,
              'unique_views': 90,
              'contact_clicks': 9,
              'enquiries': 5 - test.listings.listings.indexOf(l),
            },
        ],
      },
    });
    await test.auth.signIn('estates.owner@example.test', 'pw');
    await _pumpApp(tester, test);
    _router(tester).push(Routes.statistics, extra: const [_org]);
    await _shoot(tester, '04-listing-statistics');
  }, skip: _skip != null);

  testWidgets('05 contacts', (tester) async {
    final test = TestServices();
    const base = '/v1/agent/organisations/org-1/contacts';
    final people = [
      _fakeContact('c-1', 'Tariro Moyo', 'NEGOTIATING', due: 1),
      _fakeContact(
        'c-2',
        'Farai Chikwanha',
        'VIEWING_CONFIRMED',
        type: 'buyer',
        typeLabel: 'Buyer',
      ),
      _fakeContact('c-3', 'Nyasha Dube', 'CONTACTED'),
      _fakeContact(
        'c-4',
        'Kudzai Banda',
        'NEW',
        type: 'landlord',
        typeLabel: 'Landlord',
      ),
      _fakeContact(
        'c-5',
        'Rumbi Mlambo',
        'CLOSED',
        type: 'buyer',
        typeLabel: 'Buyer',
      ),
    ];
    final timeline = {
      'items': [
        {
          'id': 'e-4',
          'kind': 'NOTE_ADDED',
          'at': '2026-11-18T09:40:00Z',
          'actor_name': 'Rudo Moyo',
          'label': 'Note added',
          'text': 'Wants to move in on 1 December; asked about the borehole.',
          'data': {},
        },
        {
          'id': 'e-3',
          'kind': 'STAGE_CHANGED',
          'at': '2026-11-17T15:10:00Z',
          'actor_name': 'Rudo Moyo',
          'label': 'Stage changed from Viewing confirmed to Negotiating',
          'text': 'Offered USD 820 a month',
          'data': {},
        },
        {
          'id': 'e-2',
          'kind': 'STAGE_CHANGED',
          'at': '2026-11-13T10:00:00Z',
          'actor_name': 'Rudo Moyo',
          'label': 'Stage changed from Viewing requested to Viewing confirmed',
          'data': {},
        },
        {
          'id': 'e-1',
          'kind': 'APPOINTMENT',
          'at': '2026-11-12T08:00:00Z',
          'label': 'Linked to appointment AP-7K3M9QXD',
          'ref': {
            'kind': 'APPOINTMENT',
            'id': 'ap-6',
            'reference': 'AP-7K3M9QXD',
          },
          'data': {},
        },
      ],
    };
    serve(test, {
      'GET $base': (_) => {
        'items': people,
        'page': 1,
        'page_size': 25,
        'total': people.length,
        'total_pages': 1,
        'stage_counts': {
          'NEW': 1,
          'CONTACTED': 1,
          'VIEWING_REQUESTED': 0,
          'VIEWING_CONFIRMED': 1,
          'NEGOTIATING': 1,
          'CLOSED': 1,
          'UNSUCCESSFUL': 0,
        },
      },
      'GET $base/c-1': (_) => {
        'contact': people.first,
        'linked_items': [
          {
            'kind': 'APPOINTMENT',
            'id': 'ap-6',
            'reference': 'AP-7K3M9QXD',
            'type': 'VIEWING',
            'status': 'CONFIRMED',
            'title': 'Two-bedroom garden apartment',
            'listing_id': 'l-2',
            'created_at': '2026-11-12T08:00:00Z',
            'auto': true,
            'linked_at': '2026-11-12T08:00:00Z',
          },
        ],
        'reminders': [
          {
            'id': 'r-1',
            'contact_id': 'c-1',
            'due_at': '2026-11-19T07:00:00Z',
            'text': 'Send the draft lease',
            'done': false,
            'done_at': null,
            'created_by': {'user_id': 'u-1', 'name': 'Rudo Moyo'},
            'created_at': '2026-11-17T15:10:00Z',
            'overdue': false,
          },
        ],
      },
      'GET $base/c-1/timeline': (_) => timeline,
    });
    await test.auth.signIn('estates.owner@example.test', 'pw');
    await _pumpApp(tester, test);
    const book = ContactBook(
      id: 'org-1',
      name: 'Sample Estates',
      canWrite: true,
      canExport: true,
    );
    _router(tester).push(Routes.contacts, extra: const [book]);
    await _shoot(tester, '05-crm-contacts');
    _router(tester).push(Routes.contact('org-1', 'c-1'), extra: book);
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('History'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _shoot(tester, '05-crm-contact-timeline');
  }, skip: _skip != null);

  testWidgets('06 applications', (tester) async {
    final test = TestServices();
    final listing = test.listings.listings[1];
    final draft = {
      ...apps.appJson(answers: {'people': 2, 'pets': 'yes'}),
      'listing': {
        'slug': listing.slug,
        'reference': listing.reference,
        'title': listing.title,
      },
    };
    serve(test, {
      'GET /v1/me/applications/app-1': (_) => {'application': draft},
      'PATCH /v1/me/applications/app-1': (_) => {'application': draft},
      'GET /v1/me/applications': (_) => {
        'items': [
          {
            ...apps.appJson(
              status: 'MORE_INFO',
              reference: 'RPA-APP-2026-000014',
              infoRequest: 'A second payslip',
            ),
            'listing': {'slug': listing.slug, 'title': listing.title},
          },
          {
            ...apps.appJson(
              status: 'SUBMITTED',
              reference: 'RPA-APP-2026-000009',
            ),
            'id': 'app-2',
            'listing': {'slug': null, 'title': test.listings.listings[4].title},
          },
          {
            ...apps.appJson(),
            'id': 'app-3',
            'listing': {'slug': null, 'title': test.listings.listings[2].title},
          },
        ],
        'page': 1,
        'page_size': 50,
        'total': 3,
        'total_pages': 1,
      },
      'GET /v1/me/property-requests': (_) => {
        'items': [],
        'page': 1,
        'page_size': 50,
        'total': 0,
        'total_pages': 0,
        'status_counts': [],
      },
    });
    await test.auth.signIn('tenant@example.test', 'pw');
    await _pumpApp(tester, test);
    _router(tester).push(Routes.continueApplication('app-1'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('answer-pets_details')),
      'One cat, indoors, ten years old',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _shoot(tester, '06-application-form-step');

    _router(tester).go(Routes.activity);
    await _settle(tester);
    await tester.ensureVisible(find.text('My Applications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Applications'));
    await _shoot(tester, '06-my-applications');
  }, skip: _skip != null);

  // Uses http so the import is kept for the fake API's types.
  test('render setup', () => expect(http.Response, isNotNull), skip: _skip);
  testWidgets('07 hourly venue booking', (tester) async {
    final test = TestServices();
    Map<String, dynamic> r(String s, String e) => {
      'start': s,
      'end': e,
      'local_start': s,
      'local_end': e,
    };
    final days = [
      for (var i = 0; i < 6; i++)
        {
          'date': '2026-11-${(25 + i).toString().padLeft(2, '0')}',
          'weekday': (3 + i) % 7 + 1,
          'closed': i == 4,
          'note': null,
          'open_ranges': i == 4
              ? []
              : [
                  r(
                    '2026-11-${25 + i}T06:00:00Z',
                    '2026-11-${25 + i}T16:00:00Z',
                  ),
                ],
          'booked': i == 1
              ? [r('2026-11-26T08:00:00Z', '2026-11-26T12:30:00Z')]
              : [],
        },
    ];
    final quote = {
      'quote_id': 'q-1',
      'listing_id': 'venue-1',
      'expires_at': '2026-11-19T10:30:00Z',
      'currency': 'USD',
      'lines': [
        {
          'code': 'RATE',
          'kind': 'RATE',
          'label': '3 h × USD 50.00',
          'amount': '150.00',
        },
        {
          'code': 'TAX',
          'kind': 'PERCENT',
          'label': 'VAT 15%',
          'amount': '24.00',
        },
        {
          'code': 'CLEAN',
          'kind': 'FIXED',
          'label': 'Cleaning',
          'amount': '10.00',
        },
      ],
      'subtotal': '160.00',
      'deposit': '100.00',
      'deposit_note': 'payable to the host if confirmed',
      'total_excluding_deposit': '184.00',
      'start': '2026-11-26T12:30:00Z',
      'end': '2026-11-26T15:30:00Z',
      'duration_minutes': 180,
      'time_zone': 'Africa/Harare',
      'local_start': '2026-11-26T14:30:00+02:00',
      'local_end': '2026-11-26T17:30:00+02:00',
      'mode': 'ENQUIRY',
      'notice': venueNoPaymentNotice,
    };
    serve(test, {
      'GET /v1/venues/venue-1/availability': (_) => {
        'listing_id': 'venue-1',
        'time_zone': 'Africa/Harare',
        'currency': 'USD',
        'rate_per_hour': '50.00',
        'deposit': '100.00',
        'deposit_note': 'payable to the host if confirmed',
        'increment_minutes': 30,
        'min_minutes': 120,
        'max_minutes': 480,
        'cleaning_buffer_minutes': 30,
        'capacity': 1,
        'cancellation_policy': 'Cancel up to 48 hours before at no cost.',
        'free_cancellation_hours': 48,
        'mode': 'ENQUIRY',
        'notice': venueNoPaymentNotice,
        'days': days,
      },
      'POST /v1/venues/venue-1/quotes': (_) => jsonResponse(201, quote),
    });
    await _pumpApp(tester, test);
    _router(tester).push(
      Routes.bookHourly('venue-1'),
      extra: 'Glass-fronted showroom, Eastlea',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('venue-day-2026-11-26')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('venue-start-14:30')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('venue-duration-180')));
    await _settle(tester);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -380));
    await _shoot(tester, '07-venue-booking-quote');
  }, skip: _skip != null);

  testWidgets('08 ledger books', (tester) async {
    final test = TestServices();
    const base = '/v1/agent/organisations/org-1/ledger';
    final rent = ledger.entryJson();
    final repair = {
      ...ledger.entryJson(
        id: 'e-2',
        type: 'EXPENSE',
        amount: '120.00',
        out: true,
        reconciled: true,
      ),
      'type_label': 'Expense',
      'category': 'maintenance',
      'category_label': 'Maintenance',
      'method': 'CASH',
      'method_label': 'Cash',
      'effective_date': '2026-11-06',
      'description': 'Geyser element, flat 2',
      'contact': null,
    };
    final deposit = {
      ...ledger.entryJson(id: 'e-3', amount: '9500.00', currency: 'ZAR'),
      'type_label': 'Deposit received',
      'category_label': 'Deposit',
      'effective_date': '2026-11-12',
      'description': 'Deposit, Borrowdale cottage',
      'contact': {'id': 'c-3', 'name': 'Nyasha Dube'},
    };
    final cashbook = ledger.cashbookJson();
    final currencies = cashbook['currencies'] as List;
    currencies[0] = {
      ...currencies[0] as Map<String, dynamic>,
      'out': '120.00',
      'net': '580.00',
      'closing_balance': '1080.00',
      'entry_count': 2,
    };
    currencies[1] = {
      ...currencies[1] as Map<String, dynamic>,
      'in': '9500.00',
      'out': '0.00',
      'net': '9500.00',
      'closing_balance': '9500.00',
    };
    serve(test, {
      'GET $base/options': (_) => ledger.optionsJson(),
      'GET $base/reports/cashbook': (_) => cashbook,
      'GET $base/entries': (_) => ledger.page([deposit, repair, rent]),
    });
    await _pumpApp(tester, test);
    _router(tester).push(
      Routes.books,
      extra: const [
        ContactBook(id: 'org-1', name: 'Sample Estates', canWrite: true),
      ],
    );
    await _settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -620));
    await _shoot(tester, '08-ledger-books');
    await tester.tap(find.byKey(const Key('record-entry')));
    await _shoot(tester, '08-ledger-new-entry');
  }, skip: _skip != null);

  testWidgets('09 notifications', (tester) async {
    final test = TestServices();
    test.push = notes.FakePush();
    final items = [
      notes.itemJson(),
      {
        ...notes.itemJson(
          id: 'n-2',
          type: 'APPOINTMENT_CONFIRMED',
          title: 'Viewing confirmed',
          body: 'PR-ZW-10002 · Avondale',
          link: '/agent/appointments',
        ),
        'created_at': '2026-11-19T07:10:00Z',
      },
      {
        ...notes.itemJson(
          id: 'n-3',
          type: 'APPLICATION_RECEIVED',
          title: 'New rental application',
          body: 'RP-ZW-10014 · Mount Pleasant',
          link: '/agent/applications/app-1',
          read: true,
        ),
        'created_at': '2026-11-18T16:45:00Z',
      },
      {
        ...notes.itemJson(
          id: 'n-4',
          type: 'LISTING_REVIEWED',
          title: 'Listing approved',
          body: 'RP-ZW-10021 · Borrowdale Brooke',
          link: '/agent/listings/l-1',
          read: true,
        ),
        'created_at': '2026-11-18T11:20:00Z',
      },
    ];
    final prefs = notes.preferencesJson();
    final all = [
      (prefs['items'] as List).first,
      {
        ...(prefs['items'] as List).first as Map<String, dynamic>,
        'type': 'APPOINTMENT_REQUESTED',
        'label': 'Viewing requests',
        'email': false,
      },
      {
        ...(prefs['items'] as List).first as Map<String, dynamic>,
        'type': 'APPLICATION_RECEIVED',
        'label': 'Applications received',
      },
      (prefs['items'] as List).last,
    ];
    serve(test, {
      'GET /v1/me/notifications': (_) =>
          notes.pageJson(items, unread: 2, total: 4),
      'GET /v1/me/notifications/unread-count': (_) => {'unread_count': 2},
      'GET /v1/me/notification-preferences': (_) => {'items': all},
    });
    await test.auth.signIn('estates.owner@example.test', 'pw');
    await test.notificationCentre.start();
    await _pumpApp(tester, test);
    _router(tester).push(Routes.notifications);
    await _shoot(tester, '09-notifications-centre');
    _router(tester).push(Routes.notificationPreferences);
    await _shoot(tester, '09-notification-settings');
  }, skip: _skip != null);
}
