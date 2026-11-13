import 'package:flutter/widgets.dart';

import '../features/auth/auth_controller.dart';
import '../features/directory/data/business_enquiry_repository.dart';
import '../features/directory/data/directory_repository.dart';
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
  });

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
