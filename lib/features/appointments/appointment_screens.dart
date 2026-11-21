import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../core/calendar.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/market_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_screens.dart';
import 'appointment_repository.dart';

BadgeTone _tone(String status) => switch (status) {
  'CONFIRMED' || 'COMPLETED' => BadgeTone.success,
  'REQUESTED' || 'RESCHEDULE_REQUESTED' => BadgeTone.primary,
  _ => BadgeTone.neutral,
};

/// One appointment in a list.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard(
    this.appointment, {
    super.key,
    required this.professional,
    required this.onTap,
  });

  final Appointment appointment;
  final bool professional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final text = Theme.of(context).textTheme;
    final when = MarketTime.format(a.startUtc, a.timezone);
    final waiting =
        a.status == 'RESCHEDULE_REQUESTED' && a.proposedStartUtc != null
        ? (a.proposedBy == 'CUSTOMER') == professional
              ? 'New time proposed to you'
              : 'Waiting for them to accept your new time'
        : null;
    final who = professional ? a.contactName : a.withName;
    return BrandCard(
      key: Key('appointment-${a.reference}'),
      onTap: onTap,
      emphasised: waiting != null && waiting.startsWith('New time'),
      semanticLabel:
          '${a.typeLabel}: ${a.title}. ${a.statusLabel}. $when'
          '${waiting == null ? '' : '. $waiting'}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(a.title, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(a.statusLabel, tone: _tone(a.status)),
              ],
            ),
            const SizedBox(height: Space.x1),
            Text(
              '${a.typeLabel}${who == null ? '' : ' with $who'}',
              style: text.bodyMedium,
            ),
            if (a.serviceLabel != null)
              Text(a.serviceLabel!, style: text.bodyMedium),
            Text(when, style: text.bodyMedium),
            if (waiting != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x1),
                child: Text(waiting, style: text.titleSmall),
              ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in Property Seeker's viewings and consultations, on the
/// Activity tab.
class MyViewingsView extends StatefulWidget {
  const MyViewingsView({super.key});

  @override
  State<MyViewingsView> createState() => _MyViewingsViewState();
}

