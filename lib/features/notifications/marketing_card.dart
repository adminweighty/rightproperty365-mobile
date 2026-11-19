import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import 'marketing_repository.dart';

final _day = DateFormat('d MMM y');

/// News and offers: the one marketing choice. Off unless the person opts in
/// to the wording shown here; separate from service notifications, which
/// are below it. Turning it off is always possible.
class MarketingCard extends StatefulWidget {
  const MarketingCard({super.key});

  @override
  State<MarketingCard> createState() => _MarketingCardState();
}

class _MarketingCardState extends State<MarketingCard> {
  Future<MarketingPreferences>? _loading;
  MarketingPreferences? _prefs;
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<MarketingPreferences> _get() =>
      AppScope.of(context).marketing.get().then((p) => _prefs = p);

  Future<void> _set(bool on) async {
    final prefs = _prefs!;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final saved = await AppScope.of(context).marketing
          .set(on, version: on ? prefs.currentVersion : null);
      if (mounted) setState(() => _prefs = saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      // A changed wording: show the new one.
      if (failure.fields.containsKey('consent_text_version')) {
        setState(() => _loading = _get());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return FutureBuilder<MarketingPreferences>(
      future: _loading,
      builder: (context, snapshot) {
        final p = _prefs;
        // A Material, so the switch's ink shows on the card.
        return Material(
          key: const Key('marketing-card'),
          color: c.sunken,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('News and offers', style: text.titleSmall),
                const SizedBox(height: Space.x1),
                if (snapshot.hasError && p == null)
                  Text(
                    'We could not load this choice. Check your connection.',
                    style: text.bodyMedium,
                  )
                else if (p == null)
                  const Padding(
                    padding: EdgeInsets.all(Space.x2),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  MergeSemantics(
                    child: SwitchListTile(
                      key: const Key('marketing-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: p.optIn,
                      // Opting in only to wording this app can show.
                      onChanged: _saving || (!p.optIn && p.consentText == null)
                          ? null
                          : _set,
                      title: Text(
                        p.consentText ??
                            (p.optIn
                                ? 'You get news, tips and offers by email.'
                                : 'The wording to agree to could not be '
                                      'loaded, so this cannot be turned on just now.'),
                        style: text.bodyMedium,
                      ),
                    ),
                  ),
                  Text(
                    'Off unless you turn it on. Account, booking and other '
                    'service messages are set below and are not marketing.',
                    style: text.bodySmall,
                  ),
                  if (p.last != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x1),
                      child: Text(
                        '${p.last!.optIn ? 'Turned on' : 'Turned off'} '
                        '${_day.format(p.last!.changedAt)}'
                        '${p.last!.where.isEmpty ? '' : ' ${p.last!.where}'}.',
                        key: const Key('marketing-last'),
                        style: text.bodySmall,
                      ),
                    ),
                  if (p.history.length > 1)
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const Key('marketing-history'),
                        tilePadding: EdgeInsets.zero,
                        title: Text('Your choices', style: text.bodyMedium),
                        children: [
                          for (final h in p.history)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${_day.format(h.changedAt)}: '
                                '${h.optIn ? 'on' : 'off'}'
                                '${h.where.isEmpty ? '' : ' ${h.where}'}',
                                style: text.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                if (_failure != null) ...[
                  const SizedBox(height: Space.x2),
                  FailureBox(_failure!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
