import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/push/push_messaging.dart';
import '../features/activity/activity_store.dart';
import '../features/activity/my_requests_repository.dart';
import '../features/appointments/appointment_repository.dart';
import '../features/inbox/lead_repository.dart';
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
  });

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
