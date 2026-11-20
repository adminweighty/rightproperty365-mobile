import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../contacts/contacts_repository.dart' show ContactBook;
import '../contacts/contacts_screens.dart' show contactBooks;

/// Where a notification's link leads.
sealed class LinkTarget {
  const LinkTarget();
}

/// A screen in the app. [replace] is for the bottom-bar sections, which are
/// gone to rather than pushed.
class InApp extends LinkTarget {
  const InApp(this.location, {this.extra, this.replace = false});

  final String location;
  final Object? extra;
  final bool replace;
}

/// A page the app does not have (listing review, subscription), opened on
/// the website, which checks sign-in and ownership itself.
class OnWebsite extends LinkTarget {
  const OnWebsite(this.url);

  final Uri url;
}

/// Maps a website path (a notification's link, or a link opened from an
/// email or a web page, see [webLinkRedirect]) to the app's own screen, or
/// to the website when the app has no such screen. Anything that is not a relative path opens the
/// notification centre instead: links are never followed off-site.
Future<LinkTarget> resolveNotificationLink(
  String link,
  AppServices services,
) async {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !link.startsWith('/')) {
    return const InApp(Routes.notifications);
  }
  final website = OnWebsite(Uri.parse('${AppConfig.webBaseUrl}$link'));
  final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  String? at(int i) => i < s.length ? s[i] : null;

  Future<List<ContactBook>?> books() async {
    try {
      return contactBooks(await services.workspace.load(), services.auth.user);
    } on ApiFailure {
      return null;
    }
  }

  switch ((at(0), at(1), s.length)) {
    case ('agent', 'requests', 3):
      return InApp(Routes.lead(s[2]));
    case ('agent', 'requests', 2):
      return const InApp(Routes.inbox);
    case ('agent', 'appointments', _):
      return const InApp(Routes.receivedAppointments);
    case ('account', 'appointments', _):
      return const InApp('${Routes.activity}?tab=viewings', replace: true);
    case ('agent', 'applications', final n):
      final all = await books();
      if (all == null) return website;
      if (n == 3) {
        // The link has no organisation: find the one that has it.
        for (final book in all) {
          try {
            await services.agentApplications.get(book.id, s[2]);
            return InApp(Routes.receivedApplication(book.id, s[2]));
          } on ApiFailure catch (failure) {
            if (failure.status != 404 && failure.status != 403) break;
          }
        }
      }
      return InApp(Routes.receivedApplications, extra: all);
    case ('account', 'applications', 3):
      return InApp(Routes.myApplication(s[2]));
    case ('account', 'applications', _):
      return const InApp('${Routes.activity}?tab=applications', replace: true);
    case ('agent', 'venue-bookings', _):
      final all = await books();
      return all == null
          ? website
          : InApp(Routes.hostedVenueBookings, extra: all);
    // Booking emails sent before API 0.39.0 linked /account/hourly-bookings.
    case ('account', 'venue-bookings' || 'hourly-bookings', _):
      return const InApp('${Routes.activity}?tab=bookings', replace: true);
    case ('agent', 'maintenance', 3):
      final all = await books();
      if (all == null) return website;
      // The link has no organisation: find the one that has it.
      for (final book in all) {
        try {
          await services.maintenance.get(book.id, s[2]);
          return InApp(Routes.maintenanceRequest(book.id, s[2]), extra: book);
        } on ApiFailure catch (failure) {
          if (failure.status != 404 && failure.status != 403) break;
        }
      }
      return InApp(Routes.maintenance, extra: all);
    case ('agent', 'maintenance', _):
      final all = await books();
      return all == null ? website : InApp(Routes.maintenance, extra: all);
    case ('account', 'tenancies', _):
      return const InApp('${Routes.activity}?tab=tenancy', replace: true);
    case ('agent', 'reviews', _):
      return const InApp('${Routes.reviews}?tab=received');
    case ('account', 'reviews', _):
      return const InApp(Routes.reviews);
    case ('account', 'notification-preferences', _):
      return const InApp(Routes.notificationPreferences);
    case ('account', 'saved', _):
      return const InApp('${Routes.activity}?tab=saved', replace: true);
    case ('account', 'requests', 3):
      return InApp(Routes.myRequest(s[2]));
    case ('account', 'requests', _):
      return const InApp(Routes.activity, replace: true);
    case ('account', 'signing', _):
      return const InApp(Routes.documentsToSign);
    case ('account', 'signature', _):
      return const InApp(Routes.mySignature);
    case ('account', 'delete', _):
      return const InApp(Routes.deleteAccount);
    // Listing review and expiry notices (API 0.45.0). Creating a listing and
    // its calendar stay on the website.
    case ('agent', 'listings', 2):
      return const InApp(Routes.myListings);
    case ('agent', 'listings', 3) when s[2] != 'new':
      return InApp(Routes.myListing(s[2]));
    // Renewal invoices (API 0.47.0): read-only in the app. The subscription
    // page offers payment, which store billing rules keep out of the app, so
    // its links (invoice issued, subscription active) open the invoices.
    case ('account', 'invoices', 3):
      return InApp(Routes.invoice(s[2]));
    case ('account', 'invoices' || 'subscription' || 'subscriptions', _):
      return const InApp(Routes.invoices);
    case ('agent', 'leases', 3):
      return InApp(Routes.lease(s[2]));
    case ('agent', 'leases', 2):
      return const InApp(Routes.leases);
    case ('agent', 'inspections', 3) when s[2] != 'new':
      final all = await books();
      if (all == null) return website;
      for (final book in all) {
        try {
          await services.inspections.get(book.id, s[2]);
          return InApp(Routes.inspection(book.id, s[2]), extra: book);
        } on ApiFailure catch (failure) {
          if (failure.status != 404 && failure.status != 403) break;
        }
      }
      return InApp(Routes.inspections, extra: all);
    case ('agent', 'inspections', 2):
      final all = await books();
      return all == null ? website : InApp(Routes.inspections, extra: all);
    case ('agent', 'tenancies', 3) when s[2] != 'new':
      final all = await books();
      if (all == null) return website;
      for (final book in all) {
        try {
          await services.properties.tenancy(book.id, s[2]);
          return InApp(Routes.tenancy(book.id, s[2]), extra: book);
        } on ApiFailure catch (failure) {
          if (failure.status != 404 && failure.status != 403) break;
        }
      }
      return website;
    case ('agent', 'properties' || 'tenancies' || 'arrears', 2):
      final all = await books();
      return all == null ? website : InApp(Routes.properties, extra: all);
    case ('agent', 'books', 2):
      final all = await books();
      return all == null ? website : InApp(Routes.books, extra: all);
    case ('agent', 'contacts', 2):
      final all = await books();
      return all == null ? website : InApp(Routes.contacts, extra: all);
    case ('account', 'notifications', _):
      return const InApp(Routes.notifications);
    case ('account', null, _):
      return const InApp(Routes.account, replace: true);
  }
  return website;
}

/// Opens a notification's link: the app's screen, or the website.
Future<void> openNotificationLink(
  GoRouter router,
  AppServices services,
  String link,
) async {
  switch (await resolveNotificationLink(link, services)) {
    case InApp(:final location, :final extra, replace: true):
      router.go(location, extra: extra);
    case InApp(:final location, :final extra):
      router.push(location, extra: extra);
    case OnWebsite(:final url):
      await services.openLink(url);
  }
}
