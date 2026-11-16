import 'package:go_router/go_router.dart';

import '../features/activity/activity_screen.dart';
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

GoRouter buildRouter() => GoRouter(
  initialLocation: Routes.home,
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
              builder: (context, state) => const ActivityScreen(),
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
    GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
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
