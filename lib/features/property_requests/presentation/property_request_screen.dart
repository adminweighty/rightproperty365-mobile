import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/config.dart';
import '../../../core/widgets/async_view.dart';
import '../../enquiries/presentation/enquiry_form.dart';
import '../../listings/data/listing.dart';
import '../data/property_request.dart';

/// Loads the listing for the route, then shows the request form.
class PropertyRequestScreen extends StatefulWidget {
  const PropertyRequestScreen({super.key, required this.slug});

  final String slug;

  @override
  State<PropertyRequestScreen> createState() => _PropertyRequestScreenState();
}

class _PropertyRequestScreenState extends State<PropertyRequestScreen> {
  Future<Listing?>? _listing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listing ??= AppScope.of(context).listings.bySlug(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send a request')),
      body: AsyncView<Listing?>(
        future: _listing!,
        builder: (context, listing) => listing == null
            ? const MessageView(
                icon: Icons.home_outlined,
                title: 'This listing is no longer available',
                body: 'It may have expired or been removed.',
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x4),
                child: PropertyRequestForm(listing: listing),
              ),
      ),
    );
  }
}

/// A listing enquiry. Posts to POST /v1/property-requests.
class PropertyRequestForm extends StatelessWidget {
  const PropertyRequestForm({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final recipient = listing.advertiser.kind == AdvertiserKind.agency
        ? listing.advertiser.name
        : listing.listedBy;
    return EnquiryForm(
      title: listing.title,
      subtitle:
          '${listing.location} · ${listing.listedBy}, ${listing.advertiser.name}',
      recipientName: recipient,
      defaultMessage:
          'Hello, I am interested in ${listing.reference}. Please send me more details.',
      showRequestType: true,
      onSubmit: (input) async {
        final receipt = await services.propertyRequests.submit(
          PropertyRequestDraft(
            listingId: listing.id,
            requestType: input.requestType,
            preferredSlot: input.preferredSlot,
            message: input.message,
            contactMethod: input.contactMethod,
            contact: input.contact,
            consentAccepted: input.consentAccepted,
            privacyVersion: AppConfig.privacyNoticeVersion,
          ),
        );
        // Kept on this phone so the reference can be found again in Activity.
        await services.activity.recordRequest(
          receipt: receipt,
          title: listing.title,
          recipient: recipient,
          route: Routes.listing(listing.slug, heroScope: 'activity'),
        );
        return receipt;
      },
    );
  }
}
