import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/app/app_scope.dart';
import 'package:rightproperty365/app/theme/app_theme.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/terminology.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/activity/activity_store.dart';
import 'package:rightproperty365/features/activity/my_requests_repository.dart';
import 'package:rightproperty365/features/appointments/appointment_repository.dart';
import 'package:rightproperty365/features/inbox/lead_repository.dart';
import 'package:rightproperty365/features/saved/saved_listings.dart';
import 'package:rightproperty365/features/saved/saved_listings_repository.dart';
import 'package:rightproperty365/features/auth/auth_controller.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/auth/data/token_store.dart';
import 'package:rightproperty365/features/directory/data/business_enquiry_repository.dart';
import 'package:rightproperty365/features/directory/data/directory_repository.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/leases/lease_repository.dart';
import 'package:rightproperty365/features/listings/data/listing_repository.dart';
import 'package:rightproperty365/features/signing/pdf_pages.dart';
import 'package:rightproperty365/features/signing/signing_repository.dart';
import 'package:rightproperty365/features/team/team_repository.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';
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

  /// When true, login asks for an emailed code, as the API does since 0.21.
  /// Most tests only need someone signed in, so the default skips it.
  bool requireCode = false;
  ApiFailure? verifyFailure;
  ApiFailure? resendFailure;
  String? verifiedCode;
  int resends = 0;

  static final challenge = SignInChallenge(
    id: 'challenge-1',
    sentTo: 't•••@example.test',
    expiresAt: DateTime.utc(2030),
    codeLength: 6,
  );

  @override
  Future<SignInStep> login(String email, String password) async {
    if (loginFailure != null) throw loginFailure!;
    if (requireCode) return CodeRequired(challenge);
    return const SignedIn((user: testUser, token: 'token-abc'));
  }

  @override
  Future<({User user, String token})> verifySignInCode(
    String challengeId,
    String code,
  ) async {
    verifiedCode = code;
    if (verifyFailure != null) throw verifyFailure!;
    return (user: testUser, token: 'token-from-code');
  }

  @override
  Future<SignInChallenge> resendSignInCode(String challengeId) async {
    resends++;
    if (resendFailure != null) throw resendFailure!;
    return challenge;
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
    required String captchaId,
    required String captchaAnswer,
  }) async {
    registrations++;
    if (registerFailure != null) throw registerFailure!;
    registered = {
      'name': name,
      'email': email,
      'roles': roles,
      'captcha_id': captchaId,
      'captcha_answer': captchaAnswer,
      'consent': consentAccepted,
    };
  }

  ApiFailure? deleteFailure;
  String? deletedWith;

  @override
  Future<AccountDeletion> deleteAccount(String password) async {
    deletedWith = password;
    if (deleteFailure != null) throw deleteFailure!;
    return const AccountDeletion(organisationsLeft: 1);
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (logoutFailure != null) throw logoutFailure!;
  }

  /// What GET /v1/reference/account_roles answers; null means it fails.
  List<SelectableRole>? selectable = builtInRoles;

  @override
  Future<List<SelectableRole>> selectableRoles() async =>
      selectable ?? (throw const ApiFailure.network());

  ApiFailure? registerFailure;
  int registrations = 0;

  /// Null makes GET /v1/auth/captcha fail.
  String? captchaQuestion = 'What is 7 + 5?';
  int captchasAsked = 0;

  @override
  Future<Captcha> captcha() async {
    if (captchaQuestion == null) throw const ApiFailure.network();
    captchasAsked++;
    return Captcha(
      id: 'captcha-$captchasAsked',
      question: captchaQuestion!,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
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

class FakeInbox implements InboxRepository {
  List<ReceivedEnquiry> enquiries = [];
  ApiFailure? failure;

  @override
  Future<List<ReceivedEnquiry>> received() async {
    if (failure != null) throw failure!;
    return enquiries;
  }
}

/// A PDF without a PDF engine: blank pages of the given sizes.
class FakePdf implements OpenPdf {
  FakePdf(this.pageSizes);

  @override
  final List<ui.Size> pageSizes;
  bool closed = false;

  @override
  Future<ui.Image?> render(int index, int pixelWidth) async => null;

  @override
  Future<void> close() async => closed = true;
}

class FakePdfRenderer implements PdfRenderer {
  List<ui.Size> pages = const [ui.Size(595, 842)];
  final opened = <Uint8List>[];

  @override
  Future<OpenPdf> open(Uint8List bytes) async {
    opened.add(bytes);
    return FakePdf(pages);
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
    saved = SavedListings(
      repository: ApiSavedListingsRepository(workApi),
      auth: auth,
      activity: activity,
      listings: listings,
    );
    services = AppServices(
      saved: saved,
      listings: listings,
      directory: sampleDirectory(),
      propertyRequests: propertyRequests,
      businessEnquiries: businessEnquiries,
      auth: auth,
      activity: activity,
      inbox: inbox,
      workspace: ApiWorkspaceRepository(workApi),
      team: ApiTeamRepository(workApi, newKey: countingKeys()),
      leases: ApiLeaseRepository(workApi),
      signing: ApiSigningRepository(workApi),
      pdf: pdf,
      pickSignatureImage: () async => pickedImage,
      myRequests: ApiMyRequestsRepository(workApi),
      myAppointments: ApiMyAppointmentsRepository(workApi),
      receivedAppointments: ApiReceivedAppointmentsRepository(workApi),
      leads: ApiLeadRepository(workApi),
    );
  }

  /// Answers the work-area calls (dashboard, team, leases, signing); every
  /// request is kept in [workRequests]. Unset paths answer 404.
  Future<http.Response> Function(http.Request request) workHandler =
      (request) async => jsonResponse(404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
      });
  final workRequests = <http.Request>[];
  late final workApi = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient((request) {
      workRequests.add(request);
      return workHandler(request);
    }),
  );
  final pdf = FakePdfRenderer();
  Uint8List? pickedImage;

  final listings = sampleListings();
  late final SavedListings saved;
  final inbox = FakeInbox();
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
