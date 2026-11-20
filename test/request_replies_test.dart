import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/router.dart';
import 'package:rightproperty365/features/activity/my_request_screen.dart';
import 'package:rightproperty365/features/activity/my_requests_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_screen.dart';
import 'package:rightproperty365/features/inbox/lead_screen.dart';
import 'package:rightproperty365/features/notifications/notification_links.dart';

import 'seeker_and_appointments_test.dart' show leadJson, myRequestJson;
import 'support.dart';
import 'work_test.dart' show bodyOf, failure, serve, settle;

Map<String, dynamic> message(
  String id,
  String body, {
  bool professional = true,
  bool mine = false,
  String at = '2030-03-01T10:00:00Z',
}) => {
  'id': id,
  'author': professional ? 'PROFESSIONAL' : 'CUSTOMER',
  'author_name': professional ? 'Harare Homes' : 'Tom Tenant',
  'body': body,
  'created_at': at,
  'mine': mine,
};

Map<String, dynamic> mine({
  List<Map<String, dynamic>> messages = const [],
  bool canReply = false,
  String status = 'RESPONDED',
}) => {
  ...myRequestJson(timeline: true),
  'status': status,
  'status_label': status == 'CLOSED' ? 'Closed' : 'Responded',
  'messages': messages,
  'can_reply': canReply,
};

Map<String, dynamic> lead({
  String stage = 'NEW_ENQUIRY',
  List<Map<String, dynamic>> messages = const [],
  List notes = const [],
}) => {
  ...leadJson(stage: stage, notes: notes),
  'messages': messages,
  'message_count': messages.length,
};

final note = {
  'id': 'n-1',
  'body': 'Owner will drop to 380k',
  'author_name': 'Tendai Ncube',
  'mine': true,
  'created_at': '2030-03-01T09:30:00Z',
};

