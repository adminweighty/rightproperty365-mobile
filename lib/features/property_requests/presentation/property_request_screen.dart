import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
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
    final requests = AppScope.of(context).propertyRequests;
    return EnquiryForm(
      title: listing.title,
      subtitle:
          '${listing.location} · ${listing.listedBy}, ${listing.advertiser.name}',
      recipientName: listing.advertiser.kind == AdvertiserKind.agency
          ? listing.advertiser.name
          : listing.listedBy,
      defaultMessage:
          'Hello, I am interested in ${listing.reference}. Please send me more details.',
      showRequestType: true,
      onSubmit: (input) => requests.submit(
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
      ),
    );
  }
}
