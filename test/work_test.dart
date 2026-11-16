import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/features/auth/presentation/auth_screens.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_screen.dart';
import 'package:rightproperty365/features/leases/lease_form_screen.dart';
import 'package:rightproperty365/features/leases/lease_repository.dart';
import 'package:rightproperty365/features/leases/leases_screen.dart';
import 'package:rightproperty365/features/signing/signing_repository.dart';
import 'package:rightproperty365/features/signing/signing_screen.dart';
import 'package:rightproperty365/features/team/invitation_screen.dart';
import 'package:rightproperty365/features/team/team_repository.dart';
import 'package:rightproperty365/features/team/team_screen.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';

import 'support.dart';

/// Answers `"METHOD /path"` (query left out) from [routes]: a Map or List is
/// sent as JSON 200, an [http.Response] as it is. Anything else is 404.
void serve(
  TestServices test,
  Map<String, Object Function(http.Request request)> routes,
) {
  test.workHandler = (request) async {
    final answer = routes['${request.method} ${request.url.path}'];
    if (answer == null) {
      return jsonResponse(404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
      });
    }
    final value = answer(request);
    return value is http.Response ? value : jsonResponse(200, value);
  };
}

http.Response failure(int status, String code, {Map<String, String>? fields}) =>
    jsonResponse(status, {
      'error': {'code': code, 'message': 'API says $code', 'fields': ?fields},
      'trace_id': 'trace-1',
    });

Map<String, dynamic> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

final dashboard = {
  'organisations': [
    {
      'id': 'org-1',
      'name': 'Sample Estates',
      'kind': 'AGENCY',
      'market_code': 'ZW',
      'role': 'OWNER',
      'role_label': 'Agency Principal',
      'can_see_members': true,
      'can_assign_work': true,
      'can_manage_listings': true,
      'can_manage_team': true,
      'can_create_leases': true,
    },
  ],
  'capabilities': {'creates_leases': true, 'sees_team': true},
  'counters': [
    {'key': 'agreements.waiting_for_you', 'label': 'Waiting', 'value': 2},
  ],
};

Map<String, dynamic> member(
  String id,
  String name,
  String role, {
  bool you = false,
  bool canChange = true,
  bool holdsLeads = true,
  String status = 'ACTIVE',
}) => {
  'user_id': id,
  'name': name,
  'role': role,
  'role_label': teamRoleLabel(role),
  'job_title': null,
  'status': status,
  'status_label': status == 'ACTIVE' ? 'Active' : 'Suspended',
  'market_code': 'ZW',
  'joined_at': '2026-10-01T09:00:00Z',
  'open_leads': 3,
  'is_you': you,
  'can_change': canChange,
  'allowed_roles': canChange ? ['MANAGER', 'AGENT', 'STAFF'] : <String>[],
  'can_hold_leads': holdsLeads,
};

final members = {
  'organisation': {'id': 'org-1', 'name': 'Sample Estates', 'kind': 'AGENCY'},
  'items': [
    member('u-owner', 'Rudo Moyo', 'OWNER', you: true, canChange: false),
    member('u-agent', 'Tatenda Dube', 'AGENT'),
    member('u-staff', 'Farai Chari', 'STAFF', holdsLeads: false),
  ],
};

Map<String, dynamic> invitationJson(String email) => {
  'id': 'inv-1',
  'email': email,
  'role': 'AGENT',
  'role_label': 'Estate Agent',
  'job_title': null,
  'status': 'PENDING',
  'invited_by': {'user_id': 'u-owner', 'name': 'Rudo Moyo'},
  'created_at': '2026-11-15T09:00:00Z',
  'expires_at': '2026-11-22T09:00:00Z',
  'expired': false,
  'can_cancel': true,
};