class _MyViewingsViewState extends State<MyViewingsView> {
  String _when = 'upcoming';
  Future<AppointmentPage>? _page;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= AppScope.of(context).myAppointments.list(when: _when);
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).myAppointments.list(when: _when);
    setState(() {
      _page = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          SegmentedButton<String>(
            key: const Key('viewings-when'),
            segments: const [
              ButtonSegment(value: 'upcoming', label: Text('Upcoming')),
              ButtonSegment(value: 'past', label: Text('Past')),
            ],
            selected: {_when},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              _when = s.first;
              _reload();
            },
          ),
          const SizedBox(height: Space.x4),
          FutureBuilder<AppointmentPage>(
            future: _page,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Center(
                    child: Semantics(
                      label: 'Loading',
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _Problem(
                  title: 'We could not load your viewings',
                  onRetry: _reload,
                );
              }
              final items = snapshot.data!.items;
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x6),
                  child: Text(
                    _when == 'upcoming'
                        ? 'No upcoming viewings. Ask for one from a listing: choose "Book a viewing" '
                              'and a preferred time.'
                        : 'No past viewings.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Column(
                children: [
                  for (final a in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x3),
                      child: AppointmentCard(
                        a,
                        professional: false,
                        onTap: () async {
                          await context.push(Routes.myAppointment(a.id));
                          if (mounted) _reload();
                        },
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

class _Problem extends StatelessWidget {
  const _Problem({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.x6),
    child: Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.x2),
        const Text('Check your connection and try again.'),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// Appointments received by an Estate Agent, agency, Landlord, Property
/// Seller or other professional, soonest first from today.
class ReceivedAppointmentsScreen extends StatefulWidget {
  const ReceivedAppointmentsScreen({super.key});

  @override
  State<ReceivedAppointmentsScreen> createState() =>
      _ReceivedAppointmentsScreenState();
}

class _ReceivedAppointmentsScreenState
    extends State<ReceivedAppointmentsScreen> {
  Future<AppointmentPage>? _page;

  Future<AppointmentPage> _load() {
    final now = DateTime.now();
    return AppScope.of(context).receivedAppointments
        .list(from: DateTime(now.year, now.month, now.day));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= _load();
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _page = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewing Appointments'),
        actions: [
          IconButton(
            key: const Key('open-availability'),
            tooltip: 'Availability and consultations',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: () => context.push(Routes.availability),
          ),
        ],
      ),
      body: FutureBuilder<AppointmentPage>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Semantics(
                label: 'Loading',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final error = snapshot.error;
          if (error != null) {
            final none = error is ApiFailure && error.status == 403;
            return MessageView(
              icon: none ? Icons.lock_outline : Icons.cloud_off_outlined,
              title: none
                  ? 'This account takes no appointments'
                  : 'We could not load your appointments',
              body: none
                  ? 'Appointments open once your professional role is approved and you are linked '
                        'to your agency, firm or listings.'
                  : 'Check your connection and try again.',
              actionLabel: none ? null : 'Try again',
              onAction: none ? null : _reload,
            );
          }
          final items = snapshot.data!.items;
          if (items.isEmpty) {
            return MessageView(
              icon: Icons.event_available_outlined,
              title: 'No appointments from today on',
              body: 'Viewings and consultations that customers ask for appear here.',
              actionLabel: 'Refresh',
              onAction: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                Text(
                  'From today, soonest first. Times are in the market\'s time zone.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x4),
                for (final day in _byDay(items).entries) ...[
                  SectionHeading(day.key),
                  const SizedBox(height: Space.x2),
                  for (final a in day.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x3),
                      child: AppointmentCard(
                        a,
                        professional: true,
                        onTap: () async {
                          await context.push(Routes.receivedAppointment(a.id));
                          if (mounted) _reload();
                        },
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// A simple agenda: the appointments grouped by their day in the market.
  Map<String, List<Appointment>> _byDay(List<Appointment> items) {
    final days = <String, List<Appointment>>{};
    for (final a in items) {
      final day = DateFormat('EEEE d MMMM')
          .format(MarketTime.inZone(a.startUtc, a.timezone));
      days.putIfAbsent(day, () => []).add(a);
    }
    return days;
  }
}

/// Asks for a new date and time in the market's time zone; the instant in
/// UTC, or null when the person cancels.
Future<DateTime?> pickAppointmentTime(
  BuildContext context, {
  required String zone,
  required DateTime currentUtc,
}) async {
  final now = MarketTime.inZone(DateTime.now().toUtc(), zone);
  final current = MarketTime.inZone(currentUtc, zone);
  final initial = current.isAfter(now) ? current : now;
  final day = await showDatePicker(
    context: context,
    helpText: 'New date (${MarketTime.zoneName(zone)} time)',
    initialDate: DateTime(initial.year, initial.month, initial.day),
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 1, now.month, now.day),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    helpText: 'New time (${MarketTime.zoneName(zone)} time)',
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
  );
  if (time == null) return null;
  return MarketTime.toUtc(
    DateTime(day.year, day.month, day.day, time.hour, time.minute),
    zone,
  );
}

/// Asks for a short text; null when cancelled.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  bool required = false,
  int maxLength = 500,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextDialog(
    title: title,
    label: label,
    action: action,
    required: required,
    maxLength: maxLength,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.action,
    required this.required,
    required this.maxLength,
  });

  final String title;
  final String label;
  final String action;
  final bool required;
  final int maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _text = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.required && _text.text.trim().isEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('dialog-text'),
        controller: _text,
        maxLength: widget.maxLength,
        minLines: 2,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _tried && missing ? 'Write a few words.' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        TextButton(
          key: const Key('dialog-confirm'),
          onPressed: () {
            // Read the text now: it may have changed since the last build.
            if (widget.required && _text.text.trim().isEmpty) {
              setState(() => _tried = true);
              return;
            }
            Navigator.pop(context, _text.text.trim());
          },
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// One appointment with its history and the actions the API allows, for
/// the customer ([professional] false) or the professional.
class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({
    super.key,
    required this.id,
    required this.professional,
  });

  final String id;
  final bool professional;

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  Future<Appointment>? _loading;
  Appointment? _appointment;
  ApiFailure? _failure;
  bool _busy = false;

  Future<Appointment> _get() {
    final services = AppScope.of(context);
    return widget.professional
        ? services.receivedAppointments.get(widget.id)
        : services.myAppointments.get(widget.id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get().then((a) => _appointment = a);
  }

  void _reload() => setState(() {
    _failure = null;
    _loading = _get().then((a) => _appointment = a);
  });

  Future<void> _run(Future<Appointment> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _appointment = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(Appointment a) async {
    final start = await pickAppointmentTime(
      context,
      zone: a.timezone,
      currentUtc: a.proposedStartUtc ?? a.startUtc,
    );
    if (start == null || !mounted) return;
    final services = AppScope.of(context);
    await _run(
      () => widget.professional
          ? services.receivedAppointments.reschedule(a.id, start)
          : services.myAppointments.reschedule(a.id, start),
      'New time proposed. They are told by email.',
    );
  }

  Future<void> _addToCalendar(Appointment a) async {
    final messenger = ScaffoldMessenger.of(context);
    final services = AppScope.of(context);
    final added = await services.addToCalendar(
      CalendarEvent(
        title: '${a.typeLabel}: ${a.title}',
        start: a.startUtc,
        end: a.startUtc.add(Duration(minutes: a.durationMinutes)),
        location: a.locationNote ?? a.listingTitle,
        notes: 'RightProperty365 appointment ${a.reference}',
        file: () async => (
          bytes: await (widget.professional
              ? services.receivedAppointments.calendarFile(a.id)
              : services.myAppointments.calendarFile(a.id)),
          name: 'appointment-${a.reference}.ics',
        ),
      ),
    );
    if (!added) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No calendar on this phone could take it.'),
        ),
      );
    }
  }

  Future<void> _cancel(Appointment a) async {
    final reason = await askForText(
      context,
      title: 'Cancel this appointment?',
      label: widget.professional
          ? 'Reason (shown to the customer)'
          : 'Reason (optional)',
      action: 'Cancel appointment',
      required: widget.professional,
    );
    if (reason == null || !mounted) return;
    final services = AppScope.of(context);
    await _run(
      () => widget.professional
          ? services.receivedAppointments.cancel(a.id, reason)
          : services.myAppointments.cancel(a.id, reason: reason),
      'Appointment cancelled.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: FutureBuilder<Appointment>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Semantics(
                label: 'Loading',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final a = _appointment;
          if (snapshot.hasError || a == null) {
            final gone =
                snapshot.error is ApiFailure &&
                (snapshot.error as ApiFailure).status == 404;
            return MessageView(
              icon: Icons.event_busy_outlined,
              title: gone
                  ? 'This appointment is not available'
                  : 'We could not load this appointment',
              body: gone
                  ? 'It may belong to someone else now.'
                  : 'Check your connection and try again.',
              actionLabel: gone ? null : 'Try again',
              onAction: gone ? null : _reload,
            );
          }
          return _body(context, a);
        },
      ),
    );
  }

  Widget _body(BuildContext context, Appointment a) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final services = AppScope.of(context);
    final pro = widget.professional;
    final proposed = a.proposedStartUtc;
    final proposalToMe =
        proposed != null && (a.proposedBy == 'CUSTOMER') == pro;

    Widget line(IconData icon, String value, {bool selectable = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: Space.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 20, color: c.muted)),
              const SizedBox(width: Space.x3),
              Expanded(
                child: selectable
                    ? SelectableText(value, style: text.bodyLarge)
                    : Text(value, style: text.bodyLarge),
              ),
            ],
          ),
        );

    final actions = <Widget>[
      if (a.status == 'CONFIRMED' &&
          a.startUtc
              .add(Duration(minutes: a.durationMinutes))
              .isAfter(DateTime.now().toUtc()))
        OutlinedButton.icon(
          key: const Key('appointment-calendar'),
          onPressed: () => _addToCalendar(a),
          icon: const Icon(Icons.event_available_outlined),
          label: const Text('Add to calendar'),
        ),
      if (!pro && a.canAccept)
        FilledButton(
          key: const Key('appointment-accept'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => services.myAppointments.accept(a.id),
                  'New time accepted. The appointment is confirmed.',
                ),
          child: const Text('Accept the new time'),
        ),
      if (pro && a.canConfirm)
        FilledButton(
          key: const Key('appointment-confirm'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => services.receivedAppointments.confirm(a.id),
                  'Confirmed. The customer is told by email.',
                ),
          child: Text(
            a.status == 'RESCHEDULE_REQUESTED'
                ? 'Accept the customer\'s time'
                : 'Confirm this time',
          ),
        ),
      if (a.canReschedule)
        OutlinedButton(
          key: const Key('appointment-reschedule'),
          onPressed: _busy ? null : () => _propose(a),
          child: const Text('Propose another time'),
        ),
      if (pro && a.canComplete)
        OutlinedButton(
          key: const Key('appointment-complete'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => services.receivedAppointments.complete(a.id),
                  'Marked as completed.',
                ),
          child: const Text('It took place'),
        ),
      if (pro && a.canNoShow)
        OutlinedButton(
          key: const Key('appointment-no-show'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => services.receivedAppointments.noShow(a.id),
                  'Marked as a no-show.',
                ),
          child: const Text('The customer did not come'),
        ),
      if (a.canCancel)
        TextButton(
          key: const Key('appointment-cancel'),
          onPressed: _busy ? null : () => _cancel(a),
          child: Text('Cancel appointment', style: TextStyle(color: c.danger)),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(a.title, style: text.headlineSmall),
              ),
            ),
            const SizedBox(width: Space.x2),
            AppBadge(a.statusLabel, tone: _tone(a.status)),
          ],
        ),
        Text(
          '${a.typeLabel} · ${a.reference}',
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        if (a.serviceLabel != null)
          Text(
            a.serviceLabel!,
            key: const Key('appointment-service'),
            style: text.bodyLarge,
          ),
        const SizedBox(height: Space.x3),
        line(
          Icons.schedule,
          '${MarketTime.format(a.startUtc, a.timezone)} · ${a.durationMinutes} minutes',
        ),
        if (proposed != null)
          Container(
            margin: const EdgeInsets.only(top: Space.x3),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                proposalToMe
                    ? '${pro ? 'The customer' : 'They'} proposed '
                          '${MarketTime.format(proposed, a.timezone)}.'
                    : 'You proposed ${MarketTime.format(proposed, a.timezone)}. '
                          'Waiting for ${pro ? 'the customer' : 'them'} to accept.',
                style: text.bodyLarge,
              ),
            ),
          ),
        if (!pro && a.withName != null)
          line(Icons.storefront_outlined, 'With ${a.withName}'),
        if (a.assignedTo != null)
          line(Icons.badge_outlined, 'Assigned to ${a.assignedTo}'),
        if (a.locationNote != null) line(Icons.place_outlined, a.locationNote!),
        if (a.cancelReason != null)
          line(Icons.info_outline, 'Reason: ${a.cancelReason}'),
        if (pro && a.contactName != null) ...[
          const SizedBox(height: Space.x4),
          Text(
            'Customer${a.contactMethod == null ? '' : ' · prefers ${_method(a.contactMethod!)}'}',
            style: text.titleSmall,
          ),
          line(Icons.person_outline, a.contactName!),
          if (a.contactEmail != null)
            line(Icons.mail_outline, a.contactEmail!, selectable: true),
          if (a.contactPhone != null)
            line(Icons.phone_outlined, a.contactPhone!, selectable: true),
        ],
        if (a.note != null && a.note!.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          Text(pro ? 'Their note' : 'Your note', style: text.titleSmall),
          const SizedBox(height: Space.x1),
          Text(a.note!, style: text.bodyLarge),
        ],
        if (_failure != null) ...[
          const SizedBox(height: Space.x4),
          FailureBox(_failure!),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Space.x5),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x2),
              child: action,
            ),
        ],
        if (a.listingSlug != null)
          TextButton(
            onPressed: () => context.push(
              Routes.listing(a.listingSlug!, heroScope: 'appointment'),
            ),
            child: const Text('View the property'),
          ),
        if (a.timeline.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          if (pro) ...[
            OutlinedButton.icon(
              key: const Key('appointment-add-contact'),
              onPressed: () async {
                final work = await services.workspace.load();
                if (!context.mounted) return;
                await addToContacts(
                  context,
                  books: contactBooks(work, services.auth.user),
                  itemId: a.id,
                  kind: 'APPOINTMENT',
                );
              },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add to contacts'),
            ),
            const SizedBox(height: Space.x4),
          ],
          const SectionHeading('History'),
          const SizedBox(height: Space.x2),
          for (final e in a.timeline)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.describe(professional: pro), style: text.bodyLarge),
                  Text(
                    [
                      DateFormat('d MMM y, HH:mm')
                          .format(MarketTime.inZone(e.at, a.timezone)),
                      if (e.startUtc != null && e.event != 'CANCELLED')
                        'for ${MarketTime.format(e.startUtc!, a.timezone)}',
                    ].join(' · '),
                    style: text.bodySmall,
                  ),
                  if (e.note != null) Text(e.note!, style: text.bodyMedium),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _method(String code) => switch (code) {
    'PHONE' => 'a phone call',
    'WHATSAPP' => 'WhatsApp',
    _ => 'email',
  };
}
