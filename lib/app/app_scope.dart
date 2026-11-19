import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/location.dart';
import '../core/push/push_messaging.dart';
import '../features/activity/activity_store.dart';
import '../features/analytics/analytics_repository.dart';
import '../features/applications/applications_repository.dart';
import '../features/analytics/analytics_tracker.dart';
import '../features/activity/my_requests_repository.dart';
import '../features/contacts/contacts_repository.dart';
import '../features/appointments/appointment_repository.dart';
import '../features/inbox/lead_repository.dart';
import '../features/ledger/ledger_repository.dart';
import '../features/properties/properties_repository.dart';
import '../features/directory/data/reviews_repository.dart';
import '../features/properties/inspection_repository.dart';
import '../features/properties/maintenance_repository.dart';
import '../features/properties/rent_repository.dart';
import '../features/notifications/notification_centre.dart';
import '../features/notifications/notifications_repository.dart';
import '../features/venues/venue_repository.dart';
import '../features/listings/data/api_listing_repository.dart';
import '../features/listings/data/video_tour.dart';
import '../features/saved/saved_listings.dart';
import '../features/auth/auth_controller.dart';
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

/// Everything screens depend on. Built once at start-up (see bootstrap.dart)
/// and replaced by fakes in tests.
class AppServices {
  const AppServices({
    required this.listings,
    required this.directory,
    required this.propertyRequests,
    required this.businessEnquiries,
    required this.auth,
    required this.activity,
    required this.inbox,
    required this.workspace,
    required this.team,
    required this.leases,
    required this.signing,
    required this.pdf,
    required this.pickSignatureImage,
    required this.myRequests,
    required this.myAppointments,
    required this.receivedAppointments,
    required this.leads,
    this.push = const NoPushMessaging(),
    required this.saved,
    required this.listingDetails,
    required this.openLink,
    required this.listingSearch,
    required this.analytics,
    required this.contacts,
    required this.myApplications,
    required this.agentApplications,
    required this.pickApplicationFile,
    required this.venues,
    required this.ledger,
    required this.properties,
    required this.rent,
    required this.maintenance,
    required this.inspections,
    required this.reviews,
    required this.notifications,
    required this.notificationCentre,
    required this.analyticsReports,
    this.mapTiles,
    this.locate = _noLocation,
  });

  static Future<Located> _noLocation() async =>
      const Located.failed('Location is not available.');

  /// First-party listing statistics: the events this phone sends, and the
  /// reports professionals read.
  final AnalyticsTracker analytics;

  /// The agent CRM: contact books of the person's organisations.
  final ContactsRepository contacts;

  /// Applications: the person's own, and those an organisation received.
  final MyApplicationsRepository myApplications;

  /// Hourly bookings of showrooms and venues.
  final VenueRepository venues;

  /// The organisation's (or direct owner's) own books.
  final LedgerRepository ledger;

  /// Properties, units and tenancies; the tenant's own tenancy.
  final PropertiesRepository properties;

  /// Rent: schedules, receipts, waivers, statements and arrears.
  final RentRepository rent;

  /// Maintenance requests: the manager's and the tenant's.
  final MaintenanceRepository maintenance;

  /// Inspections: the manager's and the tenant's completed reports.
  final InspectionRepository inspections;

  /// Reviews of service providers: published, written, received.
  final ReviewsRepository reviews;

  /// The in-app notification centre and preferences (API 0.35.0).
  final NotificationsRepository notifications;

  /// The unread count, and push on this phone.
  final NotificationCentre notificationCentre;
  final AgentApplicationsRepository agentApplications;

  /// A file for an application, from the camera or the phone's files;
  /// null when the person cancels.
  final Future<ChosenFile?> Function({
    required bool camera,
    required List<String> accept,
  })
  pickApplicationFile;
  final AnalyticsRepository analyticsReports;

  /// Listings from the API, for the map.
  final ApiListingSearch listingSearch;

  /// The map's tile source; null means no map anywhere.
  final MapTiles? mapTiles;

  /// The phone's position, for Near me.
  final Locate locate;

  /// What the public listing adds to the bundled sample listings (the
  /// video tour).
  final ListingDetailsRepository listingDetails;

  /// Opens a link outside the app (the YouTube app, the browser); false
  /// when nothing on the phone can open it.
  final Future<bool> Function(Uri url) openLink;

  /// The signed-in account's saved properties (hearts and the Saved tab).
  final SavedListings saved;

  /// Push messaging on this device; off when the build has no Firebase
  /// project.
  final PushMessaging push;

  /// The signed-in Property Seeker's own requests and viewings.
  final MyRequestsRepository myRequests;
  final MyAppointmentsRepository myAppointments;

  /// The professional side: appointments received and working a request.
  final ReceivedAppointmentsRepository receivedAppointments;
  final LeadRepository leads;

  final WorkspaceRepository workspace;
  final TeamRepository team;
  final LeaseRepository leases;
  final SigningRepository signing;
  final PdfRenderer pdf;

  /// Asks for a picture of a signature from the photo library; null when the
  /// person cancels.
  final Future<Uint8List?> Function() pickSignatureImage;

  final InboxRepository inbox;

  final ActivityStore activity;
  final ListingRepository listings;
  final DirectoryRepository directory;
  final PropertyRequestRepository propertyRequests;
  final BusinessEnquiryRepository businessEnquiries;
  final AuthController auth;
}

/// Hands [AppServices] to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
