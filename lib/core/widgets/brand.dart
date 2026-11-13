import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';

/// The indigo-to-turquoise gradient from the logo, used for bold outlines and
/// heading rules.
LinearGradient brandGradient(AppColors c) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [c.brand, c.brandAccent],
);

/// A rounded frame around [child]. When [active] the frame is the 2px brand
/// gradient; otherwise it is the usual hairline.
class BrandOutline extends StatelessWidget {
  const BrandOutline({
    super.key,
    required this.child,
    this.active = true,
    this.radius = Radii.lg,
    this.width = 2,
  });

  final Widget child;
  final bool active;
  final double radius;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.base,
      padding: EdgeInsets.all(width),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: active
            ? brandGradient(c)
            : LinearGradient(colors: [c.line, c.line]),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - width),
        child: ColoredBox(color: c.surface, child: child),
      ),
    );
  }
}

/// A tappable card. The gradient outline shows while it is pressed, focused
/// or hovered, and always when [emphasised] (sponsored and primary surfaces).
class BrandCard extends StatefulWidget {
  const BrandCard({
    super.key,
    required this.child,
    this.onTap,
    this.emphasised = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool emphasised;

  /// When set, the card is announced as one button with this label.
  final String? semanticLabel;

  @override
  State<BrandCard> createState() => _BrandCardState();
}

class _BrandCardState extends State<BrandCard> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final card = BrandOutline(
      active: widget.emphasised || _pressed || _focused || _hovered,
      child: Material(
        type: MaterialType.transparency,
        child: widget.onTap == null
            ? widget.child
            : InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (value) => setState(() => _pressed = value),
                onFocusChange: (value) => setState(() => _focused = value),
                onHover: (value) => setState(() => _hovered = value),
                child: widget.child,
              ),
      ),
    );
    if (widget.semanticLabel == null) return card;
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: card,
    );
  }
}

/// A section title with the 3px brand rule under it and an optional action.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: Space.x2),
              Container(
                width: 48,
                height: 3,
                decoration: BoxDecoration(
                  gradient: brandGradient(context.colors),
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

/// The search field, framed by the brand gradient.
class BrandSearchField extends StatelessWidget {
  const BrandSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  static const label = 'Suburb, city or property type';

  @override
  Widget build(BuildContext context) {
    return BrandOutline(
      radius: Radii.md + 2,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          suffixIcon: IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward),
            onPressed: onSubmitted,
          ),
        ),
      ),
    );
  }
}

/// The official horizontal logo (kit v4.1). Indigo on light surfaces, white in
/// the dark theme and wherever [reverse] is set (on the brand indigo).
/// "365" is always turquoise. Never recolour or retype it.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.reverse = false, this.height = 28});

  final bool reverse;
  final double height;

  @override
  Widget build(BuildContext context) {
    final white = reverse || Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      white
          ? 'assets/brand/logo-horizontal-reverse.png'
          : 'assets/brand/logo-horizontal.png',
      height: height,
      semanticLabel: 'RightProperty365',
    );
  }
}
