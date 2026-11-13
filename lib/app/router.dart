import 'package:go_router/go_router.dart';

import '../features/listings/data/listing.dart';
import '../features/listings/presentation/home_screen.dart';
import '../features/listings/presentation/listing_detail_screen.dart';
import '../features/listings/presentation/search_screen.dart';
import '../features/property_requests/presentation/property_request_screen.dart';
import '../features/shell/app_shell.dart';

/// Route locations. Build them here so paths are written in one place.
abstract final class Routes {
  static const home = '/';
  static const activity = '/activity';
  static const account = '/account';

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

  static String listing(String slug) => '/listings/$slug';
  static String request(String slug) => '/listings/$slug/request';
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
    // Pushed above the shell, so they cover the bottom navigation.
    GoRoute(
      path: '/listings/:slug',
      builder: (context, state) =>
          ListingDetailScreen(slug: state.pathParameters['slug']!),
      routes: [
        GoRoute(
          path: 'request',
          builder: (context, state) =>
              PropertyRequestScreen(slug: state.pathParameters['slug']!),
        ),
      ],
    ),
  ],
);
