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

/// Maps a notification link (a relative website path, see the API 0.35.0
/// "Links per type") to the app's own screen, or to the website when the
/// app has no such screen. Anything that is not a relative path opens the
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
    case ('account', 'venue-bookings', _):
      return const InApp('${Routes.activity}?tab=bookings', replace: true);
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
