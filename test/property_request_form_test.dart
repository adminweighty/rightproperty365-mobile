import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/app_scope.dart';
import 'package:rightproperty365/app/theme/app_theme.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/listings/data/listing_repository.dart';
import 'package:rightproperty365/features/listings/data/sample_listings.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';

class FakeRequests implements PropertyRequestRepository {
  final drafts = <PropertyRequestDraft>[];
  ApiFailure? failure;

  @override
  Future<PropertyRequestReceipt> submit(PropertyRequestDraft draft) async {
    drafts.add(draft);
    if (failure != null) throw failure!;
    return PropertyRequestReceipt(
      requestId: 'id',
      reference: 'RP-8VXWDQJG',
      status: 'RECEIVED',
      createdAt: DateTime.utc(2026, 11, 13),
    );
  }
}

Future<void> pumpForm(
  WidgetTester tester,
  FakeRequests requests, {
  double textScale = 1,
}) async {
  // A phone-sized surface, tall enough that every field is built.
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      listings: const SampleListingRepository(),
      propertyRequests: requests,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PropertyRequestForm(listing: sampleListings.first),
          ),
        ),
      ),
    ),
  );
}

Future<void> fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
  await tester.enterText(find.byKey(const Key('email')), 'test@example.com');
  await tester.tap(find.byKey(const Key('consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocks an empty form and asks for consent', (tester) async {
    final requests = FakeRequests();
    await pumpForm(tester, requests);

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Tick the box to send your request'), findsOneWidget);
    expect(requests.drafts, isEmpty);
  });

  testWidgets(
    'a valid request shows "received" with the reference, never "delivered"',
    (tester) async {
      final requests = FakeRequests();
      await pumpForm(tester, requests);

      await fillAndSubmit(tester);

      expect(find.text('Request received'), findsOneWidget);
      expect(find.text('RP-8VXWDQJG'), findsOneWidget);
      expect(find.textContaining('delivered'), findsNothing);

      final draft = requests.drafts.single;
      expect(draft.listingId, sampleListings.first.id);
      expect(draft.name, 'Test Customer');
      expect(draft.consentAccepted, isTrue);
      expect(draft.contactMethod, ContactMethod.email);
    },
  );

  testWidgets('API field errors appear under the matching control', (
    tester,
  ) async {
    final requests = FakeRequests()
      ..failure = const ApiFailure(
        status: 400,
        code: 'VALIDATION_FAILED',
        message: 'The request is invalid.',
        fields: {'guest_contact.email': 'must be a valid email address'},
        traceId: 'trace-9',
      );
    await pumpForm(tester, requests);

    await fillAndSubmit(tester);

    expect(
      find.text('Email address must be a valid email address'),
      findsOneWidget,
    );
    expect(find.text('Support reference: trace-9'), findsOneWidget);
    expect(find.text('Request received'), findsNothing);
  });

  testWidgets('a failure without fields shows its message and keeps the form', (
    tester,
  ) async {
    final requests = FakeRequests()..failure = const ApiFailure.network();
    await pumpForm(tester, requests);

    await fillAndSubmit(tester);

    expect(
      find.textContaining('We could not reach RightProperty365'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('submit')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('name')))
          .controller!
          .text,
      'Test Customer',
    );
  });

  testWidgets('lays out without overflow at 200% text size', (tester) async {
    await pumpForm(tester, FakeRequests(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
