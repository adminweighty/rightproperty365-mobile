import 'package:go_router/go_router.dart';

import '../features/activity/activity_screen.dart';
import '../features/activity/my_request_screen.dart';
import '../features/analytics/statistics_screen.dart';
import '../features/ledger/books_screens.dart';
import '../features/notifications/link_opener.dart';
import '../features/notifications/notifications_screens.dart';
import '../features/properties/properties_repository.dart';
import '../features/properties/properties_screens.dart';
import '../features/properties/maintenance_screens.dart';
import '../features/properties/inspection_screens.dart';
import '../features/directory/presentation/reviews_widgets.dart';
import '../features/ledger/ledger_repository.dart';
import '../features/venues/venue_screens.dart';
import '../features/applications/apply_screen.dart';
import '../features/applications/received_applications.dart';
import '../features/contacts/contacts_repository.dart';
import '../features/contacts/contacts_screens.dart';
import '../features/workspace/workspace.dart';
import '../features/appointments/appointment_screens.dart';
import '../features/auth/presentation/delete_account_screen.dart';
import '../features/inbox/lead_screen.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/auth/presentation/recovery_screens.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/directory/data/profile.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/leases/lease_form_screen.dart';
import '../features/leases/leases_screen.dart';
import '../features/signing/documents_screen.dart';
import '../features/signing/signing_screen.dart';
import '../features/team/invitation_screen.dart';
import '../features/team/team_screen.dart';
import '../features/directory/presentation/directory_screens.dart';
import '../features/directory/presentation/profile_screen.dart';
import '../features/listings/data/listing.dart';
import '../features/listings/presentation/home_screen.dart';
import '../features/listings/presentation/listing_detail_screen.dart';
import '../features/listings/presentation/search_screen.dart';
import '../features/property_requests/presentation/property_request_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/legal/legal_screens.dart';
import '../features/developments/development_screens.dart';

/// Route locations. Build them here so paths are written in one place.
abstract final class Routes {
  static const home = '/';
  static const directory = '/directory';
  static const activity = '/activity';
  static const account = '/account';
  static const signIn = '/sign-in';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const inbox = '/inbox';
  static const leases = '/leases';
  static const newLease = '/leases/new';
  static const documentsToSign = '/signing';
  static const mySignature = '/signature';
  static const joinTeam = '/invitations';
  static const accountManagement = '/account-management';
  static const deleteAccount = '/account-management/delete';
  static const receivedAppointments = '/appointments';
  static const statistics = '/statistics';
  static const contacts = '/contacts';
  static const receivedApplications = '/received-applications';
  static const hostedVenueBookings = '/hosted-venue-bookings';
  static const books = '/books';
  static const notifications = '/notifications';
  static const properties = '/properties';
  static const maintenance = '/maintenance';
  static const inspections = '/inspections';
  static const reviews = '/reviews';

  static String inspection(String book, String id) =>
      '/inspections/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';

  static String maintenanceRequest(String book, String id) =>
      '/maintenance/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';

  static String newProperty(String book) =>
      '/properties/${Uri.encodeComponent(book)}/new';
  static String managedProperty(String book, String id) =>
      '/properties/${Uri.encodeComponent(book)}/p/${Uri.encodeComponent(id)}';
  static String newTenancy(String book, String propertyId) =>
      '${managedProperty(book, propertyId)}/new-tenancy';
  static String tenancy(String book, String id) =>
      '/tenancies/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';
  static const notificationPreferences = '/notification-preferences';
  static const legalUpdates = '/legal-updates';

  /// Development projects (API 0.44.0), at the website's own paths.
  static const developments = '/developments';
  static String development(String market, String slug) =>
      '/developments/${Uri.encodeComponent(market.toLowerCase())}/'
      '${Uri.encodeComponent(slug)}';
  static String developmentEnquiry(
    String market,
    String slug, {
    String? unitTypeId,
  }) => Uri(
    path: '${development(market, slug)}/enquire',
    queryParameters: unitTypeId == null ? null : {'unit_type': unitTypeId},
  ).toString();

  static String newLedgerEntry(String book) =>
      '/books/${Uri.encodeComponent(book)}/new';
  static String ledgerEntry(String book, String id) =>
      '/books/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';

  static String bookHourly(String listingId) =>
      '/venues/${Uri.encodeComponent(listingId)}/book';
  static String myVenueBooking(String id) =>
      '/my-venue-bookings/${Uri.encodeComponent(id)}';
  static String hostedVenueBooking(String book, String id) =>
      '/hosted-venue-bookings/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';

