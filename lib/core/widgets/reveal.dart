import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// Fades and slides [child] in once, [index] steps after its siblings, for a
/// staggered entrance. When the OS asks for reduced motion the child is shown
/// immediately with no animation.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _step = Duration(milliseconds: 70);

  late final Duration _delay = _step * widget.index.clamp(0, 6);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _delay + Motion.slow,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    // The delay is part of the timeline, so no timer is needed.
    curve: Interval(
      _delay.inMilliseconds / (_delay + Motion.slow).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _progress.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
