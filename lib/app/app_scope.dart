import 'package:flutter/widgets.dart';

import '../features/listings/data/listing_repository.dart';
import '../features/property_requests/data/property_request_repository.dart';

/// Hands repositories to the widget tree, so screens depend on interfaces and
/// tests can substitute fakes.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.listings,
    required this.propertyRequests,
    required super.child,
  });

  final ListingRepository listings;
  final PropertyRequestRepository propertyRequests;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      listings != oldWidget.listings ||
      propertyRequests != oldWidget.propertyRequests;
}