  static String apply(String slug) => '/apply/${Uri.encodeComponent(slug)}';
  static String continueApplication(String id) =>
      '/my-applications/${Uri.encodeComponent(id)}/continue';
  static String myApplication(String id) =>
      '/my-applications/${Uri.encodeComponent(id)}';
  static String receivedApplication(String organisation, String id) =>
      '/received-applications/${Uri.encodeComponent(organisation)}/${Uri.encodeComponent(id)}';

  /// [book] is the organisation (or a direct owner's user) ID.
  static String contact(String book, String id) =>
      '/contacts/${Uri.encodeComponent(book)}/${Uri.encodeComponent(id)}';
  static String newContact(String book) =>
      '/contacts/${Uri.encodeComponent(book)}/new';

  static String receivedAppointment(String id) =>
      '/appointments/${Uri.encodeComponent(id)}';
  static String myAppointment(String id) =>
      '/my-appointments/${Uri.encodeComponent(id)}';
  static String myRequest(String id) =>
      '/my-requests/${Uri.encodeComponent(id)}';
  static String lead(String requestId) =>
      '/inbox/${Uri.encodeComponent(requestId)}';

  static String team(String organisationId) =>
      '/team/${Uri.encodeComponent(organisationId)}';
  static String lease(String id) => '/leases/${Uri.encodeComponent(id)}';
  static String editLease(String id) =>
      '/leases/${Uri.encodeComponent(id)}/edit';

  /// Matches the emailed signing and invitation links on the website.
  static String sign(String token) => '/sign/${Uri.encodeComponent(token)}';
  static String invitation(String token) =>
      '/invitations/${Uri.encodeComponent(token)}';

  /// With no token these open the screen where the emailed link is pasted.
  static String verifyEmail([String? token]) =>
      _withToken('/verify-email', token);
  static String resetPassword([String? token]) =>
      _withToken('/reset-password', token);
  static String _withToken(String path, String? token) => token == null
      ? path
      : Uri(path: path, queryParameters: {'token': token}).toString();

  static String search({
    String query = '',
    DealType? deal,
    ListingCategory? category,
  }) => Uri(
    path: '/search',
    queryParameters: {
      if (query.isNotEmpty) 'q': query,
      'deal': ?deal?.name,
      'category': ?category?.name,
    },
  ).toString();

  /// [heroScope] names the row the listing was opened from, so its photo can
  /// animate into the detail screen.
  static String listing(String slug, {String heroScope = 'list'}) =>
      '/listings/$slug?from=$heroScope';
  static String request(String slug) => '/listings/$slug/request';

  static String directoryKind(DirectoryKind kind) => '/profiles/${kind.slug}';
  static String profile(Profile profile) =>
      '/profiles/${profile.kind.slug}/${profile.slug}';
  static String profileEnquiry(Profile profile) =>
      '/profiles/${profile.kind.slug}/${profile.slug}/enquire';
}

T? _byName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// The book a pushed screen was opened for, or a read-only stand-in made
/// from the path (the API checks access either way).
ContactBook _bookFrom(GoRouterState state) =>
    state.extra as ContactBook? ??
    ContactBook(id: state.pathParameters['book']!, name: '', canWrite: false);

