import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../features/activity/activity_store.dart';
import '../features/activity/my_requests_repository.dart';
import '../features/appointments/appointment_repository.dart';
import '../features/inbox/lead_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/token_store.dart';
import '../features/directory/data/business_enquiry_repository.dart';
import '../features/directory/data/directory_repository.dart';
import '../features/inbox/inbox_repository.dart';
import '../features/leases/lease_repository.dart';
import '../features/signing/pdf_pages.dart';
import '../features/signing/signing_repository.dart';
import '../features/team/team_repository.dart';
import '../features/workspace/workspace.dart';
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
    inbox: ApiInboxRepository(api),
    workspace: ApiWorkspaceRepository(api),
    team: ApiTeamRepository(api),
    leases: ApiLeaseRepository(api),
    signing: ApiSigningRepository(api),
    pdf: const PlatformPdfRenderer(),
    pickSignatureImage: _pickSignatureImage,
    myRequests: ApiMyRequestsRepository(api),
    myAppointments: ApiMyAppointmentsRepository(api),
    receivedAppointments: ApiReceivedAppointmentsRepository(api),
    leads: ApiLeadRepository(api),
    activity: ActivityStore(
      PreferencesStore(await SharedPreferences.getInstance()),
    ),
  );

  // Not awaited: the app opens straight away and the account area updates
  // when the saved session has been checked.
  auth.restore();
  return services;
}

/// A photo of a signature, shrunk to the API's 2000 x 1000 pixel limit.
Future<Uint8List?> _pickSignatureImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    maxHeight: 1000,
    imageQuality: 85,
  );
  return file?.readAsBytes();
}
