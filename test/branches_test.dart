import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/branch.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_screen.dart';
import 'package:rightproperty365/features/inbox/lead_screen.dart';
import 'package:rightproperty365/features/ledger/books_screens.dart';
import 'package:rightproperty365/features/ledger/ledger_repository.dart';
import 'package:rightproperty365/features/listings/manage/my_listings.dart';
import 'package:rightproperty365/features/listings/manage/my_listings_screens.dart';
import 'package:rightproperty365/features/team/team_repository.dart';
import 'package:rightproperty365/features/team/team_screen.dart';

import 'ledger_test.dart' show base, book, entryJson;
import 'listing_expiry_test.dart' show managedJson, rowJson;
import 'seeker_and_appointments_test.dart' show leadJson;
import 'support.dart';
import 'work_test.dart' show failure, member, members, serve, settle;

const north = {'id': 'br-1', 'name': 'Harare North'};

void main() {
  group('the models read the branch', () {
    test('an object, free text or nothing', () {
      expect(branchName(north), 'Harare North');
      expect(branchName(' Bulawayo '), 'Bulawayo');
      expect(branchName(null), isNull);
      expect(branchName({'id': 'br-2', 'name': ''}), isNull);
    });

    test('listings, leads, entries and members', () {
      expect(
        MyListing.fromJson({...rowJson('l-1', 'Cottage'), 'branch': north})
            .branch,
        'Harare North',
      );
      expect(MyListing.fromJson(rowJson('l-1', 'Cottage')).branch, isNull);
      expect(
        ManagedListing.fromJson({
          ...managedJson('l-1')['listing'] as Map<String, dynamic>,
          'branch': north,
        }).branch,
        'Harare North',
      );
      expect(
        ReceivedEnquiry.fromPropertyRequest({...leadJson(), 'branch': north})
            .branch,
        'Harare North',
      );
      expect(
        LedgerEntry.fromJson({...entryJson(), 'branch': north}).branch,
        'Harare North',
      );
      // A personal book's entry keeps its free text.
      expect(
        LedgerEntry.fromJson({...entryJson(), 'branch': 'Main office'}).branch,
        'Main office',
      );
      expect(
        TeamMember.fromJson({
          ...member('u-agent', 'Tatenda Dube', 'AGENT'),
          'branch': north,
        }).branch,
        'Harare North',
      );
    });
  });

  group('shown on the screens', () {
    testWidgets('a lead says its branch', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) => {
          'request': {...leadJson(), 'branch': north},
        },
      });
      await pumpInApp(tester, test, const LeadScreen(requestId: 'req-9'));
      await settle(tester);
      expect(find.byKey(const Key('lead-branch')), findsOneWidget);
      expect(find.text('Branch: Harare North'), findsOneWidget);
    });

    testWidgets('the inbox row says its branch', (tester) async {
      final test = TestServices();
      final lead = ReceivedEnquiry.fromPropertyRequest({
        ...leadJson(),
        'branch': north,
      });
      test.inbox.enquiries = [lead];
      await pumpInApp(tester, test, const InboxScreen());
      await settle(tester);
      expect(find.text('Branch: Harare North'), findsOneWidget);
    });

    testWidgets('managed listings say their branch', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings': (_) => {
          'items': [
            {...rowJson('l-1', 'Garden cottage'), 'branch': north},
            rowJson('l-2', 'Town flat'),
          ],
          'total': 2,
        },
        'GET /v1/me/listings/l-1': (_) => {
          'listing': {
            ...managedJson('l-1')['listing'] as Map<String, dynamic>,
            'branch': north,
          },
        },
      });
      await pumpInApp(tester, test, const MyListingsScreen());
      await settle(tester);
      expect(find.byKey(const Key('my-listing-branch-l-1')), findsOneWidget);
      expect(find.byKey(const Key('my-listing-branch-l-2')), findsNothing);
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      expect(find.byKey(const Key('listing-branch')), findsOneWidget);
    });

    testWidgets('a ledger entry says its branch', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET $base/entries/e-1': (_) => {
          'entry': {...entryJson(), 'branch': north},
          'notes': [],
          'attachments': [],
          'related': [],
        },
      });
      await pumpInApp(
        tester,
        test,
        const LedgerEntryScreen(book: book, id: 'e-1'),
      );
      await settle(tester);
      expect(find.text('Branch: Harare North'), findsOneWidget);
    });

    testWidgets('the team says who is pinned to a branch', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/organisations/org-1/members': (_) => {
          ...members,
          'items': [
            for (final m in members['items'] as List)
              (m as Map<String, dynamic>)['user_id'] == 'u-agent'
                  ? {...m, 'branch': north}
                  : m,
          ],
        },
        'GET /v1/agent/organisations/org-1/invitations': (_) => {'items': []},
      });
      await pumpInApp(tester, test, const TeamScreen(organisationId: 'org-1'));
      await settle(tester);
      expect(find.text('Estate Agent · Branch: Harare North'), findsOneWidget);
    });
  });

  group('another branch', () {
    test('the failure is worded plainly everywhere', () async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-9': (_) => failure(403, 'BRANCH_FORBIDDEN'),
      });
      await expectLater(
        test.services.myListings.get('l-9'),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.status, 'status', 403)
              .having((f) => f.message, 'message', branchForbiddenMessage),
        ),
      );
    });

    for (final (name, screen, path) in [
      (
        'a lead',
        const LeadScreen(requestId: 'req-9'),
        'GET /v1/agent/property-requests/req-9',
      ),
      ('a listing', const MyListingScreen(id: 'l-9'), 'GET /v1/me/listings/l-9'),
      (
        'a ledger entry',
        const LedgerEntryScreen(book: book, id: 'e-9'),
        'GET $base/entries/e-9',
      ),
    ]) {
      testWidgets('opening $name says it belongs to another branch', (
        tester,
      ) async {
        final test = TestServices();
        serve(test, {path: (_) => failure(403, 'BRANCH_FORBIDDEN')});
        await pumpInApp(tester, test, screen);
        await settle(tester);
        expect(find.byKey(const Key('branch-forbidden')), findsOneWidget);
        expect(find.text('Another branch'), findsOneWidget);
        expect(find.text(branchForbiddenMessage), findsOneWidget);
        // Trying again would not help.
        expect(find.text('Try again'), findsNothing);
        expect(find.text('We could not load this'), findsNothing);
      });
    }

    testWidgets('an action on a listing moved to another branch', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings/l-1': (_) =>
            managedJson('l-1', actions: const ['pause', 'archive']),
        'POST /v1/me/listings/l-1/pause': (_) =>
            failure(403, 'BRANCH_FORBIDDEN'),
      });
      await pumpInApp(tester, test, const MyListingScreen(id: 'l-1'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-action-pause')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('my-listing-confirm')));
      await settle(tester);
      expect(find.textContaining('another branch'), findsOneWidget);
    });

    testWidgets('a list with every item in other branches is just empty', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/listings': (_) => {'items': [], 'total': 0},
      });
      await pumpInApp(tester, test, const MyListingsScreen());
      await settle(tester);
      expect(find.byKey(const Key('my-listings-empty')), findsOneWidget);
      expect(find.byKey(const Key('my-listings-none')), findsNothing);
    });

    testWidgets('holds at 200% text', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) =>
            failure(403, 'BRANCH_FORBIDDEN'),
      });
      await pumpInApp(
        tester,
        test,
        const LeadScreen(requestId: 'req-9'),
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Another branch'), findsOneWidget);
    });
  });
}
