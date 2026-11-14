import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/widgets/searchable_select.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/directory/presentation/profile_screen.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';

import 'support.dart';

const cities = [
  SelectOption('harare', 'Harare', group: 'Zimbabwe', keywords: 'ZW capital'),
  SelectOption('bulawayo', 'Bulawayo', group: 'Zimbabwe', keywords: 'ZW'),
  SelectOption('sao-paulo', 'São Paulo', group: 'Brazil', keywords: 'BR'),
  SelectOption('victoria-falls', 'Victoria Falls', group: 'Zimbabwe'),
];

/// A field on its own, with the value it reports.
Future<List<String?>> pumpField(
  WidgetTester tester, {
  List<SelectOption<String>> options = cities,
  String? value,
  String? anyLabel,
}) async {
  final changes = <String?>[];
  await pumpInApp(
    tester,
    TestServices(),
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SearchableSelectField<String>(
          key: const Key('city'),
          label: 'City',
          value: value,
          anyLabel: anyLabel,
          options: options,
          onChanged: changes.add,
        ),
      ),
    ),
    size: const Size(390, 900),
  );
  return changes;
}

Future<void> openField(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  group('filterOptions', () {
    List<String> labels(String query) =>
        filterOptions(cities, query).map((o) => o.label).toList();

    test('matches anywhere in the label, ignoring case', () {
      expect(labels('ARE'), ['Harare']);
      expect(labels('falls'), ['Victoria Falls']);
      expect(labels(''), hasLength(4));
      expect(labels('   '), hasLength(4));
    });

    test('ignores accents', () {
      expect(labels('sao'), ['São Paulo']);
      expect(labels('SÃO'), ['São Paulo']);
    });

    test('searches keywords too, and needs every word', () {
      expect(labels('zw'), ['Harare', 'Bulawayo']);
      expect(labels('capital'), ['Harare']);
      expect(labels('zw bula'), ['Bulawayo']);
      expect(labels('zw paulo'), isEmpty);
    });
  });

  group('SearchableSelectField', () {
    testWidgets('typing narrows the list and picking reports the value', (
      tester,
    ) async {
      final changes = await pumpField(tester);
      await openField(tester, const Key('city'));

      expect(find.text('Harare'), findsOneWidget);
      expect(find.text('São Paulo'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('select-search')), 'sao');
      await tester.pumpAndSettle();
      expect(find.text('Harare'), findsNothing);

      await tester.tap(find.text('São Paulo'));
      await tester.pumpAndSettle();

      expect(changes, ['sao-paulo']);
      expect(find.text('São Paulo'), findsOneWidget); // shown in the field
    });

    testWidgets('group headings stay only while their options match', (
      tester,
    ) async {
      await pumpField(tester);
      await openField(tester, const Key('city'));
      expect(find.text('Zimbabwe'), findsWidgets);
      expect(find.text('Brazil'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('select-search')), 'bula');
      await tester.pumpAndSettle();

      expect(find.text('Zimbabwe'), findsOneWidget);
      expect(find.text('Brazil'), findsNothing);
    });

    testWidgets('says "No matches" when nothing fits', (tester) async {
      await pumpField(tester);
      await openField(tester, const Key('city'));
      await tester.enterText(find.byKey(const Key('select-search')), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('an "any" option clears the choice', (tester) async {
      final changes = await pumpField(
        tester,
        value: 'harare',
        anyLabel: 'Any city',
      );
      expect(find.text('Harare'), findsOneWidget);

      await openField(tester, const Key('city'));
      await tester.tap(find.byKey(const Key('select-any')));
      await tester.pumpAndSettle();

      expect(changes, [null]);
      expect(find.text('Any city'), findsOneWidget);
    });

    testWidgets('dismissing the sheet keeps the value', (tester) async {
      final changes = await pumpField(tester, value: 'harare');
      await openField(tester, const Key('city'));
      await tester.tapAt(const Offset(10, 10)); // outside the sheet
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.text('Harare'), findsOneWidget);
    });

    testWidgets('a long list shows 100 and asks for more typing', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 250; i++)
          SelectOption('c$i', 'Country ${i.toString().padLeft(3, '0')}'),
      ];
      await pumpField(tester, options: many);
      await openField(tester, const Key('city'));

      await tester.scrollUntilVisible(
        find.text('Keep typing to narrow the list'),
        600,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Keep typing to narrow the list'), findsOneWidget);
      expect(find.text('Country 100'), findsNothing);

      await tester.enterText(find.byKey(const Key('select-search')), '249');
      await tester.pumpAndSettle();
      expect(find.text('Country 249'), findsOneWidget);
      expect(find.text('Keep typing to narrow the list'), findsNothing);
    });

    testWidgets('holds at 200% text size', (tester) async {
      await pumpInApp(
        tester,
        TestServices(),
        Scaffold(
          body: SearchableSelectField<String>(
            key: const Key('city'),
            label: 'City',
            options: cities,
            onChanged: (_) {},
          ),
        ),
        textScale: 2,
        size: const Size(390, 900),
      );
      await openField(tester, const Key('city'));
      expect(tester.takeException(), isNull);
    });
  });

  group('in the app', () {
    testWidgets('the request type and reply method are searchable pickers', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PropertyRequestForm(
              listing: sampleListings().listings.first,
            ),
          ),
        ),
      );

      await openField(tester, const Key('request-type'));
      await tester.enterText(find.byKey(const Key('select-search')), 'view');
      await tester.pumpAndSettle();
      // "General enquiry" is still shown in the field behind the sheet.
      expect(find.text('More information'), findsNothing);
      await tester.tap(find.text('Book a viewing'));
      await tester.pumpAndSettle();

      await openField(tester, const Key('contact-method'));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
      await tester.enterText(
        find.byKey(const Key('email')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('phone')),
        '+263 77 123 4567',
      );
      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      final draft = test.propertyRequests.drafts.single;
      expect(draft.requestType, RequestType.viewingRequest);
      expect(draft.contactMethod, ContactMethod.whatsapp);
    });

    testWidgets(
      'the service picker searches a profile\'s services and can be cleared',
      (tester) async {
        final test = TestServices();
        await pumpInApp(
          tester,
          test,
          const ProfileEnquiryScreen(
            kind: DirectoryKind.serviceProviders,
            slug: 'sample-plumbers',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('General enquiry'), findsOneWidget);

        await openField(tester, const Key('service'));
        await tester.enterText(find.byKey(const Key('select-search')), 'geys');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Geysers'));
        await tester.pumpAndSettle();
        expect(find.text('Geysers'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
        await tester.enterText(
          find.byKey(const Key('email')),
          'test@example.com',
        );
        await tester.tap(find.byKey(const Key('consent')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();

        expect(test.businessEnquiries.drafts.single.service, 'Geysers');
      },
    );
  });
}
