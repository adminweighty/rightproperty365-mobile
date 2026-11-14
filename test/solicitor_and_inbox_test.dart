import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/terminology.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/presentation/auth_screens.dart';
import 'package:rightproperty365/features/directory/data/directory_repository.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/directory/presentation/directory_screens.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_screen.dart';

import 'support.dart';

const propertyRequest = {
  'request_id': '0195c0de-1111-7000-8000-000000000001',
  'reference': 'RP-8VXWDQJG',
  'listing_id': '0195c0de-0000-7000-8000-000000000001',
  'listing': {
    'slug': 'four-bedroom-family-home-borrowdale',
    'title': 'Four-bedroom family home',
    'reference': 'RP-ZW-10001',
  },
  'request_type': 'VIEWING_REQUEST',
  'status': 'RECEIVED',
  'message': 'May I view on Saturday?',
  'preferred_contact_method': 'WHATSAPP',
  'contact': {
    'name': 'Casey Seeker',
    'email': 'casey@example.test',
    'phone': '+263771234567',
  },
  'created_at': '2026-11-13T09:00:00Z',
};

const businessEnquiry = {
  'enquiry_id': '0195c0de-2222-7000-8000-000000000001',
  'reference': 'BE-3KQ7M2XT',
  'recipient': {
    'kind': 'solicitors',
    'slug': 'sample-solicitors',
    'name': 'Sample Solicitors',
  },
  'service': 'Conveyancing',
  'message': 'Please quote for a transfer.',
  'preferred_contact_method': 'EMAIL',
  'contact': {'name': 'Pat Buyer', 'email': 'pat@example.test', 'phone': null},
  'status': 'RECEIVED',
  'created_at': '2026-11-14T09:00:00Z',
};

http.Response forbidden() => jsonResponse(403, {
  'error': {'code': 'FORBIDDEN', 'message': 'no'},
  'trace_id': 't',
});

