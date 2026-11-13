import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/app_scope.dart';
import 'package:rightproperty365/app/theme/app_theme.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/activity/activity_store.dart';
import 'package:rightproperty365/features/auth/auth_controller.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/data/token_store.dart';
import 'package:rightproperty365/features/directory/data/business_enquiry_repository.dart';
import 'package:rightproperty365/features/directory/data/directory_repository.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/listings/data/listing_repository.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';

/// The bundled sample data, read straight from the asset files.
SampleListingRepository sampleListings() => SampleListingRepository.fromJson(
  File('assets/data/listings.json').readAsStringSync(),
);

SampleDirectoryRepository sampleDirectory() =>
    SampleDirectoryRepository.fromJson(
      File('assets/data/directory.json').readAsStringSync(),
    );

http.Response jsonResponse(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// An [ApiClient] whose calls are answered by [handler]; every request is
/// recorded in `requests`.
({ApiClient api, List<http.Request> requests}) mockApi(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final client = MockClient((request) {
    requests.add(request);
    return handler(request);
  });
  return (
    api: ApiClient(baseUrl: 'http://api.test/', httpClient: client),
    requests: requests,
  );
}

/// Predictable idempotency keys: key-1-padding, key-2-padding, ...
String Function() countingKeys() {
  var count = 0;
  return () => 'key-${++count}-padding';
}

final testReceipt = EnquiryReceipt(
  id: 'id',
  reference: 'RP-8VXWDQJG',
  status: 'RECEIVED',
  createdAt: DateTime.utc(2026, 11, 13),
);

class FakePropertyRequests implements PropertyRequestRepository {
  final drafts = <PropertyRequestDraft>[];
  ApiFailure? failure;

  @override
  Future<EnquiryReceipt> submit(PropertyRequestDraft draft) async {
    drafts.add(draft);
    if (failure != null) throw failure!;
    return testReceipt;
  }
}

class FakeBusinessEnquiries implements BusinessEnquiryRepository {
  final drafts = <BusinessEnquiryDraft>[];
  ApiFailure? failure;

  @override
  Future<EnquiryReceipt> submit(BusinessEnquiryDraft draft) async {
    drafts.add(draft);
    if (failure != null) throw failure!;
    return testReceipt;
  }
}

const testUser = User(
  id: 'user-1',
  name: 'Tendai Ncube',
  email: 'tendai@example.test',
  emailVerified: true,
  accountRoles: [
    AccountRole('CONSUMER', 'ACTIVE'),
    AccountRole('AGENT', 'PENDING_VERIFICATION'),
  ],
  memberships: [
    Membership(
      organisationName: 'Sample Estates',
      organisationKind: 'AGENCY',
      marketCode: 'ZW',
      role: 'AGENT',
    ),
  ],
);

class FakeAuthRepository implements AuthRepository {
  ApiFailure? loginFailure;
  ApiFailure? meFailure;
  ApiFailure? logoutFailure;
  Map<String, Object?>? registered;
  int logouts = 0;

  @override
  Future<({User user, String token})> login(
    String email,
    String password,
  ) async {
    if (loginFailure != null) throw loginFailure!;
    return (user: testUser, token: 'token-abc');
  }

  @override
  Future<User> me() async {
    if (meFailure != null) throw meFailure!;
    return testUser;
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required List<String> roles,
    required bool consentAccepted,
    required String privacyVersion,
  }) async {
    registered = {
      'name': name,
      'email': email,
      'roles': roles,
      'consent': consentAccepted,
    };
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (logoutFailure != null) throw logoutFailure!;
  }

  ApiFailure? linkFailure;
  String? verifiedToken;
  String? resentTo;
  String? resetRequestedFor;
  ({String token, String password})? passwordReset;

  @override
  Future<({User user, String token})> verifyEmail(String token) async {
    verifiedToken = token;
    if (linkFailure != null) throw linkFailure!;
    return (user: testUser, token: 'token-verified');
  }

  @override
  Future<void> resendVerification(String email) async => resentTo = email;

  @override
  Future<void> requestPasswordReset(String email) async =>
      resetRequestedFor = email;

  @override
  Future<void> confirmPasswordReset(String token, String password) async {
    if (linkFailure != null) throw linkFailure!;
    passwordReset = (token: token, password: password);
  }
}

/// Services wired with fakes for widget tests.
class TestServices {
  TestServices({MemoryTokenStore? tokens})
    : tokens = tokens ?? MemoryTokenStore(),
      api = ApiClient(baseUrl: 'http://api.test') {
    auth = AuthController(
      repository: authRepository,
      tokens: this.tokens,
      api: api,
    );
    services = AppServices(
      listings: sampleListings(),
      directory: sampleDirectory(),
      propertyRequests: propertyRequests,
      businessEnquiries: businessEnquiries,
      auth: auth,
      activity: activity,
    );
  }

  final storage = MemoryStore();
  late final activity = ActivityStore(storage);

  final MemoryTokenStore tokens;
  final ApiClient api;
  final propertyRequests = FakePropertyRequests();
  final businessEnquiries = FakeBusinessEnquiries();
  final authRepository = FakeAuthRepository();
  late final AuthController auth;
  late final AppServices services;
}

/// The whole app on [router], wired like the real one but with fakes and
/// reduced motion (so the rotating home hero does not keep tests waiting).
Widget appWith(TestServices test, GoRouter router) => AppScope(
  services: test.services,
  child: MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: app!,
    ),
  ),
);

/// Pumps [child] inside the app theme and scope on a phone-sized surface that
/// is tall enough for every field of a form to be built.
Future<void> pumpInApp(
  WidgetTester tester,
  TestServices test,
  Widget child, {
  double textScale = 1,
  Size size = const Size(390, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      services: test.services,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            // Reduced motion: no rotating hero or entrance animations, so
            // tests settle and exercise the accessible path.
            disableAnimations: true,
          ),
          child: app!,
        ),
        home: child,
      ),
    ),
  );
}
