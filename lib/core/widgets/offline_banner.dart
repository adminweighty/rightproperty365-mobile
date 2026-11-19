import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../api/offline.dart';

/// Above every screen while the API cannot be reached: says so plainly,
/// and how old what is shown is.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    super.key,
    required this.connectivity,
    required this.child,
  });

  final Connectivity connectivity;
  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _trying = false;

  Future<void> _retry() async {
    setState(() => _trying = true);
    await widget.connectivity.retry();
    if (mounted) setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.connectivity,
    builder: (context, _) {
      final c = context.colors;
      final connectivity = widget.connectivity;
      if (connectivity.online) return widget.child;
      final from = connectivity.showingFrom;
      final text = Theme.of(context).textTheme;
      return Column(
        children: [
          Material(
            key: const Key('offline-banner'),
            color: c.sunken,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  Space.x2,
                  Space.x2,
                  Space.x2,
                ),
                child: Row(
                  children: [
                    const ExcludeSemantics(
                      child: Icon(Icons.cloud_off_outlined, size: 20),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          from == null
                              ? 'You are offline. Anything new needs a '
                                    'connection; nothing is sent until then.'
                              : 'You are offline. Showing what this phone '
                                    'saved on ${DateFormat('d MMM, HH:mm').format(from.toLocal())}.',
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('offline-retry'),
                      onPressed: _trying ? null : _retry,
                      child: Text(_trying ? 'Trying…' : 'Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      );
    },
  );
}
