import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/listing.dart';

/// Placeholder artwork shown until listing photos come from object storage.
/// Decorative, so it is hidden from screen readers.
class ListingMedia extends StatelessWidget {
  const ListingMedia({
    super.key,
    required this.tone,
    this.aspectRatio = 16 / 10,
  });

  final ListingTone tone;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (background, foreground) = switch (tone) {
      ListingTone.primary => (c.primarySoft, c.primaryInk),
      ListingTone.accent => (c.accentSoft, c.accentInk),
      ListingTone.neutral => (c.sunken, c.subtle),
    };
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ColoredBox(
          color: background,
          child: Center(
            child: Icon(
              Icons.home_work_outlined,
              size: 56,
              color: foreground.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
