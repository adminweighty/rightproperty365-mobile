import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../features/activity/activity_store.dart';
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
  });

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
