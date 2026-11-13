import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../features/listings/data/listing_repository.dart';
import '../features/property_requests/data/property_request_repository.dart';
import 'app_scope.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class RightPropertyApp extends StatefulWidget {
  const RightPropertyApp({super.key, this.listings, this.propertyRequests});

  /// Overrides for tests. Production uses the defaults below.
  final ListingRepository? listings;
  final PropertyRequestRepository? propertyRequests;

  @override
  State<RightPropertyApp> createState() => _RightPropertyAppState();
}

class _RightPropertyAppState extends State<RightPropertyApp> {
  late final GoRouter _router = buildRouter();
  late final ListingRepository _listings =
      widget.listings ?? const SampleListingRepository();
  late final PropertyRequestRepository _requests =
      widget.propertyRequests ??
      ApiPropertyRequestRepository(ApiClient(baseUrl: AppConfig.apiBaseUrl));

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      listings: _listings,
      propertyRequests: _requests,
      child: MaterialApp.router(
        title: 'RightProperty365',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