void main() {
  group('roles from the API', () {
    // What an API that has not added Solicitor yet would list.
    final withoutSolicitor = builtInRoles
        .where((r) => r.code != 'SOLICITOR')
        .toList();
    Iterable<String> offered(List<SelectableRole> accepted) =>
        signUpRoleGroups(accepted).expand((g) => g.roles).map((r) => r.label);

    test('Solicitor has its name, a law firm kind and a directory', () {
      expect(roleLabel('SOLICITOR'), 'Solicitor');
      expect(roleLabel('SALES_AGENT'), 'Sales Agent');
      expect(roleLabel('LETTINGS_AGENT'), 'Lettings Agent');
      expect(roleLabel('PROPERTY_MANAGER'), 'Property Manager');
      expect(organisationKindLabel('LAW_FIRM'), 'Law Firm');
      expect(organisationKindLabel('PROPERTY_MANAGER'), 'Property Manager');
      expect(DirectoryKind.fromSlug('solicitors'), DirectoryKind.solicitors);
    });

    test('only roles the API lists are offered', () {
      expect(offered(withoutSolicitor), isNot(contains('Solicitor')));
      expect(offered(builtInRoles), contains('Solicitor'));
      expect(
        offered(builtInRoles),
        containsAll(['Sales Agent', 'Lettings Agent', 'Property Manager']),
      );
    });

    test(
      'labels and group headings are the API\'s; descriptions are the app\'s',
      () {
        final groups = signUpRoleGroups(const [
          SelectableRole('CONSUMER', 'Home Buyer', 'People looking'),
          SelectableRole('SOLICITOR', 'Conveyancing Solicitor', 'Legal'),
          SelectableRole('TENANT', 'Renter', 'People looking'),
          SelectableRole('VALUER', 'Property Valuer', 'Legal'),
          SelectableRole('AGENT', 'Estate Agent'),
          SelectableRole('MYSTERY', 'Mystery Role'),
        ]);

        expect(groups.map((g) => g.legend), [
          'People looking',
          'Legal',
          'Real Estate Professionals', // no heading from the API: the app's own
          'Other roles',
        ]);
        expect(groups[0].roles.map((r) => r.label), ['Home Buyer', 'Renter']);
        expect(groups[1].roles.map((r) => r.label), [
          'Conveyancing Solicitor',
          'Property Valuer',
        ]);
        expect(groups[1].roles.first.description, contains('conveyancing'));
        expect(groups[1].roles.last.description, isEmpty);
      },
    );

    test(
      'the accepted roles are read from the reference set with their groups',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(200, {
            'set': 'account_roles',
            'market': null,
            'items': [
              {
                'code': 'CONSUMER',
                'label': 'Prospective Buyer',
                'group': {
                  'code': 'seekers',
                  'label': 'Property Seekers',
                  'sort_order': 10,
                },
              },
              {'code': 'SOLICITOR', 'label': 'Solicitor', 'group': null},
            ],
          }),
        );

        final roles = await ApiAuthRepository(api).selectableRoles();

        expect(requests.single.url.path, '/v1/reference/account_roles');
        expect(roles.map((r) => r.code), ['CONSUMER', 'SOLICITOR']);
        expect(roles.first.group, 'Property Seekers');
        expect(roles.last.group, isNull);
      },
    );

    test('a membership uses the role label the API sends', () {
      final user = User.fromJson({
        'id': 'u',
        'name': 'n',
        'email': 'e@example.test',
        'memberships': [
          {
            'organisation_name': 'Sample Solicitors',
            'organisation_kind': 'LAW_FIRM',
            'market_code': 'ZW',
            'role': 'OWNER',
            'role_label': 'Principal',
          },
          {
            'organisation_name': 'Sample Estates',
            'organisation_kind': 'AGENCY',
            'market_code': 'ZW',
            'role': 'OWNER',
          },
        ],
      });
      expect(user.memberships.first.roleLabel, 'Principal');
      expect(user.memberships.first.kindLabel, 'Law Firm');
      expect(user.memberships.last.roleLabel, 'Agency Principal');
    });
  });

  group('Solicitors directory', () {
    test('always exists, and lists solicitors when the data has them', () {
      final empty = sampleDirectory();
      expect(empty.directories.last.kind, DirectoryKind.solicitors);
      expect(empty.info(DirectoryKind.solicitors).title, 'Solicitors');
      expect(empty.ofKind(DirectoryKind.solicitors), isEmpty);

      final withOne = SampleDirectoryRepository.fromJson('''
        {"kinds": [{"kind": "solicitors", "title": "x", "singular": "x", "description": "Law firms."},
                   {"kind": "a-future-kind", "title": "x", "singular": "x", "description": "x"}],
         "tradeOrder": [],
         "profiles": [
           {"slug": "sample-solicitors", "kind": "solicitors", "name": "Sample Solicitors",
            "role": "Conveyancing", "tagline": "t", "about": "a", "city": "Harare",
            "areas": [], "services": ["Conveyancing"], "verified": true},
           {"slug": "x", "kind": "a-future-kind", "name": "x", "role": "", "tagline": "",
            "about": "", "city": "", "areas": [], "services": [], "verified": false}
         ]}''');
      expect(withOne.directories.map((d) => d.kind), [
        DirectoryKind.solicitors,
      ]);
      expect(withOne.info(DirectoryKind.solicitors).singular, 'Solicitor');
      expect(
        withOne.ofKind(DirectoryKind.solicitors).single.name,
        'Sample Solicitors',
      );
    });

    testWidgets('says so plainly when no solicitors are listed yet', (
      tester,
    ) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const DirectoryListScreen(kind: DirectoryKind.solicitors),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitors'), findsOneWidget);
      expect(find.text('No Solicitors listed yet'), findsOneWidget);
    });

    testWidgets('appears in the directory hub', (tester) async {
      final test = TestServices();
      await pumpInApp(
        tester,
        test,
        const DirectoryHubScreen(),
        size: const Size(390, 3200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitors'), findsOneWidget);
      expect(find.text('Real Estate Agencies'), findsOneWidget);
    });
  });

  group('ApiInboxRepository', () {
    test('merges listing and profile enquiries, newest first, with the bearer token', () async {
      final (:api, :requests) = mockApi(
        (request) async => jsonResponse(200, {
          'items': [
            request.url.path.contains('agent')
                ? propertyRequest
                : businessEnquiry,
          ],
        }),
      );
      api.bearerToken = 'token-abc';

      final enquiries = await ApiInboxRepository(api).received();

      expect(requests.map((r) => r.url.path).toSet(), {
        '/v1/agent/property-requests',
        '/v1/inbox/business-enquiries',
      });
      expect(
        requests.every((r) => r.headers['Authorization'] == 'Bearer token-abc'),
        isTrue,
      );
      expect(enquiries.map((e) => e.reference), ['BE-3KQ7M2XT', 'RP-8VXWDQJG']);

      final business = enquiries.first;
      expect(business.subject, 'Conveyancing');
      expect(business.kind, 'To Sample Solicitors');
      expect(business.contactPhone, isNull);
      expect(business.replyBy, 'Email');

      final listing = enquiries.last;
      expect(listing.subject, 'Four-bedroom family home');
      expect(listing.kind, 'Book a viewing');
      expect(listing.listingSlug, 'four-bedroom-family-home-borrowdale');
      expect(listing.contactPhone, '+263771234567');
      expect(listing.replyBy, 'WhatsApp');
      expect(listing.statusLabel, 'New Enquiry');
    });

    test('one closed inbox still shows the other', () async {
      final (:api, requests: _) = mockApi(
        (request) async => request.url.path.contains('agent')
            ? jsonResponse(200, {
                'items': [propertyRequest],
              })
            : forbidden(),
      );
      expect(
        (await ApiInboxRepository(api).received()).single.reference,
        'RP-8VXWDQJG',
      );
    });

    test('an account with no inbox at all is refused', () async {
      final (:api, requests: _) = mockApi((_) async => forbidden());
      await expectLater(
        ApiInboxRepository(api).received(),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 403)),
      );
    });

    test('other failures are not hidden', () async {
      final (:api, requests: _) = mockApi(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        ApiInboxRepository(api).received(),
        throwsA(
          isA<ApiFailure>().having((f) => f.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });
  });

  group('inbox screen', () {
    testWidgets('shows each enquiry with who to reply to', (tester) async {
      final test = TestServices();
      test.inbox.enquiries = [
        ReceivedEnquiry.fromBusinessEnquiry(businessEnquiry),
        ReceivedEnquiry.fromPropertyRequest(propertyRequest),
      ];
      await pumpInApp(
        tester,
        test,
        const InboxScreen(),
        size: const Size(390, 3200),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 enquiries'), findsOneWidget);
      expect(find.text('Conveyancing'), findsOneWidget);
      expect(find.text('Please quote for a transfer.'), findsOneWidget);
      expect(find.text('pat@example.test'), findsOneWidget);
      expect(find.text('Reply by WhatsApp'), findsOneWidget);
      expect(find.text('+263771234567'), findsOneWidget);
      expect(find.text('New Enquiry'), findsNWidgets(2));
      expect(find.text('View listing'), findsOneWidget);
    });

    testWidgets('explains an account that has no inbox', (tester) async {
      final test = TestServices();
      test.inbox.failure = const ApiFailure(
        status: 403,
        code: 'FORBIDDEN',
        message: 'no',
      );
      await pumpInApp(tester, test, const InboxScreen());
      await tester.pumpAndSettle();

      expect(find.text('No enquiries inbox on this account'), findsOneWidget);
    });

    testWidgets('has an empty state', (tester) async {
      final test = TestServices();
      await pumpInApp(tester, test, const InboxScreen());
      await tester.pumpAndSettle();

      expect(find.text('No enquiries yet'), findsOneWidget);
    });

    testWidgets('the account screen offers the inbox to professionals only', (
      tester,
    ) async {
      final professional = TestServices();
      await professional.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, professional, const AccountScreen());
      expect(find.byKey(const Key('open-inbox')), findsOneWidget);
    });
  });
}
