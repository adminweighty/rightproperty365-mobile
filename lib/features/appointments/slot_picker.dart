import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/market_time.dart';
import '../../core/widgets/searchable_select.dart';
import 'availability.dart';

/// Loads the offered times, for a consultation with the chosen service.
typedef SlotLoader = Future<AppointmentSlots> Function({
  required bool consultation,
  String? serviceId,
});

/// The customer's choice of time when the professional has set their
/// availability (API 0.51.0): a day, then one of its free starts, in the
/// market's time zone. With no availability set, [fallback] (the free date
/// and time picker) is shown instead.
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.load,
    required this.consultation,
    required this.selected,
    required this.onSelected,
    required this.serviceId,
    required this.onService,
    required this.fallback,
    this.error,
  });

  final SlotLoader load;
  final bool consultation;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelected;
  final String? serviceId;
  final ValueChanged<String?> onService;

  /// Shown while loading fails or no calendar is behind the target.
  final Widget fallback;

  /// The API's problem with the chosen time.
  final String? error;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  Future<AppointmentSlots>? _slots;
  String? _day;

  @override
  void initState() {
    super.initState();
    _slots = _load();
  }

  @override
  void didUpdateWidget(SlotPicker old) {
    super.didUpdateWidget(old);
    if (old.consultation != widget.consultation ||
        old.serviceId != widget.serviceId) {
      _day = null;
      _slots = _load();
    }
  }

  Future<AppointmentSlots> _load() => widget.load(
    consultation: widget.consultation,
    serviceId: widget.consultation ? widget.serviceId : null,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return FutureBuilder<AppointmentSlots>(
      future: _slots,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Semantics(
            label: 'Loading the free times',
            child: const LinearProgressIndicator(),
          );
        }
        final slots = snapshot.data;
        // Not reachable, or nobody's calendar: any time may be asked for.
        if (slots == null) return widget.fallback;
        final services = widget.consultation
            ? slots.services
            : const <ConsultationService>[];
        final picker = Column(
          key: const Key('slot-picker'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (services.isNotEmpty) ...[
              SearchableSelectField<String>(
                key: const Key('consultation-service'),
                label: 'Consultation (optional)',
                value: widget.serviceId,
                anyLabel: 'Any consultation',
                options: [
                  for (final s in services)
                    SelectOption(s.id, '${s.name} (${s.summary})'),
                ],
                onChanged: (id) {
                  widget.onSelected(null);
                  widget.onService(id);
                },
              ),
              const SizedBox(height: Space.x4),
            ],
            if (slots.configured) ..._times(context, slots),
          ],
        );
        if (!slots.configured) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [if (services.isNotEmpty) picker, widget.fallback],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            picker,
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: Text(
                  widget.error!,
                  style: text.bodyMedium?.copyWith(color: c.danger),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _times(BuildContext context, AppointmentSlots slots) {
    final text = Theme.of(context).textTheme;
    final zone = MarketTime.zoneName(slots.timezone);
    final days = slots.days.where((d) => d.slots.isNotEmpty).toList();
    if (days.isEmpty) {
      return [
        Text(
          'No free times in the coming days. Send your request without a '
          'time and they will suggest one.',
          key: const Key('slot-none'),
          style: text.bodyLarge,
        ),
      ];
    }
    final selected = widget.selected;
    final day =
        _day ??
        (selected == null
            ? days.first.date
            : days
                  .firstWhere(
                    (d) => d.slots.any((s) => s.startUtc == selected),
                    orElse: () => days.first,
                  )
                  .date);
    final current = days.firstWhere(
      (d) => d.date == day,
      orElse: () => days.first,
    );
    final dayLabel = DateFormat('EEE d MMM');
    final timeLabel = DateFormat('HH:mm');
    return [
      Text('Choose a time (optional)', style: text.titleMedium),
      Text('Times are in $zone time.', style: text.bodyMedium),
      const SizedBox(height: Space.x2),
      Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          for (final d in days)
            ChoiceChip(
              key: Key('slot-day-${d.date}'),
              label: Text(dayLabel.format(DateTime.parse(d.date))),
              selected: d.date == current.date,
              onSelected: (_) => setState(() => _day = d.date),
            ),
        ],
      ),
      const SizedBox(height: Space.x3),
      Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          for (final s in current.slots)
            ChoiceChip(
              key: Key('slot-${s.startUtc.toUtc().toIso8601String()}'),
              label: Text(
                timeLabel.format(MarketTime.inZone(s.startUtc, slots.timezone)),
              ),
              selected: selected == s.startUtc,
              onSelected: (on) => widget.onSelected(on ? s.startUtc : null),
            ),
        ],
      ),
    ];
  }
}
