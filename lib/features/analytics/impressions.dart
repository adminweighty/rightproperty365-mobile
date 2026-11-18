import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../app/app_scope.dart';
import 'analytics_tracker.dart';

/// One screen's record of the cards already counted, so a card scrolled
/// away and back is counted once per screen visit.
class ImpressionScope extends StatefulWidget {
  const ImpressionScope({super.key, required this.child});

  final Widget child;

  static Set<String>? _seen(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ImpressionSet>()?.seen;

  @override
  State<ImpressionScope> createState() => _ImpressionScopeState();
}

class _ImpressionScopeState extends State<ImpressionScope> {
  final _seen = <String>{};

  @override
  Widget build(BuildContext context) =>
      _ImpressionSet(seen: _seen, child: widget.child);
}

class _ImpressionSet extends InheritedWidget {
  const _ImpressionSet({required this.seen, required super.child});

  final Set<String> seen;

  @override
  bool updateShouldNotify(_ImpressionSet oldWidget) => seen != oldWidget.seen;
}

/// Counts a listing card as seen once at least half of it has been on
/// screen for a second (`property_card_impression`).
class ImpressionTracker extends StatefulWidget {
  const ImpressionTracker({
    super.key,
    required this.listingId,
    required this.placement,
    required this.rank,
    required this.child,
  });

  final String listingId;
  final AnalyticsPlacement placement;
  final int rank;
  final Widget child;

  @override
  State<ImpressionTracker> createState() => _ImpressionTrackerState();
}

class _ImpressionTrackerState extends State<ImpressionTracker> {
  Timer? _wait;
  bool _counted = false;

  String get _key => '${widget.placement.name}:${widget.listingId}';

  void _visible(VisibilityInfo info) {
    if (_counted || !mounted) return;
    if (info.visibleFraction >= 0.5) {
      _wait ??= Timer(const Duration(seconds: 1), _count);
    } else {
      _wait?.cancel();
      _wait = null;
    }
  }

  void _count() {
    _wait = null;
    if (!mounted || _counted) return;
    final seen = ImpressionScope._seen(context);
    _counted = true;
    if (seen != null && !seen.add(_key)) return;
    AppScope.of(context).analytics.record(
      AnalyticsEventType.impression,
      widget.listingId,
      placement: widget.placement,
      rank: widget.rank,
    );
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
    key: ValueKey('impression-$_key-${widget.rank}'),
    onVisibilityChanged: _visible,
    child: widget.child,
  );
}