Map<String, dynamic> leaseJson({String status = 'DRAFT'}) => {
  'id': 'lease-1',
  'reference': 'RPL-2026-000123',
  'status': status,
  'template': {
    'id': 'tpl-1',
    'name': 'Zimbabwe residential lease',
    'version': 2,
    'market_code': 'ZW',
    'lease_kind': 'RESIDENTIAL',
  },
  'organisation': {'id': 'org-1', 'name': 'Sample Estates'},
  'listing': null,
  'created_by': {'user_id': 'u-owner', 'name': 'Rudo Moyo'},
  'property_address': '12 Example Road, Borrowdale, Harare',
  'landlords': [
    {
      'role': 'LANDLORD',
      'name': 'Ann Landlord',
      'email': 'ann@example.test',
      'phone': null,
    },
  ],
  'tenants': [
    {
      'role': 'TENANT',
      'name': 'Tom Tenant',
      'email': 'tom@example.test',
      'phone': null,
    },
  ],
  'start_date': '2027-01-01',
  'end_date': '2027-12-31',
  'periodic': false,
  'rent_amount': '850.00',
  'rent_currency': 'USD',
  'rent_period': 'MONTHLY',
  'payment_day': 1,
  'deposit_amount': '850.00',
  'notice_period_days': 30,
  'optional_clauses': <String>[],
  'special_conditions': null,
  'document': {
    'kind': 'DRAFT',
    'sha256': 'a' * 64,
    'size_bytes': 1000,
    'template_version': 2,
    'generated_at': '2026-11-16T09:00:00Z',
  },
  'signing_copy': null,
  'agreement_id': null,
  'can_edit': status == 'DRAFT',
  'can_send': status == 'DRAFT',
  'can_cancel': status == 'DRAFT' || status == 'SENT_FOR_SIGNING',
  'can_delete': status == 'DRAFT',
  'created_at': '2026-11-16T09:00:00Z',
  'updated_at': '2026-11-16T09:00:00Z',
  'sent_at': null,
  'completed_at': null,
  'declined_at': null,
  'cancelled_at': null,
  'cancel_reason': null,
};

const signingToken = 'tok_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

Map<String, dynamic> field(
  String id,
  String type, {
  int page = 1,
  double y = 700,
  String recipient = 'r-me',
  String? value,
}) => {
  'id': id,
  'recipient_id': recipient,
  'type': type,
  'page': page,
  'x': 72,
  'y': y,
  'w': type == 'INITIALS' ? 60 : 180,
  'h': type == 'INITIALS' ? 30 : 40,
  'required': true,
  'label': null,
  'value': value,
};

