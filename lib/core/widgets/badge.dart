import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';

enum BadgeTone { neutral, primary, accent, success, onPhoto }

/// A short, non-interactive label. Always carries text, never colour alone.
class AppBadge extends StatelessWidget {
  const AppBadge(
    this.label, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (background, foreground) = switch (tone) {
      BadgeTone.neutral => (c.sunken, c.muted),
      BadgeTone.primary => (c.primarySoft, c.primaryInk),
      BadgeTone.accent => (c.accentSoft, c.accentInk),
      BadgeTone.success => (c.successSoft, c.success),
      // Sits on a photograph, so it needs an opaque surface.
      BadgeTone.onPhoto => (c.surface, c.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: Space.x1),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sponsored" label for paid placements. Required wherever one is shown.
class SponsoredBadge extends StatelessWidget {
  const SponsoredBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppBadge('Sponsored', tone: BadgeTone.accent);
}

/// "Verified" label for checked advertisers and profiles.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) => const AppBadge(
    'Verified',
    tone: BadgeTone.success,
    icon: Icons.verified_outlined,
  );
}
