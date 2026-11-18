import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, WidgetsBinding;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../core/location.dart';
import '../core/push/push_messaging.dart';
import '../features/activity/activity_store.dart';
import '../features/analytics/analytics_repository.dart';
import '../features/analytics/analytics_tracker.dart';
import '../features/activity/my_requests_repository.dart';
import '../features/contacts/contacts_repository.dart';
import '../features/appointments/appointment_repository.dart';
import '../features/inbox/lead_repository.dart';
import '../features/listings/data/api_listing_repository.dart';
import '../features/listings/data/video_tour.dart';
import '../features/saved/saved_listings.dart';
import '../features/saved/saved_listings_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/token_store.dart';
import '../features/directory/data/business_enquiry_repository.dart';
import '../features/directory/data/directory_repository.dart';
import '../features/inbox/inbox_repository.dart';
import '../features/leases/lease_repository.dart';
import '../features/signing/pdf_pages.dart';
import '../features/signing/signing_repository.dart';
import '../features/team/team_repository.dart';
import '../features/workspace/workspace.dart';
import '../features/listings/data/listing_repository.dart';
import '../features/property_requests/data/property_request_repository.dart';
import 'app_scope.dart';

// Kept for the life of the app.
// ignore: unused_element
AppLifecycleListener? _lifecycle;

/// Builds the production services: sample listings and directory from bundled
/// JSON, and the Go API for enquiries and identity.
Future<AppServices> bootstrap({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final auth = AuthController(
    repository: ApiAuthRepository(api),
    tokens: const SecureTokenStore(),
    api: api,
  );

  final push = await FirebasePushMessaging.start();
  // FR-045: nothing tied to the account stays on the phone after sign-out,
  // the push token included.
  auth.addListener(() {
    if (!auth.signedIn) push.deleteToken();
  });

  final preferences = PreferencesStore(await SharedPreferences.getInstance());
  final activity = ActivityStore(preferences);
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final analytics = AnalyticsTracker(
    api,
    store: preferences,
    device:
        view != null &&
            view.physicalSize.shortestSide / view.devicePixelRatio >= 600
        ? 'tablet'
        : 'mobile',
  );
  // What is waiting goes out when the app leaves the screen.
  _lifecycle = AppLifecycleListener(
    onInactive: analytics.flush,
    onHide: analytics.flush,
  );
  final listingSearch = ApiListingSearch(api, apiBase: AppConfig.apiBaseUrl);
  // Browsing stays on the bundled sample; a listing it does not have (one
  // opened from the map) comes from the API.
  final listings = SampleThenApiListingRepository(
    SampleListingRepository.fromJson(
      await assets.loadString('assets/data/listings.json'),
    ),
    listingSearch,
  );

  final services = AppServices(
    push: push,
    listingDetails: ApiListingDetailsRepository(api),
    listingSearch: listingSearch,
    analytics: analytics,
    contacts: ContactsRepository(api),
    analyticsReports: ApiAnalyticsRepository(api),
    mapTiles: AppConfig.mapTiles,
    locate: locateWithGeolocator,
    openLink: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    saved: SavedListings(
      repository: ApiSavedListingsRepository(api),
      auth: auth,
      activity: activity,
      listings: listings,
    ),
    listings: listings,
    directory: SampleDirectoryRepository.fromJson(
      await assets.loadString('assets/data/directory.json'),
    ),
    propertyRequests: ApiPropertyRequestRepository(api),
    businessEnquiries: ApiBusinessEnquiryRepository(api),
    auth: auth,
    inbox: ApiInboxRepository(api),
    workspace: ApiWorkspaceRepository(api),
    team: ApiTeamRepository(api),
    leases: ApiLeaseRepository(api),
    signing: ApiSigningRepository(api),
    pdf: const PlatformPdfRenderer(),
    pickSignatureImage: _pickSignatureImage,
    myRequests: ApiMyRequestsRepository(api),
    myAppointments: ApiMyAppointmentsRepository(api),
    receivedAppointments: ApiReceivedAppointmentsRepository(api),
    leads: ApiLeadRepository(api),
    activity: activity,
  );

  // Not awaited: the app opens straight away and the account area updates
  // when the saved session has been checked.
  auth.restore();
  return services;
}

/// A photo of a signature, shrunk to the API's 2000 x 1000 pixel limit.
Future<Uint8List?> _pickSignatureImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    maxHeight: 1000,
    imageQuality: 85,
  );
  return file?.readAsBytes();
}