Map<String, dynamic> signingView({
  String recipientStatus = 'ACTIVE',
  String status = 'OUT_FOR_SIGNATURE',
  bool canAct = true,
  bool readOnly = false,
}) => {
  'signing': {
    'agreement': {
      'reference': 'RPA-2026-000045',
      'name': 'Lease RPL-2026-000123',
      'message': 'Please sign by Friday.',
      'status': status,
      'sender_name': 'Rudo Moyo',
      'organisation_name': 'Sample Estates',
      'expires_at': '2026-12-16T09:00:00Z',
      'document_sha256': 'b' * 64,
      'final_sha256': null,
      'pages': [
        {'width': 595, 'height': 842},
        {'width': 595, 'height': 842},
      ],
      'completed_at': null,
    },
    'recipient': {
      'id': 'r-me',
      'name': 'Tom Tenant',
      'role': 'SIGNER',
      'label': 'Tenant 1',
      'status': recipientStatus,
      'email_masked': 't•••@example.test',
      'completed_at': recipientStatus == 'SIGNED'
          ? '2026-11-16T10:00:00Z'
          : null,
    },
    'fields': [
      // Out of reading order on purpose: page 2 first.
      field('f-sign', 'SIGNATURE', page: 2, y: 600),
      field('f-init', 'INITIALS', page: 1, y: 780),
      field('f-name', 'NAME', page: 2, y: 650),
      field('f-other', 'SIGNATURE', page: 2, y: 300, recipient: 'r-ann'),
    ],
    'other_recipients': [
      {
        'name': 'Ann Landlord',
        'role': 'SIGNER',
        'order': 1,
        'status': 'ACTIVE',
      },
    ],
    'can_act': canAct,
    'read_only': readOnly,
    'code_length': 6,
    'consent_text': 'I agree to sign electronically.',
    'statement': 'Signed with RightProperty365.',
    'signature_fonts': [
      {'key': 'FLOWING', 'label': 'Flowing (Great Vibes)'},
      {'key': 'BOLD', 'label': 'Bold (Kaushan Script)'},
      {'key': 'CLASSIC', 'label': 'Classic (Allura)'},
    ],
    'link_expires_at': '2026-12-16T09:00:00Z',
  },
};

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('the dashboard', () {
    test('gives the organisations, what each allows and the counters', () {
      final work = Workspace.fromJson(dashboard);
      expect(work.organisations.single.name, 'Sample Estates');
      expect(work.teamsToManage, hasLength(1));
      expect(work.assigningOrganisations, hasLength(1));
      expect(work.createsLeases, isTrue);
      expect(work.documentsWaitingForYou, 2);
      expect(work.organisations.single.invitableRoles, [
        'MANAGER',
        'AGENT',
        'STAFF',
      ]);
    });

    testWidgets('the account screen offers documents, leases and the team', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {'GET /v1/me/dashboard': (_) => dashboard});
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const AccountScreen());
      await settle(tester);

      expect(find.text('2 waiting for your signature'), findsOneWidget);
      expect(find.byKey(const Key('open-signature')), findsOneWidget);
      expect(find.byKey(const Key('open-leases')), findsOneWidget);
      expect(find.text('Team: Sample Estates'), findsOneWidget);
      expect(find.byKey(const Key('open-join-team')), findsOneWidget);
    });

    testWidgets('without the dashboard only the documents are offered', (
      tester,
    ) async {
      final test = TestServices();
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const AccountScreen());
      await settle(tester);

      expect(find.byKey(const Key('open-documents')), findsOneWidget);
      expect(find.byKey(const Key('open-leases')), findsNothing);
      expect(find.textContaining('Team:'), findsNothing);
    });
  });

  group('teams', () {
    test('an invitation token is read from a pasted link', () {
      const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
      expect(
        invitationTokenFrom('https://rightproperty365.com/invitations/$token'),
        token,
      );
      expect(invitationTokenFrom('  $token '), token);
      expect(invitationTokenFrom('not a link'), isNull);
    });

    testWidgets('lists the members with their roles and invites someone', (
      tester,
    ) async {
      final test = TestServices();
      var invitations = <Object>[];
      serve(test, {
        'GET /v1/agent/organisations/org-1/members': (_) => members,
        'GET /v1/agent/organisations/org-1/invitations': (_) => {
          'items': invitations,
        },
        'POST /v1/agent/organisations/org-1/invitations': (request) {
          final sent = invitationJson(bodyOf(request)['email'] as String);
          invitations = [sent];
          return http.Response(
            jsonEncode({'invitation': sent}),
            201,
            headers: {'content-type': 'application/json'},
          );
        },
      });
      await pumpInApp(tester, test, const TeamScreen(organisationId: 'org-1'));
      await settle(tester);

      expect(find.text('Sample Estates'), findsOneWidget);
      expect(find.text('Rudo Moyo (you)'), findsOneWidget);
      expect(find.text('Estate Agent'), findsOneWidget);
      expect(find.text('3 open enquiries'), findsNWidgets(2));
      // The principal cannot be changed; the others can.
      expect(find.byKey(const Key('member-menu-u-owner')), findsNothing);
      expect(find.byKey(const Key('member-menu-u-agent')), findsOneWidget);

      await tester.tap(find.byKey(const Key('team-invite')));
      await settle(tester);
      // An owner may invite administrators, agents and staff.
      expect(find.byKey(const Key('invite-role-MANAGER')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        ' New.Agent@Example.TEST ',
      );
      await tester.tap(find.byKey(const Key('invite-send')));
      await settle(tester);

      final sent = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(sent), {
        'email': 'new.agent@example.test',
        'role': 'AGENT',
      });
      expect(
        find.text('Invitation emailed to new.agent@example.test'),
        findsOneWidget,
      );
      expect(find.text('new.agent@example.test'), findsOneWidget);
    });

    testWidgets('changes a role and shows a refusal in plain words', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/organisations/org-1/members': (_) => members,
        'GET /v1/agent/organisations/org-1/invitations': (_) => {'items': []},
        'PATCH /v1/agent/organisations/org-1/members/u-agent': (_) =>
            failure(403, 'ROLE_NOT_ALLOWED'),
      });
      await pumpInApp(tester, test, const TeamScreen(organisationId: 'org-1'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('member-menu-u-agent')));
      await settle(tester);
      await tester.tap(find.text('Change role'));
      await settle(tester);
      await tester.tap(find.text('Agency Administrator'));
      await settle(tester);

      final patch = test.workRequests.lastWhere((r) => r.method == 'PATCH');
      expect(bodyOf(patch), {'role': 'MANAGER'});
      expect(
        find.textContaining(
          'Only an Agency Principal makes someone an administrator',
        ),
        findsOneWidget,
      );
    });

    testWidgets('someone who is not a manager is told so', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/organisations/org-1/members': (_) =>
            failure(403, 'FORBIDDEN'),
      });
      await pumpInApp(tester, test, const TeamScreen(organisationId: 'org-1'));
      await settle(tester);
      expect(
        find.text(
          'Only the Agency Principal and administrators manage the team',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an invitation is accepted by the signed-in invitee', (
      tester,
    ) async {
      const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
      final test = TestServices();
      serve(test, {
        'GET /v1/invitations/$token': (_) => {
          'invitation': {
            'organisation': {'name': 'Sample Estates', 'kind': 'AGENCY'},
            'role': 'AGENT',
            'role_label': 'Estate Agent',
            'job_title': null,
            'invited_by_name': 'Rudo Moyo',
            'email_masked': 't•••@example.test',
            'expires_at': '2026-11-22T09:00:00Z',
          },
        },
        'POST /v1/invitations/$token/accept': (_) => {
          'organisation': {
            'id': 'org-1',
            'name': 'Sample Estates',
            'kind': 'AGENCY',
          },
          'role': 'AGENT',
          'role_label': 'Estate Agent',
          'profile': null,
        },
      });
      await test.auth.signIn('tendai@example.test', 'pw');
      await pumpInApp(tester, test, const InvitationScreen(token: token));
      await settle(tester);

      expect(
        find.textContaining('Rudo Moyo invites you to join as Estate Agent'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('invitation-accept')));
      await settle(tester);

      final accept = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(accept.body, isEmpty);
      expect(find.text('You joined Sample Estates'), findsOneWidget);
    });

    testWidgets('an invitation sent to another address is explained', (
      tester,
    ) async {
      const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
      final test = TestServices();
      serve(test, {
        'GET /v1/invitations/$token': (_) => failure(410, 'INVITATION_EXPIRED'),
      });
      await pumpInApp(tester, test, const InvitationScreen(token: token));
      await settle(tester);
      expect(
        find.textContaining('This invitation has expired'),
        findsOneWidget,
      );
    });
  });

  group('assigning enquiries', () {
    testWidgets('an Agency Principal gives an enquiry to an agent', (
      tester,
    ) async {
      final test = TestServices();
      test.inbox.enquiries = [
        ReceivedEnquiry.fromPropertyRequest({
          'request_id': 'req-1',
          'reference': 'RQ-ZW-1',
          'listing_id': 'l-1',
          'listing': {
            'slug': 'house',
            'title': 'Family house',
            'reference': 'RP-1',
          },
          'request_type': 'VIEWING',
          'status': 'NEW',
          'stage': 'NEW_ENQUIRY',
          'stage_label': 'New enquiry',
          'message': 'Can I view it on Saturday?',
          'preferred_contact_method': 'EMAIL',
          'contact': {
            'name': 'Sam Seeker',
            'email': 'sam@example.test',
            'phone': null,
          },
          'created_at': '2026-11-16T08:00:00Z',
          'assigned_to': null,
        }),
      ];
      serve(test, {
        'GET /v1/me/dashboard': (_) => dashboard,
        'GET /v1/agent/organisations/org-1/members': (_) => members,
        'POST /v1/agent/property-requests/req-1/assign': (_) => {
          'request': <String, Object>{},
        },
      });
      await pumpInApp(tester, test, const InboxScreen());
      await settle(tester);

      expect(find.text('In the agency inbox'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assign-RQ-ZW-1')));
      await settle(tester);
      // Staff hold no leads, so they are not offered.
      expect(find.byKey(const Key('assign-to-u-staff')), findsNothing);
      await tester.tap(find.byKey(const Key('assign-to-u-agent')));
      await settle(tester);

      final assign = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(assign), {'user_id': 'u-agent'});
      expect(assign.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Assigned to Tatenda Dube'), findsOneWidget);
    });

    testWidgets('an agent sees who has it but cannot assign', (tester) async {
      final test = TestServices();
      test.inbox.enquiries = [
        ReceivedEnquiry.fromPropertyRequest({
          'request_id': 'req-1',
          'reference': 'RQ-ZW-1',
          'listing': {'slug': 'house', 'title': 'Family house'},
          'request_type': 'VIEWING',
          'status': 'NEW',
          'message': 'Hello',
          'preferred_contact_method': 'EMAIL',
          'contact': {'name': 'Sam', 'email': 'sam@example.test'},
          'created_at': '2026-11-16T08:00:00Z',
          'assigned_to': {'user_id': 'u-agent', 'name': 'Tatenda Dube'},
        }),
      ];
      await pumpInApp(tester, test, const InboxScreen());
      await settle(tester);
      expect(find.text('Assigned to Tatenda Dube'), findsOneWidget);
      expect(find.byKey(const Key('assign-RQ-ZW-1')), findsNothing);
    });
  });

  group('leases', () {
    test('a draft sends the create-only keys only when creating', () {
      final draft = LeaseDraft(
        templateId: 'tpl-1',
        organisationId: 'org-1',
        propertyAddress: ' 12 Example Road ',
        landlords: const [LeaseParty(name: 'Ann', email: 'ann@example.test')],
        tenants: const [
          LeaseParty(
            name: 'Tom',
            email: 'tom@example.test',
            phone: '+263 77 000 0000',
          ),
        ],
        startDate: DateTime(2027, 1, 1),
        endDate: DateTime(2027, 12, 31),
        periodic: true,
        rentAmount: '850',
        rentCurrency: 'usd',
        rentPeriod: 'MONTHLY',
        paymentDay: 1,
        noticePeriodDays: 30,
      );
      final created = draft.toJson(creating: true);
      expect(created['organisation_id'], 'org-1');
      expect(created['property_address'], '12 Example Road');
      expect(created['rent_currency'], 'USD');
      expect(created['start_date'], '2027-01-01');
      // Periodic: no end date.
      expect(created.containsKey('end_date'), isFalse);
      expect((created['tenants'] as List).single, {
        'name': 'Tom',
        'email': 'tom@example.test',
        'phone': '+263 77 000 0000',
      });
      expect(
        draft.toJson(creating: false).containsKey('organisation_id'),
        isFalse,
      );
    });

    test('a lease is read with its parties and what can be done', () {
      final lease = Lease.fromJson(leaseJson());
      expect(lease.statusLabel, 'Draft');
      expect(lease.tenants.single.name, 'Tom Tenant');
      expect(lease.canSend, isTrue);
      expect(lease.paymentDayLabel, 'Day 1');
      expect(lease.hasDocument, isTrue);
    });

    testWidgets('the list shows each lease and its status', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/leases': (_) => {
          'items': [
            leaseJson(),
            {...leaseJson(status: 'SIGNED'), 'id': 'lease-2'},
          ],
          'page': 1,
          'page_size': 100,
          'total': 2,
          'total_pages': 1,
        },
      });
      await pumpInApp(tester, test, const LeasesScreen());
      await settle(tester);
      expect(
        find.text('12 Example Road, Borrowdale, Harare'),
        findsNWidgets(2),
      );
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Signed'), findsWidgets);
      expect(find.text('Tenants: Tom Tenant'), findsNWidgets(2));
    });

    testWidgets('a draft is sent for signing', (tester) async {
      final test = TestServices();
      var status = 'DRAFT';
      serve(test, {
        'GET /v1/me/leases/lease-1': (_) => {
          'lease': leaseJson(status: status),
        },
        'GET /v1/me/leases/lease-1/events': (_) => {
          'items': [
            {
              'id': 'e1',
              'action': 'CREATED',
              'actor': {'type': 'USER', 'user_id': 'u', 'name': 'Rudo Moyo'},
              'detail': <String, Object>{},
              'at': '2026-11-16T09:00:00Z',
            },
          ],
        },
        'POST /v1/me/leases/lease-1/send': (_) {
          status = 'SENT_FOR_SIGNING';
          return {'lease': leaseJson(status: status)};
        },
      });
      await pumpInApp(tester, test, const LeaseDetailScreen(id: 'lease-1'));
      await settle(tester);

      expect(find.textContaining('Created · Rudo Moyo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lease-send')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('lease-send-confirm')));
      await settle(tester);

      final send = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(send), {'reminder_frequency': 'EVERY_3_DAYS'});
      expect(find.text('Out for signing'), findsOneWidget);
      expect(find.byKey(const Key('lease-send')), findsNothing);
    });

    testWidgets('the draft PDF opens in the app', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/leases/lease-1': (_) => {'lease': leaseJson()},
        'GET /v1/me/leases/lease-1/events': (_) => {'items': []},
        'GET /v1/me/leases/lease-1/pdf': (_) =>
            http.Response.bytes([37, 80, 68, 70], 200),
      });
      test.pdf.pages = const [Size(595, 842), Size(595, 842)];
      await pumpInApp(tester, test, const LeaseDetailScreen(id: 'lease-1'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('lease-pdf')));
      await settle(tester);

      expect(test.pdf.opened.single, Uint8List.fromList([37, 80, 68, 70]));
      expect(find.bySemanticsLabel(RegExp('page 2 of 2')), findsOneWidget);
    });

    testWidgets('a new lease is drafted from a template', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/lease-templates': (_) => {
          'items': [
            {
              'id': 'tpl-1',
              'family_id': 'tpl-1',
              'version': 2,
              'market_code': 'ZW',
              'name': 'Zimbabwe residential lease',
              'lease_kind': 'RESIDENTIAL',
              'description': null,
              'sections': [],
              'optional_clauses': [
                {
                  'code': 'PETS',
                  'title': 'Pets allowed',
                  'text': 'The tenant may keep a pet.',
                },
              ],
              'status': 'APPROVED',
              'legal_review': null,
            },
          ],
          'variables': [],
        },
        'GET /v1/me/listings': (_) => failure(403, 'FORBIDDEN'),
        'GET /v1/me/dashboard': (_) => dashboard,
        'POST /v1/me/leases': (_) => http.Response(
          jsonEncode({'lease': leaseJson()}),
          201,
          headers: {'content-type': 'application/json'},
        ),
      });
      await pumpInApp(tester, test, const LeaseFormScreen());
      await settle(tester);

      await tester.tap(find.byKey(const Key('lease-template')));
      await settle(tester);
      await tester.tap(find.text('Zimbabwe residential lease (v2)'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('lease-address')),
        '12 Example Road',
      );
      await tester.enterText(
        find.byKey(const Key('landlords-0-name')),
        'Ann Landlord',
      );
      await tester.enterText(
        find.byKey(const Key('landlords-0-email')),
        'ann@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('tenants-0-name')),
        'Tom Tenant',
      );
      await tester.enterText(
        find.byKey(const Key('tenants-0-email')),
        'tom@example.test',
      );
      await tester.enterText(find.byKey(const Key('lease-rent')), '850');
      await tester.tap(find.text('Pets allowed'));
      await tester.tap(find.byKey(const Key('lease-periodic')));
      await tester.tap(find.byKey(const Key('lease-start')));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('lease-save')));
      await settle(tester);

      final create = test.workRequests.lastWhere((r) => r.method == 'POST');
      final body = bodyOf(create);
      expect(body['template_id'], 'tpl-1');
      expect(body['property_address'], '12 Example Road');
      expect(body['periodic'], isTrue);
      expect(body.containsKey('end_date'), isFalse);
      expect(body['optional_clauses'], ['PETS']);
      expect(body['notice_period_days'], 30);
      // One organisation: the API picks it, nothing to send.
      expect(body.containsKey('organisation_id'), isFalse);
    });

    testWidgets('missing parties are caught before anything is sent', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/lease-templates': (_) => {
          'items': [
            {
              'id': 'tpl-1',
              'version': 1,
              'market_code': 'ZW',
              'name': 'Lease',
              'lease_kind': 'RESIDENTIAL',
              'optional_clauses': [],
            },
          ],
        },
        'GET /v1/me/listings': (_) => {'items': []},
      });
      await pumpInApp(tester, test, const LeaseFormScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('lease-save')));
      await settle(tester);

      expect(
        find.text('Choose the template the lease is made from'),
        findsOneWidget,
      );
      expect(find.text('Enter their full name'), findsNWidgets(2));
      expect(test.workRequests.where((r) => r.method == 'POST'), isEmpty);
    });
  });

  group('signing', () {
    test('a typed signature and a drawing are sent as the API expects', () {
      expect(
        const AdoptedSignature.typed('Tom Tenant', font: 'BOLD').toJson(),
        {'kind': 'TYPED', 'text': 'Tom Tenant', 'font': 'BOLD'},
      );
      final drawn = AdoptedSignature.image(
        SignatureKind.drawn,
        Uint8List.fromList([1, 2, 3]),
      ).toJson();
      expect(drawn, {'kind': 'DRAWN', 'image_base64': 'AQID'});
      final saved = AdoptedSignature.fromSaved({
        'kind': 'UPLOADED',
        'text': null,
        'font': null,
        'image_base64': 'data:image/png;base64,AQID',
      });
      expect(saved.kind, SignatureKind.uploaded);
      expect(saved.image, [1, 2, 3]);
    });

    test("the signer's fields are visited page by page, top to bottom", () {
      final view = SigningView.fromJson(
        signingView()['signing'] as Map<String, dynamic>,
      );
      expect([for (final f in view.mine) f.id], ['f-init', 'f-sign', 'f-name']);
      expect(view.signingNow, isTrue);
    });

    testWidgets('Start, adopt, code, consent, then Click to sign', (
      tester,
    ) async {
      final test = TestServices();
      var signed = false;
      serve(test, {
        'GET /v1/signing/$signingToken': (_) => signed
            ? signingView(
                recipientStatus: 'SIGNED',
                canAct: false,
                readOnly: true,
              )
            : signingView(),
        'GET /v1/signing/$signingToken/pdf': (_) =>
            http.Response.bytes([37, 80, 68, 70], 200),
        'POST /v1/signing/$signingToken/code': (_) => {
          'sent_to': 't•••@example.test',
          'expires_at': '2026-11-16T10:10:00Z',
          'code_length': 6,
        },
        'POST /v1/signing/$signingToken/submit': (request) {
          signed = true;
          return {
            'recipient_status': 'SIGNED',
            'agreement_status': 'OUT_FOR_SIGNATURE',
            'completed_at': null,
          };
        },
      });
      test.pdf.pages = const [Size(595, 842), Size(595, 842)];
      await pumpInApp(
        tester,
        test,
        const SigningScreen(token: signingToken),
        size: const Size(390, 900),
      );
      await settle(tester);

      expect(find.text('Start · 0 of 2 required fields'), findsOneWidget);
      // Start goes to the initials on page 1 (the first in reading order).
      await tester.tap(find.byKey(const Key('signing-next')));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Initial here (required)'));
      await settle(tester);
      expect(find.text('Adopt your initials'), findsOneWidget);
      expect(
        find.byKey(const Key('adopt-save')),
        findsNothing,
      ); // Not signed in.
      await tester.enterText(find.byKey(const Key('adopt-typed')), 'TT');
      await tester.tap(find.byKey(const Key('adopt-confirm')));
      await settle(tester);
      expect(find.text('Next · 1 of 2 required fields'), findsOneWidget);

      await tester.tap(find.byKey(const Key('signing-next')));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Sign here (required)'));
      await settle(tester);
      await tester.tap(find.text('Draw'));
      await settle(tester);
      // A stroke with some downward movement, in small steps like a finger.
      final stroke = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('adopt-pad'))) -
            const Offset(60, 10),
      );
      for (var i = 0; i < 12; i++) {
        await stroke.moveBy(const Offset(10, 4));
      }
      await stroke.up();
      await tester.pump();
      // The drawing is encoded as a PNG for real, outside the fake clock:
      // let real time pass until the sheet closes.
      await tester.tap(find.byKey(const Key('adopt-confirm')));
      for (
        var i = 0;
        i < 100 && find.text('Adopt your signature').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await settle(tester);
      expect(find.text('Finish · 2 of 2 required fields'), findsOneWidget);

      // Signing without the code is stopped.
      await tester.tap(find.byKey(const Key('signing-next')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('signing-submit')));
      await settle(tester);
      expect(find.text('Send yourself the code first.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('signing-send-code')));
      await settle(tester);
      expect(
        find.textContaining('We sent a 6-digit code to t•••@example.test'),
        findsOneWidget,
      );
      expect(find.text('Send a new code in 30 s'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('signing-code')), '123456');
      await tester.tap(find.byKey(const Key('signing-submit')));
      await settle(tester);
      expect(
        find.text('Tick the box to agree to sign electronically.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('signing-consent')));
      await tester.tap(find.byKey(const Key('signing-submit')));
      await settle(tester);

      final submit = test.workRequests.lastWhere(
        (r) => r.url.path.endsWith('/submit'),
      );
      final body = bodyOf(submit);
      expect(body['code'], '123456');
      expect(body['consent'], isTrue);
      expect(body['initials'], {
        'kind': 'TYPED',
        'text': 'TT',
        'font': 'FLOWING',
      });
      expect((body['signature'] as Map)['kind'], 'DRAWN');
      expect(
        base64Decode((body['signature'] as Map)['image_base64'] as String)
            .take(4),
        [0x89, 0x50, 0x4E, 0x47], // A PNG.
      );
      expect(find.text('You signed it'), findsOneWidget);
      // Let the resend countdown run out.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a wrong code is said plainly and can be tried again', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/signing/$signingToken': (_) => {
          'signing': {
            ...(signingView()['signing'] as Map<String, dynamic>),
            'fields': <Object>[],
          },
        },
        'GET /v1/signing/$signingToken/pdf': (_) =>
            http.Response.bytes([1], 200),
        'POST /v1/signing/$signingToken/code': (_) => {
          'sent_to': 't•••@example.test',
          'expires_at': '2026-11-16T10:10:00Z',
          'code_length': 6,
        },
        'POST /v1/signing/$signingToken/submit': (_) => failure(
          400,
          'VALIDATION_FAILED',
          fields: {'code': 'The code is not right.'},
        ),
      });
      await pumpInApp(tester, test, const SigningScreen(token: signingToken));
      await settle(tester);

      await tester.tap(find.byKey(const Key('signing-send-code')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('signing-code')), '000000');
      await tester.tap(find.byKey(const Key('signing-consent')));
      await tester.tap(find.byKey(const Key('signing-submit')));
      await settle(tester);

      expect(
        find.text('That code is not right. Check the email and try again.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a signer can decline with a reason', (tester) async {
      final test = TestServices();
      var declined = false;
      serve(test, {
        'GET /v1/signing/$signingToken': (_) => declined
            ? signingView(
                recipientStatus: 'DECLINED',
                status: 'DECLINED',
                canAct: false,
              )
            : signingView(),
        'GET /v1/signing/$signingToken/pdf': (_) =>
            http.Response.bytes([1], 200),
        'POST /v1/signing/$signingToken/decline': (request) {
          declined = true;
          return signingView(
            recipientStatus: 'DECLINED',
            status: 'DECLINED',
            canAct: false,
          );
        },
      });
      await pumpInApp(tester, test, const SigningScreen(token: signingToken));
      await settle(tester);

      await tester.tap(find.byKey(const Key('signing-more')));
      await settle(tester);
      await tester.tap(find.text('Decline to sign'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('decline-confirm')));
      await settle(tester);
      expect(
        find.textContaining('Write why you are declining'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('decline-reason')),
        'Wrong rent',
      );
      await tester.tap(find.byKey(const Key('decline-confirm')));
      await settle(tester);

      final decline = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(decline), {'reason': 'Wrong rent'});
      expect(find.text('You declined this document'), findsOneWidget);
    });

    testWidgets(
      "someone whose turn has not come reads it and is told who's next",
      (tester) async {
        final test = TestServices();
        serve(test, {
          'GET /v1/signing/$signingToken': (_) => signingView(
            recipientStatus: 'WAITING',
            canAct: false,
            readOnly: true,
          ),
          'GET /v1/signing/$signingToken/pdf': (_) =>
              http.Response.bytes([1], 200),
        });
        await pumpInApp(tester, test, const SigningScreen(token: signingToken));
        await settle(tester);
        expect(find.text('It is not your turn yet'), findsOneWidget);
        expect(
          find.textContaining('Ann Landlord must sign first'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the signing screen and the team hold at 200% text size', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/signing/$signingToken': (_) => signingView(),
        'GET /v1/signing/$signingToken/pdf': (_) =>
            http.Response.bytes([1], 200),
        'GET /v1/agent/organisations/org-1/members': (_) => members,
        'GET /v1/agent/organisations/org-1/invitations': (_) => {
          'items': [invitationJson('someone.with.a.long.address@example.test')],
        },
      });
      await pumpInApp(
        tester,
        test,
        const SigningScreen(token: signingToken),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('signing-next')));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Initial here (required)'));
      await settle(tester);
      expect(find.text('Adopt your initials'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpInApp(
        tester,
        test,
        const TeamScreen(organisationId: 'org-1'),
        textScale: 2,
        size: const Size(390, 844),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an expired link says so', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/signing/$signingToken': (_) =>
            failure(410, 'SIGNING_LINK_EXPIRED'),
      });
      await pumpInApp(tester, test, const SigningScreen(token: signingToken));
      await settle(tester);
      expect(find.text('This signing link has expired'), findsOneWidget);
    });
  });
}
