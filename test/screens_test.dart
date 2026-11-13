import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/auth/presentation/auth_screens.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/directory/presentation/directory_screens.dart';
import 'package:rightproperty365/features/directory/presentation/profile_screen.dart';
import 'package:rightproperty365/features/listings/presentation/home_screen.dart';
import 'package:rightproperty365/features/property_requests/presentation/property_request_screen.dart';

import 'support.dart';

Future<void> fillGuestAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('name')), 'Test Customer');
  await tester.enterText(find.byKey(const Key('email')), 'test@example.com');
  await tester.tap(find.byKey(const Key('consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pumpAndSettle();
}

/// Text that looks like a phone number or an email address.
final contactDetail = RegExp(r'(\+?\d[\d\s-]{7,}\d)|([\w.+-]+@[\w-]+\.[\w.]+)');

void main() {
  group('listing request form', () {
    Widget form(TestServices test) => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PropertyRequestForm(listing: sampleListings().listings.first),
      ),
    );

    testWidgets('blocks an empty form and asks for consent', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, form(test));

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Tick the box to send your request'), findsOneWidget);
      expect(test.propertyRequests.drafts, isEmpty);
    });

    testWidgets(
      'a valid request shows "received" with the reference, never "delivered"',
      (tester) async {
        final test = TestServices();
        await pumpInApp(tester, test, form(test));

        await fillGuestAndSubmit(tester);

        expect(find.text('Request received'), findsOneWidget);
        expect(find.text('RP-8VXWDQJG'), findsOneWidget);
        expect(find.textContaining('delivered'), findsNothing);

        final draft = test.propertyRequests.drafts.single;
        expect(draft.listingId, sampleListings().listings.first.id);
        expect(draft.contact.name, 'Test Customer');
        expect(draft.consentAccepted, isTrue);
      },
    );

    testWidgets('API field errors appear under the matching control', (
      tester,
    ) async {
      final test = TestServices();
      test.propertyRequests.failure = const ApiFailure(
        status: 400,
        code: 'VALIDATION_FAILED',
        message: 'The request is invalid.',
        fields: {'guest_contact.email': 'must be a valid email address'},
        traceId: 'trace-9',
      );
      await pumpInApp(tester, test, form(test));

      await fillGuestAndSubmit(tester);

      expect(
        find.text('Email address must be a valid email address'),
        findsOneWidget,
      );
      expect(find.text('Support reference: trace-9'), findsOneWidget);
      expect(find.text('Request received'), findsNothing);
    });

    testWidgets(
      'a network failure shows its message and keeps what was typed',
      (tester) async {
        final test = TestServices();
        test.propertyRequests.failure = const ApiFailure.network();
        await pumpInApp(tester, test, form(test));

        await fillGuestAndSubmit(tester);

        expect(
          find.textContaining('We could not reach RightProperty365'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('name')))
              .controller!
              .text,
          'Test Customer',
        );
      },
    );

    testWidgets('a signed-in customer is not asked for name or email', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, form(test));

      expect(find.byKey(const Key('name')), findsNothing);
      expect(find.byKey(const Key('email')), findsNothing);
      expect(find.textContaining('Sending as Tendai Ncube'), findsOneWidget);

      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      final contact = test.propertyRequests.drafts.single.contact;
      expect(contact.name, isNull);
      expect(contact.email, isNull);
      expect(find.text('Request received'), findsOneWidget);
    });

    testWidgets('lays out without overflow at 200% text size', (tester) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        form(test),
        textScale: 2,
        size: const Size(390, 4000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('directory', () {
    testWidgets('a list labels sponsored profiles and puts them first', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const DirectoryListScreen(kind: DirectoryKind.agencies),
      );
      await tester.pumpAndSettle();

      final agencies = sampleDirectory().ofKind(DirectoryKind.agencies);
      expect(
        find.text('Sponsored'),
        findsNWidgets(agencies.where((a) => a.sponsored).length),
      );
      final first = tester.getTopLeft(find.text(agencies.first.name)).dy;
      final last = tester.getTopLeft(find.text(agencies.last.name)).dy;
      expect(first, lessThan(last));
      expect(agencies.first.sponsored, isTrue);
    });

    testWidgets('service providers are grouped under their trade', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const DirectoryListScreen(kind: DirectoryKind.serviceProviders),
        size: const Size(390, 6000),
      );
      await tester.pumpAndSettle();

      for (final group in sampleDirectory().serviceCategories()) {
        expect(find.text(group.category), findsWidgets);
      }
    });

    testWidgets(
      'a profile shows no phone number or email, only an enquiry button',
      (tester) async {
        final test = TestServices();
        await pumpInApp(
          tester,
          test,
          const ProfileScreen(
            kind: DirectoryKind.agencies,
            slug: 'sample-estates',
          ),
          size: const Size(390, 8000),
        );
        await tester.pumpAndSettle();

        expect(find.text('Send an enquiry to Sample Estates'), findsOneWidget);
        expect(find.text('Agents'), findsOneWidget);
        expect(find.text('Properties'), findsOneWidget);
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          final value = text.data ?? text.textSpan?.toPlainText() ?? '';
          // Prices and areas are numbers too; only contact-like text matters.
          if (value.startsWith('USD') || value.contains('m²')) continue;
          expect(
            contactDetail.hasMatch(value),
            isFalse,
            reason: 'Contact detail shown: "$value"',
          );
        }
      },
    );

    testWidgets(
      'the enquiry form explains a 404 while the endpoint is not live',
      (tester) async {
        final test = TestServices();
        test.businessEnquiries.failure = const ApiFailure(
          status: 404,
          code: 'NOT_FOUND',
          message: 'Enquiries to this profile are not available yet. Please try again later.',
        );
        await pumpInApp(
          tester,
          test,
          const ProfileEnquiryScreen(
            kind: DirectoryKind.serviceProviders,
            slug: 'sample-plumbers',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('service')), findsOneWidget);
        expect(find.byKey(const Key('request-type')), findsNothing);
        await fillGuestAndSubmit(tester);

        expect(find.textContaining('not available yet'), findsOneWidget);
        expect(find.text('Request received'), findsNothing);
        expect(
          test.businessEnquiries.drafts.single.recipient.slug,
          'sample-plumbers',
        );
      },
    );
  });

  group('account', () {
    testWidgets('signed out offers sign-in and registration', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const AccountScreen());

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('signed in shows roles and memberships, and signs out', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const AccountScreen());

      expect(find.text('Tendai Ncube'), findsOneWidget);
      expect(find.text('Buyer or renter'), findsOneWidget);
      expect(find.text('Estate agent'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Sample Estates'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();

      expect(test.auth.signedIn, isFalse);
      expect(test.tokens.token, isNull);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets(
      'registration sends the chosen roles and then asks to check email',
      (tester) async {
        final test = TestServices();
        await pumpInApp(
          tester,
          test,
          const RegisterScreen(),
          size: const Size(390, 3200),
        );

        await tester.enterText(
          find.byKey(const Key('register-name')),
          'New Person',
        );
        await tester.enterText(
          find.byKey(const Key('register-email')),
          'new@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('register-password')),
          'correct-horse-battery',
        );
        await tester.tap(find.byKey(const Key('role-LANDLORD')));
        await tester.tap(find.byKey(const Key('register-consent')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('register-submit')));
        await tester.pumpAndSettle();

        expect(test.authRepository.registered?['roles'], [
          'CONSUMER',
          'LANDLORD',
        ]);
        expect(find.text('Check your email'), findsOneWidget);
        expect(find.textContaining('account has been created'), findsNothing);
      },
    );
  });

  testWidgets('home shows every section from the sample data', (tester) async {
    final test = TestServices();
    await pumpInApp(
      tester,
      test,
      const HomeScreen(),
      size: const Size(390, 6000),
    );
    await tester.pumpAndSettle();

    for (final heading in [
      'Just listed',
      'Featured collection',
      'Homes for sale',
      'Homes to rent',
      'Commercial and land',
      'Explore by city',
      'Popular suburbs',
      'Property directory',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text('18'), findsOneWidget); // properties stat
    expect(find.text('Estate agencies'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
