import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, WidgetsBinding;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/language.dart';
import '../features/legal/legal.dart';
import '../features/developments/development.dart';
import '../core/config.dart';
import '../core/location.dart';
import '../core/api/offline.dart';
import '../core/calendar.dart';
import '../core/push/push_messaging.dart';
import '../features/activity/activity_store.dart';
import '../features/analytics/analytics_repository.dart';
import '../features/applications/applications_repository.dart';
import '../features/analytics/analytics_tracker.dart';
import '../features/activity/my_requests_repository.dart';
import '../features/appointments/availability.dart';
import '../features/listings/data/listing_reports.dart';
import '../features/saved/saved_searches.dart';
import '../features/auth/data/account_security.dart';
import '../features/auth/data/data_export.dart';
import '../features/billing/invoices.dart';
import '../features/listings/manage/my_listings.dart';
import '../features/contacts/contacts_repository.dart';
import '../features/appointments/appointment_repository.dart';
import '../features/inbox/lead_repository.dart';
import '../features/ledger/ledger_repository.dart';
import '../features/properties/properties_repository.dart';
import '../features/directory/data/reviews_repository.dart';
import '../features/properties/inspection_repository.dart';
import '../features/properties/maintenance_repository.dart';
import '../features/properties/rent_repository.dart';
import '../features/notifications/marketing_repository.dart';
import '../features/notifications/notification_centre.dart';
import '../features/notifications/notifications_repository.dart';
import '../features/venues/venue_repository.dart';
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
  final connectivity = Connectivity();
  final responseCache = PreferencesResponseCache(
    await SharedPreferences.getInstance(),
  );
  final api = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    cache: responseCache,
    connectivity: connectivity,
  );
  connectivity.probe = api.ping;
  api.userAgent =
      'RightProperty365/${AppConfig.appVersion} '
      '(${defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android'})';
  api.acceptLanguage = () =>
      acceptLanguageHeader(PlatformDispatcher.instance.locales);
  final auth = AuthController(
    repository: ApiAuthRepository(api),
    tokens: const SecureTokenStore(),
    api: api,
  );

  final push = await FirebasePushMessaging.start();
  final preferences = PreferencesStore(await SharedPreferences.getInstance());
  final notifications = NotificationsRepository(api);
  // FR-045: the push token leaves the account with the session (logout
  // carries it) and is deleted on the phone after sign-out.
  final notificationCentre = NotificationCentre(
    repository: notifications,
    auth: auth,
    push: push,
    store: preferences,
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
    appVersion: AppConfig.appVersion,
    locale: () => PlatformDispatcher.instance.locale.toLanguageTag(),
  );
  auth.deviceTokenForSignOut = notificationCentre.tokenForSignOut;
  forgetAtSignOut(auth, () => auth.signedIn, responseCache);

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
    myApplications: MyApplicationsRepository(api),
    agentApplications: AgentApplicationsRepository(api),
    pickApplicationFile: _pickApplicationFile,
    venues: VenueRepository(api),
    ledger: LedgerRepository(api),
    properties: PropertiesRepository(api),
    rent: RentRepository(api),
    maintenance: MaintenanceRepository(api),
    inspections: InspectionRepository(api),
    reviews: ReviewsRepository(api),
    connectivity: connectivity,
    marketing: MarketingRepository(api),
    addToCalendar: PhoneCalendar(
      openLink: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    ).add,
    notifications: notifications,
    notificationCentre: notificationCentre,
    legal: LegalCentre(repository: LegalRepository(api), auth: auth),
    developments: DevelopmentsRepository(api, apiBase: AppConfig.apiBaseUrl),
    analyticsReports: ApiAnalyticsRepository(api),
    mapTiles: AppConfig.mapTiles,
    locate: locateWithGeolocator,
    openLink: (url) => launchUrl(
      url,
      // Our own website opens in a browser tab inside the app: an external
      // open would come straight back to the app through App Links.
      mode: url.host == Uri.parse(AppConfig.webBaseUrl).host
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication,
    ),
    saved: SavedListings(
      repository: ApiSavedListingsRepository(api),
      auth: auth,
      activity: activity,
      listings: listings,
      store: preferences,
      connectivity: connectivity,
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
    myListings: MyListingsRepository(api),
    invoices: InvoicesRepository(api),
    security: AccountSecurityRepository(api),
    availability: AvailabilityRepository(api),
    savedSearches: SavedSearchesRepository(api),
    listingReports: ListingReportsRepository(api),
    dataExport: DataExportRepository(api),
    saveFile: _saveFile,
    myAppointments: ApiMyAppointmentsRepository(api),
    receivedAppointments: ApiReceivedAppointmentsRepository(api),
    leads: ApiLeadRepository(api),
    activity: activity,
  );

  // Not awaited: the app opens straight away and the account area updates
  // when the saved session has been checked.
  auth.restore().whenComplete(notificationCentre.start);
  return services;
}

/// A photo (from the camera, asked for by the system) or a document for an
/// application. Nothing is kept on the phone afterwards.
Future<ChosenFile?> _pickApplicationFile({
  required bool camera,
  required List<String> accept,
}) async {
  if (camera) {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 85,
    );
    if (photo == null) return null;
    return (bytes: await photo.readAsBytes(), name: photo.name);
  }
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [...accept, if (accept.contains('jpg')) 'jpeg'],
  );
  if (files.isEmpty) return null;
  return (bytes: await files.first.readAsBytes(), name: files.first.name);
}

/// The system "save as" screen; false when the person cancelled.
Future<bool> _saveFile({
  required String name,
  required Uint8List bytes,
  required String mimeType,
}) async =>
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: mimeType,
    ) !=
    null;

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
