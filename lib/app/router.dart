import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_screens.dart';
import '../features/directory/data/profile.dart';
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
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
  ],
);