GoRouter buildRouter() => GoRouter(
  initialLocation: Routes.home,
  // Website links (App Links, Universal Links, the app scheme) whose path
  // the app does not have as such.
  redirect: (context, state) => webLinkRedirect(state.uri),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) {
                final params = state.uri.queryParameters;
                return SearchScreen(
                  initial: ListingFilters(
                    query: params['q'] ?? '',
                    deal: _byName(DealType.values, params['deal']),
                    category: _byName(
                      ListingCategory.values,
                      params['category'],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/directory',
              builder: (context, state) => const DirectoryHubScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/activity',
              builder: (context, state) =>
                  ActivityScreen(tab: state.uri.queryParameters['tab']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/account',
              builder: (context, state) => const AccountScreen(),
            ),
          ],
        ),
      ],
    ),
    // Everything below is pushed above the shell and covers the bottom bar.
    GoRoute(
      path: '/listings/:slug',
      builder: (context, state) => ListingDetailScreen(
        slug: state.pathParameters['slug']!,
        heroScope: state.uri.queryParameters['from'] ?? 'list',
      ),
      routes: [
        GoRoute(
          path: 'request',
          builder: (context, state) =>
              PropertyRequestScreen(slug: state.pathParameters['slug']!),
        ),
      ],
    ),
    GoRoute(
      path: '/profiles/:kind',
      builder: (context, state) => DirectoryListScreen(
        kind: DirectoryKind.fromSlug(state.pathParameters['kind']),
      ),
      routes: [
        GoRoute(
          path: ':slug',
          builder: (context, state) => ProfileScreen(
            kind: DirectoryKind.fromSlug(state.pathParameters['kind']),
            slug: state.pathParameters['slug']!,
          ),
          routes: [
            GoRoute(
              path: 'enquire',
              builder: (context, state) => ProfileEnquiryScreen(
                kind: DirectoryKind.fromSlug(state.pathParameters['kind']),
                slug: state.pathParameters['slug']!,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => const SignInScreen(),
    ),
    GoRoute(
      path: '/inbox',
      builder: (context, state) => const InboxScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              LeadScreen(requestId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/appointments',
      builder: (context, state) => const ReceivedAppointmentsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => AppointmentScreen(
            id: state.pathParameters['id']!,
            professional: true,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/my-appointments/:id',
      builder: (context, state) => AppointmentScreen(
        id: state.pathParameters['id']!,
        professional: false,
      ),
    ),
    GoRoute(
      path: '/properties',
      builder: (context, state) => PropertiesScreen(
        books: state.extra as List<ContactBook>? ?? const [],
      ),
      routes: [
        GoRoute(
          path: ':book/new',
          builder: (context, state) =>
              NewPropertyScreen(book: _bookFrom(state)),
        ),
        GoRoute(
          path: ':book/p/:id',
          builder: (context, state) => ManagedPropertyScreen(
            book: _bookFrom(state),
            id: state.pathParameters['id']!,
          ),
          routes: [
            GoRoute(
              path: 'new-tenancy',
              builder: (context, state) {
                final extra =
                    state.extra!
                        as ({
                          ContactBook book,
                          ManagedProperty property,
                          TenancyOptions options,
                        });
                return NewTenancyScreen(
                  book: extra.book,
                  property: extra.property,
                  options: extra.options,
                );
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/open',
      builder: (context, state) =>
          LinkOpenerScreen(link: state.uri.queryParameters['to'] ?? '/'),
    ),
    GoRoute(
      path: '/reviews',
      builder: (context, state) =>
          ReviewsScreen(tab: state.uri.queryParameters['tab']),
    ),
    GoRoute(
      path: '/inspections',
      builder: (context, state) => InspectionsScreen(
        books: state.extra as List<ContactBook>? ?? const [],
      ),
      routes: [
        GoRoute(
          path: ':book/:id',
          builder: (context, state) => InspectionScreen(
            book: _bookFrom(state),
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/maintenance',
      builder: (context, state) => MaintenanceScreen(
        books: state.extra as List<ContactBook>? ?? const [],
      ),
      routes: [
        GoRoute(
          path: ':book/:id',
          builder: (context, state) => MaintenanceRequestScreen(
            book: _bookFrom(state),
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/tenancies/:book/:id',
      builder: (context, state) => TenancyScreen(
        book: _bookFrom(state),
        id: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/notification-preferences',
      builder: (context, state) => const NotificationPreferencesScreen(),
    ),
    GoRoute(
      path: '/legal-updates',
      builder: (context, state) => const LegalUpdatesScreen(),
    ),
    GoRoute(
      path: '/developments',
      builder: (context, state) => const DevelopmentsScreen(),
      routes: [
        GoRoute(
          path: ':market/:slug',
          builder: (context, state) => DevelopmentScreen(
            market: state.pathParameters['market']!,
            slug: state.pathParameters['slug']!,
          ),
          routes: [
            GoRoute(
              path: 'enquire',
              builder: (context, state) => DevelopmentEnquiryScreen(
                market: state.pathParameters['market']!,
                slug: state.pathParameters['slug']!,
                unitTypeId: state.uri.queryParameters['unit_type'],
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/books',
      builder: (context, state) =>
          BooksScreen(books: state.extra as List<ContactBook>? ?? const []),
      routes: [
        GoRoute(
          path: ':book/new',
          builder: (context, state) {
            final extra =
                state.extra! as ({ContactBook book, LedgerOptions options});
            return NewLedgerEntryScreen(
              book: extra.book,
              options: extra.options,
            );
          },
        ),
        GoRoute(
          path: ':book/:id',
          builder: (context, state) => LedgerEntryScreen(
            book:
                state.extra as ContactBook? ??
                ContactBook(
                  id: state.pathParameters['book']!,
                  name: '',
                  canWrite: false,
                ),
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/venues/:id/book',
      builder: (context, state) => HourlyBookingScreen(
        listingId: state.pathParameters['id']!,
        title: state.extra as String? ?? 'Venue',
      ),
    ),
    GoRoute(
      path: '/my-venue-bookings/:id',
      builder: (context, state) =>
          VenueBookingScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/hosted-venue-bookings',
      builder: (context, state) => HostedVenueBookingsScreen(
        books: state.extra as List<ContactBook>? ?? const [],
      ),
      routes: [
        GoRoute(
          path: ':book/:id',
          builder: (context, state) => VenueBookingScreen(
            id: state.pathParameters['id']!,
            book:
                state.extra as ContactBook? ??
                ContactBook(
                  id: state.pathParameters['book']!,
                  name: '',
                  canWrite: true,
                ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/apply/:slug',
      builder: (context, state) =>
          ApplyScreen(slug: state.pathParameters['slug']),
    ),
    GoRoute(
      path: '/my-applications/:id',
      builder: (context, state) =>
          MyApplicationScreen(id: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'continue',
          builder: (context, state) =>
              ApplyScreen(applicationId: state.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(
      path: '/received-applications',
      builder: (context, state) => ReceivedApplicationsScreen(
        books: state.extra as List<ContactBook>? ?? const [],
      ),
      routes: [
        GoRoute(
          path: ':org/:id',
          builder: (context, state) => ReceivedApplicationScreen(
            organisationId: state.pathParameters['org']!,
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/contacts',
      builder: (context, state) =>
          ContactsScreen(books: state.extra as List<ContactBook>? ?? const []),
      routes: [
        GoRoute(
          path: ':book/new',
          builder: (context, state) => NewContactScreen(
            book:
                state.extra as ContactBook? ??
                ContactBook(
                  id: state.pathParameters['book']!,
                  name: '',
                  canWrite: true,
                ),
          ),
        ),
        GoRoute(
          path: ':book/:id',
          builder: (context, state) => ContactScreen(
            book:
                state.extra as ContactBook? ??
                ContactBook(
                  id: state.pathParameters['book']!,
                  name: '',
                  canWrite: false,
                ),
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/statistics',
      builder: (context, state) => StatisticsScreen(
        organisations: state.extra as List<WorkOrganisation>? ?? const [],
      ),
    ),
    GoRoute(
      path: '/my-requests/:id',
      builder: (context, state) =>
          MyRequestScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/account-management',
      builder: (context, state) => const AccountManagementScreen(),
      routes: [
        GoRoute(
          path: 'delete',
          builder: (context, state) => const DeleteAccountScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/team/:id',
      builder: (context, state) =>
          TeamScreen(organisationId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/invitations',
      builder: (context, state) => const InvitationScreen(),
      routes: [
        GoRoute(
          path: ':token',
          builder: (context, state) =>
              InvitationScreen(token: state.pathParameters['token']),
        ),
      ],
    ),
    GoRoute(
      path: '/leases',
      builder: (context, state) => const LeasesScreen(),
      routes: [
        // Before ':id', so "new" is not read as an ID.
        GoRoute(
          path: 'new',
          builder: (context, state) => const LeaseFormScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              LeaseDetailScreen(id: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  LeaseFormScreen(leaseId: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/signing',
      builder: (context, state) => const DocumentsToSignScreen(),
    ),
    GoRoute(
      path: '/signature',
      builder: (context, state) => const MySignatureScreen(),
    ),
    GoRoute(
      path: '/sign/:token',
      builder: (context, state) =>
          SigningScreen(token: state.pathParameters['token']!),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    // The next two paths match the links in the emails the API sends
    // ({WEB_BASE_URL}/verify-email?token=..., /reset-password?token=...), so
    // an email link opened on the phone lands on the right screen.
    GoRoute(
      path: '/verify-email',
      builder: (context, state) =>
          VerifyEmailScreen(token: state.uri.queryParameters['token']),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) =>
          ResetPasswordScreen(token: state.uri.queryParameters['token']),
    ),
  ],
);
