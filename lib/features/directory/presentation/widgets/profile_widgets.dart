import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/widgets/badge.dart';
import '../../../../core/widgets/brand.dart';
import '../../data/profile.dart';

/// Initials on the brand gradient. Profiles have no photo yet.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, this.size = 48});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: brandGradient(c),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          profile.initials,
          style: TextStyle(
            color: c.onBrand,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}

/// One row of a directory list. Sponsored profiles are labelled and always
/// carry the gradient outline.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BrandCard(
      onTap: onTap,
      emphasised: profile.sponsored,
      semanticLabel: [
        if (profile.sponsored) 'Sponsored',
        profile.name,
        profile.role,
        profile.city,
        if (profile.verified) 'Verified',
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(profile),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name, style: text.titleMedium),
                  Text(
                    '${profile.role} · ${profile.city}',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    profile.tagline,
                    style: text.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.sponsored || profile.verified) ...[
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData directoryIcon(DirectoryKind kind) => switch (kind) {
  DirectoryKind.agencies => Icons.business_outlined,
  DirectoryKind.agents => Icons.badge_outlined,
  DirectoryKind.developers => Icons.construction_outlined,
  DirectoryKind.propertyManagers => Icons.key_outlined,
  DirectoryKind.hosts => Icons.event_available_outlined,
  DirectoryKind.serviceProviders => Icons.handyman_outlined,
};