void main() {
  group('the customer', () {
    testWidgets('before the first reply: told where it will appear', (
      tester,
    ) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/property-requests/req-1': (_) => {'request': mine()},
      });
      await pumpInApp(tester, test, const MyRequestScreen(id: 'req-1'));
      await settle(tester);
      expect(find.text("You'll see the agent's reply here."), findsOneWidget);
      expect(find.byKey(const Key('thread-input')), findsNothing);
    });

    testWidgets('reads the reply and answers back', (tester) async {
      final test = TestServices();
      final thread = [
        message('m-1', 'Thank you, the house is still available.'),
      ];
      serve(test, {
        'GET /v1/me/property-requests/req-1': (_) => {
          'request': mine(messages: thread, canReply: true),
        },
        'POST /v1/me/property-requests/req-1/messages': (request) {
          final m = message(
            'm-2',
            bodyOf(request)['body'] as String,
            professional: false,
            mine: true,
            at: '2030-03-01T11:00:00Z',
          );
          thread.add(m);
          // 0.46: the API answers with the whole request.
          return jsonResponse(201, {
            'request': mine(messages: thread, canReply: true),
          });
        },
      });
      await pumpInApp(tester, test, const MyRequestScreen(id: 'req-1'));
      await settle(tester);
      expect(
        find.text('Thank you, the house is still available.'),
        findsOneWidget,
      );
      expect(find.textContaining('Harare Homes ·'), findsOneWidget);
      // The send button waits for some text.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('thread-send')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('thread-input')),
        '  Can I view it on Saturday?  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-send')));
      await settle(tester);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(bodyOf(post), {'body': 'Can I view it on Saturday?'});
      // Reloaded: the answer shows as the customer's own.
      expect(find.text('Can I view it on Saturday?'), findsOneWidget);
      expect(find.textContaining('You ·'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('thread-input')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('a refused answer shows the API message', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/property-requests/req-1': (_) => {
          'request': mine(messages: [message('m-1', 'Hello')], canReply: true),
        },
        'POST /v1/me/property-requests/req-1/messages': (_) =>
            failure(409, 'REPLY_NOT_OPEN'),
      });
      await pumpInApp(tester, test, const MyRequestScreen(id: 'req-1'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('thread-input')), 'Hi');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-send')));
      await settle(tester);
      expect(find.text('API says REPLY_NOT_OPEN'), findsOneWidget);
      // What was typed is kept.
      expect(find.text('Hi'), findsOneWidget);
    });

    testWidgets('a closed request cannot be answered', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/me/property-requests/req-1': (_) => {
          'request': mine(
            messages: [message('m-1', 'Sorry, it has been let.')],
            status: 'CLOSED',
          ),
        },
      });
      await pumpInApp(tester, test, const MyRequestScreen(id: 'req-1'));
      await settle(tester);
      expect(find.byKey(const Key('thread-blocked')), findsOneWidget);
      expect(find.byKey(const Key('thread-input')), findsNothing);
    });

    testWidgets('a list row says there is a new reply', (tester) async {
      final test = TestServices();
      final row = MyRequest.fromJson({
        ...myRequestJson(),
        'message_count': 1,
        'last_message_at': '2030-03-01T10:00:00Z',
        'unread_reply': true,
      });
      expect(row.messageCount, 1);
      await pumpInApp(
        tester,
        test,
        Scaffold(body: MyRequestCard(row, onTap: () {})),
      );
      expect(find.text('New reply'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('New reply')), findsOneWidget);
    });
  });

  group('the professional', () {
    testWidgets('replies apart from the private notes', (tester) async {
      final test = TestServices();
      var stage = 'NEW_ENQUIRY';
      final thread = <Map<String, dynamic>>[];
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) => {
          'request': lead(stage: stage, messages: thread, notes: [note]),
        },
        'POST /v1/agent/property-requests/req-9/messages': (request) {
          final m = message(
            'm-1',
            bodyOf(request)['body'] as String,
            mine: true,
          );
          thread.add(m);
          stage = 'CONTACTED';
          return jsonResponse(201, {
            'request': lead(stage: stage, messages: thread, notes: [note]),
          });
        },
      });
      await pumpInApp(tester, test, const LeadScreen(requestId: 'req-9'));
      await settle(tester);

      // The note sits in the private section, not in the conversation.
      expect(
        find.descendant(
          of: find.byKey(const Key('lead-private-notes')),
          matching: find.text('Owner will drop to 380k'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('lead-thread')),
          matching: find.text('Owner will drop to 380k'),
        ),
        findsNothing,
      );
      expect(find.text('Private notes'), findsOneWidget);
      expect(find.text('New enquiry'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('thread-input')),
        'Yes, Saturday at 10 works.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-send')));
      await settle(tester);
      // The answer is the updated request: no second fetch.
      expect(test.workRequests.where((r) => r.method == 'GET').length, 1);
      final post = test.workRequests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/v1/agent/property-requests/req-9/messages');
      expect(bodyOf(post), {'body': 'Yes, Saturday at 10 works.'});
      expect(
        find.descendant(
          of: find.byKey(const Key('lead-thread')),
          matching: find.text('Yes, Saturday at 10 works.'),
        ),
        findsOneWidget,
      );
      // The reply moved the new request on.
      expect(find.text('Contacted'), findsOneWidget);
      expect(find.text('Reply sent.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a closed request must be reopened to reply', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) => {
          'request': {...lead(stage: 'CLOSED'), 'can_reply': false},
        },
      });
      await pumpInApp(tester, test, const LeadScreen(requestId: 'req-9'));
      await settle(tester);
      expect(
        find.text('This request is closed. Reopen it to reply.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thread-input')), findsNothing);
    });

    testWidgets('a refused reply shows the API message', (tester) async {
      final test = TestServices();
      serve(test, {
        'GET /v1/agent/property-requests/req-9': (_) => {'request': lead()},
        'POST /v1/agent/property-requests/req-9/messages': (_) =>
            failure(400, 'VALIDATION_FAILED'),
      });
      await pumpInApp(tester, test, const LeadScreen(requestId: 'req-9'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('thread-input')), 'Hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-send')));
      await settle(tester);
      expect(find.text('API says VALIDATION_FAILED'), findsOneWidget);
    });

    testWidgets('the inbox flags requests awaiting a reply', (tester) async {
      final test = TestServices();
      test.inbox.enquiries = [
        ReceivedEnquiry.fromPropertyRequest({
          ...lead(),
          'awaiting_reply': true,
          'message_count': 2,
        }),
      ];
      expect(test.inbox.enquiries.single.awaitingReply, isTrue);
      await pumpInApp(tester, test, const InboxScreen());
      await settle(tester);
      expect(find.text('Awaiting your reply'), findsOneWidget);
    });
  });

  test('reply and update notices open the thread', () async {
    final app = TestServices();
    Future<String?> where(String link) async =>
        switch (await resolveNotificationLink(link, app.services)) {
          InApp(:final location) => location,
          OnWebsite() => null,
        };
    expect(await where('/account/requests/req-1'), Routes.myRequest('req-1'));
    expect(await where('/agent/requests/req-9'), Routes.lead('req-9'));
  });

  testWidgets('both sides hold at 200% text', (tester) async {
    final test = TestServices();
    final thread = [
      message('m-1', 'Thank you, the house is still available.'),
      message('m-2', 'Can I view it?', professional: false, mine: true),
    ];
    serve(test, {
      'GET /v1/me/property-requests/req-1': (_) => {
        'request': mine(messages: thread, canReply: true),
      },
      'GET /v1/agent/property-requests/req-9': (_) => {
        'request': lead(messages: thread, notes: [note]),
      },
    });
    await pumpInApp(
      tester,
      test,
      const MyRequestScreen(id: 'req-1'),
      textScale: 2,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('thread-send'))).height,
      greaterThanOrEqualTo(48),
    );
    await pumpInApp(
      tester,
      test,
      const LeadScreen(requestId: 'req-9'),
      textScale: 2,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
