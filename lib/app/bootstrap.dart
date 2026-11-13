import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../features/activity/activity_store.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/token_store.dart';
import '../features/directory/data/business_enquiry_repository.dart';
import '../features/directory/data/directory_repository.dart';
import '../features/listings/data/listing_repository.dart';
import '../features/property_requests/data/property_request_repository.dart';
import 'app_scope.dart';

/// Builds the production services: sample listings and directory from bundled
/// JSON, and the Go API for enquiries and identity.
Future<AppServices> bootstrap({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final auth = AuthController(
    repository: ApiAuthRepository(api),
    tokens: const SecureTokenStore(),
    api: api,
  );

  final services = AppServices(
    listings: SampleListingRepository.fromJson(
      await assets.loadString('assets/data/listings.json'),
    ),
    directory: SampleDirectoryRepository.fromJson(
      await assets.loadString('assets/data/directory.json'),
    ),
    propertyRequests: ApiPropertyRequestRepository(api),
    businessEnquiries: ApiBusinessEnquiryRepository(api),
    auth: auth,
    activity: ActivityStore(
      PreferencesStore(await SharedPreferences.getInstance()),
    ),
  );

  // Not awaited: the app opens straight away and the account area updates
  // when the saved session has been checked.
  auth.restore();
  return services;
}
