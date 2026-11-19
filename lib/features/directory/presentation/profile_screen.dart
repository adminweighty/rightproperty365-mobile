import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/config.dart';
import '../../../core/terminology.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../../enquiries/presentation/enquiry_form.dart';
import '../../listings/data/listing.dart';
import '../../listings/presentation/widgets/listing_card.dart';
import '../data/business_enquiry_repository.dart';
import '../../analytics/analytics_tracker.dart';
import '../data/profile.dart';
import 'reviews_widgets.dart';
import 'widgets/profile_widgets.dart';

const _notFound = MessageView(
  icon: Icons.person_search_outlined,
  title: 'We could not find that profile',
  body: 'It may have been removed. Go back and choose another.',
);

/// A directory profile: about, services, areas, team and listings. Contact is
/// by enquiry only; no phone number or email address is shown.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.kind, required this.slug});

  final DirectoryKind? kind;
  final String slug;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<Listing>>? _listings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listings ??= AppScope.of(context).listings.search();
  }

  @override
  Widget build(BuildContext context) {
    final directory = AppScope.of(context).directory;
    final kind = widget.kind;
    final profile = kind == null ? null : directory.find(kind, widget.slug);
    if (profile == null) {
      return Scaffold(appBar: AppBar(), body: _notFound);
    }

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final info = directory.info(profile.kind);
    final agents = directory.agentsOfAgency(profile);
    final agency = directory.agencyOfAgent(profile);

    return Scaffold(
      appBar: AppBar(title: Text(info.singular)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x2,
            Space.x4,
            Space.x3,
          ),
          child: FilledButton(
            onPressed: () => context.push(Routes.profileEnquiry(profile)),
            child: Text('Send an enquiry to ${profile.name}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(profile, size: 64),
              const SizedBox(width: Space.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(profile.name, style: text.headlineSmall),
                    ),
                    Text(
                      [
                        profile.role,
                        profile.city,
                        if (profile.since != null) 'Since ${profile.since}',
                      ].join(' · '),
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: Space.x2),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x1,
                      children: [
                        if (profile.sponsored) const SponsoredBadge(),
                        if (profile.verified) const VerifiedBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          Text(profile.tagline, style: text.bodyLarge),
          if (agency != null) ...[
            const SizedBox(height: Space.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(Routes.profile(agency)),
                icon: const Icon(Icons.business_outlined),
                label: Text('${Terms.estateAgent} at ${agency.name}'),
              ),
            ),
          ],
          const SizedBox(height: Space.x6),
          const SectionHeading('About'),
          const SizedBox(height: Space.x3),
          Text(profile.about, style: text.bodyLarge?.copyWith(color: c.muted)),
          const SizedBox(height: Space.x6),
          const SectionHeading('Services'),
          const SizedBox(height: Space.x3),
          if (profile.offerings.isNotEmpty)
            for (final offering in profile.offerings)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offering.name, style: text.titleMedium),
                    Text(offering.description, style: text.bodyMedium),
                  ],
                ),
              )
          else
            for (final service in profile.services)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x1),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(Icons.check, size: 18, color: c.primaryInk),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(service, style: text.bodyLarge)),
                  ],
                ),
              ),
          const SizedBox(height: Space.x6),
          const SectionHeading('Areas covered'),
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [for (final area in profile.areas) AppBadge(area)],
          ),
          if (profile.kind == DirectoryKind.serviceProviders)
            ProfileReviewsSection(
              kind: profile.kind.slug,
              slug: profile.slug,
              name: profile.name,
            ),
          if (agents.isNotEmpty) ...[
            const SizedBox(height: Space.x6),
            const SectionHeading(Terms.estateAgents),
            const SizedBox(height: Space.x3),
            for (final agent in agents)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x3),
                child: ProfileCard(
                  profile: agent,
                  onTap: () => context.push(Routes.profile(agent)),
                ),
              ),
          ],
          FutureBuilder<List<Listing>>(
            future: _listings,
            builder: (context, snapshot) {
              final listings = directory.listingsFor(
                profile,
                snapshot.data ?? const [],
              );
              if (listings.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Space.x3),
                  const SectionHeading('Properties'),
                  const SizedBox(height: Space.x3),
                  for (final listing in listings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x4),
                      child: ListingCard(
                        listing: listing,
                        heroScope: 'profile-${profile.slug}',
                        placement: AnalyticsPlacement.rail,
                        onTap: () => context.push(
                          Routes.listing(
                            listing.slug,
                            heroScope: 'profile-${profile.slug}',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The enquiry form for a profile. Posts to POST /v1/business-enquiries.
class ProfileEnquiryScreen extends StatelessWidget {
  const ProfileEnquiryScreen({
    super.key,
    required this.kind,
    required this.slug,
  });

  final DirectoryKind? kind;
  final String slug;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final kind = this.kind;
    final profile = kind == null ? null : services.directory.find(kind, slug);
    return Scaffold(
      appBar: AppBar(title: const Text('Send an enquiry')),
      body: profile == null
          ? _notFound
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x4),
              child: EnquiryForm(
                title: profile.name,
                subtitle: '${profile.role} · ${profile.city}',
                recipientName: profile.name,
                defaultMessage:
                    'Hello, I would like to ask about your services.',
                services: profile.services,
                submitLabel: 'Send enquiry',
                onSubmit: (input) async {
                  final receipt = await services.businessEnquiries.submit(
                    BusinessEnquiryDraft(
                      recipient: profile,
                      service: input.service,
                      message: input.message,
                      contactMethod: input.contactMethod,
                      contact: input.contact,
                      consentAccepted: input.consentAccepted,
                      privacyVersion: AppConfig.privacyNoticeVersion,
                    ),
                  );
                  // Kept on this phone so the reference can be found again.
                  await services.activity.recordRequest(
                    receipt: receipt,
                    title: input.service ?? 'Enquiry',
                    recipient: profile.name,
                    route: Routes.profile(profile),
                  );
                  return receipt;
                },
              ),
            ),
    );
  }
}
