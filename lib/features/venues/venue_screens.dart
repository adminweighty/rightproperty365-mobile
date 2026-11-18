import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/market_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../appointments/appointment_screens.dart' show askForText;
import '../auth/presentation/auth_screens.dart' show FailureBox;
import '../contacts/contacts_repository.dart' show ContactBook;
import 'venue_repository.dart';

String _hours(int minutes) {
  final h = minutes / 60;
  return h == h.roundToDouble()
      ? '${h.round()} h'
      : '${h.toStringAsFixed(1)} h';
}

String _clock(DateTime utc, String zone) =>
    DateFormat('HH:mm').format(MarketTime.inZone(utc, zone));

BadgeTone _tone(String status) => switch (status) {
  'CONFIRMED' || 'COMPLETED' => BadgeTone.success,
  'REQUESTED' || 'RESCHEDULE_REQUESTED' => BadgeTone.primary,
  _ => BadgeTone.neutral,
};

/// "Book by the hour" on a listing page, for a venue or showroom whose
/// host takes hourly bookings.
class HourlyBookingSection extends StatefulWidget {
  const HourlyBookingSection({
    super.key,
    required this.listingId,
    required this.slug,
    required this.title,
  });

  final String listingId;
  final String slug;
  final String title;

  @override
  State<HourlyBookingSection> createState() => _HourlyBookingSectionState();
}

class _HourlyBookingSectionState extends State<HourlyBookingSection> {
  Future<HourlyOffer?>? _offer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _offer ??= AppScope.of(context).listingDetails.hourly(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<HourlyOffer?>(
      future: _offer,
      builder: (context, snapshot) {
        final offer = snapshot.data;
        if (offer == null || !offer.enabled) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading('Book by the hour'),
              const SizedBox(height: Space.x2),
              Text(
                'From ${offer.currency} ${offer.ratePerHour} an hour. Choose a day and a time; '
                'the host confirms or declines your request.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: Space.x2),
              FilledButton.tonal(
                key: const Key('book-by-the-hour'),
                onPressed: () => context.push(
                  Routes.bookHourly(widget.listingId),
                  extra: widget.title,
                ),
                child: const Text('Book by the hour'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Choosing a day, a start and a duration from the venue's availability,
/// seeing the itemised estimate, and sending the request.
class HourlyBookingScreen extends StatefulWidget {
  const HourlyBookingScreen({
    super.key,
    required this.listingId,
    this.title = 'Venue',
  });

  final String listingId;
  final String title;

  @override
  State<HourlyBookingScreen> createState() => _HourlyBookingScreenState();
}

class _HourlyBookingScreenState extends State<HourlyBookingScreen> {
  Future<VenueAvailability>? _availability;
  VenueDay? _day;
  DateTime? _start;
  int? _minutes;
  Future<VenueQuote>? _quote;
  final _message = TextEditingController();
  final _attendees = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  ApiFailure? _failure;
  VenueBooking? _sent;

  VenueRepository get _repo => AppScope.of(context).venues;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _availability ??= _repo.availability(
      widget.listingId,
      from: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _message.dispose();
    _attendees.dispose();
    super.dispose();
  }

  void _requote() {
    final start = _start;
    final minutes = _minutes;
    setState(() {
      _failure = null;
      _quote = start == null || minutes == null
          ? null
          : _repo.quote(
              widget.listingId,
              start,
              start.add(Duration(minutes: minutes)),
            );
    });
  }

  Future<void> _send(VenueQuote quote) async {
    final services = AppScope.of(context);
    if (!services.auth.signedIn) {
      await context.push(Routes.signIn);
      if (!mounted || !services.auth.signedIn) return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final sent = await _repo.request(
        quote.id,
        message: _message.text,
        attendees: int.tryParse(_attendees.text.trim()),
        privacyVersion: AppConfig.privacyNoticeVersion,
      );
      if (mounted) setState(() => _sent = sent);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'QUOTE_EXPIRED') _requote();
      setState(() => _failure = failure.withMessage(slotProblem(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book by the hour')),
      body: AsyncView<VenueAvailability>(
        future: _availability!,
        onRetry: () => setState(() {
          _availability = _repo.availability(
            widget.listingId,
            from: DateTime.now(),
          );
        }),
        builder: (context, venue) =>
            _sent != null ? _Sent(_sent!) : _picker(context, venue),
      ),
    );
  }

  Widget _picker(BuildContext context, VenueAvailability venue) {
    final text = Theme.of(context).textTheme;
    final zone = venue.timeZone;
    final days = [
      for (final d in venue.days)
        if (d.bookable && venue.starts(d).isNotEmpty) d,
    ];
    final day = _day;
    final starts = day == null ? const <DateTime>[] : venue.starts(day);
    final durations = day == null || _start == null
        ? const <int>[]
        : venue.durations(day, _start!);
    final phoneZone = DateTime.now().timeZoneName;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Semantics(
          header: true,
          child: Text(widget.title, style: text.headlineSmall),
        ),
        Text(
          '${venue.currency} ${venue.ratePerHour} an hour · ${_hours(venue.minMinutes)} to ${_hours(venue.maxMinutes)} · '
          'times in ${MarketTime.zoneName(zone)} time',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Space.x4),
        Text('Day', style: text.titleSmall),
        const SizedBox(height: Space.x2),
        if (days.isEmpty)
          Text('No free times in the next two months.', style: text.bodyLarge)
        else
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
              itemBuilder: (context, i) {
                final d = days[i];
                final label = DateFormat('EEE d MMM')
                    .format(DateTime.parse(d.date));
                return ChoiceChip(
                  key: Key('venue-day-${d.date}'),
                  label: Text(label),
                  selected: _day?.date == d.date,
                  onSelected: (_) {
                    setState(() {
                      _day = d;
                      _start = null;
                      _minutes = null;
                    });
                    _requote();
                  },
                );
              },
            ),
          ),
        if (day?.note != null) Text(day!.note!, style: text.bodySmall),
        if (day != null) ...[
          const SizedBox(height: Space.x4),
          Text('Start', style: text.titleSmall),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final s in starts)
                ChoiceChip(
                  key: Key('venue-start-${_clock(s, zone)}'),
                  label: Text(_clock(s, zone)),
                  selected: _start == s,
                  onSelected: (_) {
                    setState(() {
                      _start = s;
                      final fits = venue.durations(day, s);
                      if (_minutes == null || !fits.contains(_minutes)) {
                        _minutes = fits.firstOrNull;
                      }
                    });
                    _requote();
                  },
                ),
            ],
          ),
        ],
        if (_start != null) ...[
          const SizedBox(height: Space.x4),
          Text('How long', style: text.titleSmall),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final m in durations)
                ChoiceChip(
                  key: Key('venue-duration-$m'),
                  label: Text(
                    '${_hours(m)} · until ${_clock(_start!.add(Duration(minutes: m)), zone)}',
                  ),
                  selected: _minutes == m,
                  onSelected: (_) {
                    setState(() => _minutes = m);
                    _requote();
                  },
                ),
            ],
          ),
          if (phoneZone.isNotEmpty &&
              MarketTime.inZone(_start!, zone).hour != _start!.toLocal().hour)
            Padding(
              padding: const EdgeInsets.only(top: Space.x2),
              child: Text(
                'On your phone\'s clock that starts at ${DateFormat('HH:mm').format(_start!.toLocal())}.',
                style: text.bodySmall,
              ),
            ),
        ],
        if (_quote != null)
          FutureBuilder<VenueQuote>(
            future: _quote,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(Space.x5),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final error = snapshot.error;
              if (error != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: Space.x4),
                  child: Text(
                    error is ApiFailure ? slotProblem(error) : '$error',
                    style: text.bodyLarge,
                  ),
                );
              }
              final quote = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Space.x5),
                  QuoteCard(quote),
                  const SizedBox(height: Space.x3),
                  if (venue.cancellationPolicy.isNotEmpty) ...[
                    Text('Cancelling', style: text.titleSmall),
                    Text(
                      '${venue.cancellationPolicy} Free cancellation until '
                      '${venue.freeCancellationHours} hours before the start.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: Space.x3),
                  ],
                  TextField(
                    key: const Key('venue-attendees'),
                    controller: _attendees,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'How many people (optional)',
                    ),
                  ),
                  const SizedBox(height: Space.x3),
                  TextField(
                    key: const Key('venue-message'),
                    controller: _message,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message to the host (optional)',
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('venue-consent'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _consent,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                    title: const Text(
                      'Share my name and email with the host for this request, as the privacy notice explains.',
                    ),
                  ),
                  if (_failure != null) FailureBox(_failure!),
                  const SizedBox(height: Space.x3),
                  FilledButton(
                    key: const Key('venue-send'),
                    onPressed: _busy || !_consent ? null : () => _send(quote),
                    child: const Text('Send booking request'),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// The itemised estimate, in the order people read a bill: the rate and
/// fixed fees, the subtotal, percentage fees such as VAT, the total, then
/// the deposit and the no-payment notice.
class QuoteCard extends StatelessWidget {
  const QuoteCard(this.quote, {super.key});

  final VenueQuote quote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    Widget row(String label, String amount, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? text.titleMedium : text.bodyLarge,
            ),
          ),
          Text(
            '${quote.currency} $amount',
            style: strong ? text.titleMedium : text.bodyLarge,
          ),
        ],
      ),
    );
    return Container(
      key: const Key('venue-quote'),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Estimate', style: text.titleMedium),
          Text(
            '${MarketTime.format(quote.start, quote.timeZone)} · ${_hours(quote.durationMinutes)}',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.x2),
          for (final l in quote.beforeSubtotal) row(l.label, l.amount),
          if (quote.onSubtotal.isNotEmpty) ...[
            const Divider(),
            row('Subtotal', quote.subtotal),
            for (final l in quote.onSubtotal) row(l.label, l.amount),
          ],
          const Divider(),
          row('Total', quote.total, strong: true),
          if (quote.deposit != null)
            row('Deposit, ${quote.depositNote}', quote.deposit!),
          const SizedBox(height: Space.x2),
          Text(quote.notice, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent(this.booking);

  final VenueBooking booking;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        const SizedBox(height: Space.x6),
        Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: context.colors.primary,
        ),
        const SizedBox(height: Space.x3),
        Semantics(
          header: true,
          child: Text('Request sent', style: text.headlineSmall),
        ),
        const SizedBox(height: Space.x2),
        Text(
          'Reference ${booking.reference}. The host confirms or declines it, and you are told by email. '
          'Nothing is booked or paid until then.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: Space.x6),
        FilledButton(
          onPressed: () => context.go(Routes.activity),
          child: const Text('See it in Activity'),
        ),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard(this.booking, {required this.onTap, this.host = false});

  final VenueBooking booking;
  final VoidCallback onTap;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = booking;
    final when =
        '${MarketTime.format(b.start, b.timeZone)} to ${_clock(b.end, b.timeZone)}';
    return BrandCard(
      key: Key('venue-booking-${b.id}'),
      onTap: onTap,
      emphasised: host && b.actions.contains('confirm'),
      semanticLabel: '${b.listingTitle}. ${b.statusLabel}. $when',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    host ? (b.customerName ?? 'Customer') : b.listingTitle,
                    style: text.titleMedium,
                  ),
                ),
                const SizedBox(width: Space.x2),
                AppBadge(b.statusLabel, tone: _tone(b.status)),
              ],
            ),
            if (host) Text(b.listingTitle, style: text.bodyMedium),
            Text(when, style: text.bodyMedium),
            Text(
              '${b.reference} · ${b.quote.currency} ${b.quote.total}',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Hourly Bookings" in Activity.
class MyHourlyBookingsView extends StatefulWidget {
  const MyHourlyBookingsView({super.key});

  @override
  State<MyHourlyBookingsView> createState() => _MyHourlyBookingsViewState();
}

class _MyHourlyBookingsViewState extends State<MyHourlyBookingsView> {
  Future<List<VenueBooking>>? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _list ??= AppScope.of(context).venues.mine();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).venues.mine();
    setState(() {
      _list = next;
    });
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<VenueBooking>>(
    future: _list!,
    onRetry: _reload,
    builder: (context, items) => items.isEmpty
        ? const MessageView(
            icon: Icons.meeting_room_outlined,
            title: 'No hourly bookings',
            body: 'Showrooms and venues that take hourly bookings show "Book by the hour" on their page.',
          )
        : RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                for (final b in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: _BookingCard(
                      b,
                      onTap: () async {
                        await context.push(Routes.myVenueBooking(b.id));
                        if (mounted) _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
  );
}

/// The host's hourly booking requests, soonest first.
class HostedVenueBookingsScreen extends StatefulWidget {
  const HostedVenueBookingsScreen({super.key, required this.books});

  final List<ContactBook> books;

  @override
  State<HostedVenueBookingsScreen> createState() =>
      _HostedVenueBookingsScreenState();
}

class _HostedVenueBookingsScreenState extends State<HostedVenueBookingsScreen> {
  late ContactBook? _book = widget.books.firstOrNull;
  Future<List<VenueBooking>>? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_list == null) _load();
  }

  void _load() {
    final book = _book;
    if (book == null) return;
    final next = AppScope.of(context).venues
        .hosted(book.id, personal: book.personal);
    setState(() {
      _list = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final book = _book;
    return Scaffold(
      appBar: AppBar(title: const Text('Hourly bookings')),
      body: book == null
          ? const MessageView(
              icon: Icons.lock_outline,
              title: 'No venue bookings on this account',
              body: 'Hourly bookings go to the hosts of showrooms and venues.',
            )
          : FutureBuilder<List<VenueBooking>>(
              future: _list,
              builder: (context, snapshot) {
                final error = snapshot.error;
                return ListView(
                  padding: const EdgeInsets.all(Space.x4),
                  children: [
                    if (widget.books.length > 1) ...[
                      SearchableSelectField<String>(
                        value: book.id,
                        label: 'Agency or business',
                        options: [
                          for (final b in widget.books)
                            SelectOption(b.id, b.name),
                        ],
                        onChanged: (id) {
                          _book = widget.books.firstWhere((b) => b.id == id);
                          _load();
                        },
                      ),
                      const SizedBox(height: Space.x3),
                    ],
                    if (snapshot.connectionState != ConnectionState.done)
                      const Center(child: CircularProgressIndicator())
                    else if (error != null)
                      Text(
                        error is ApiFailure && error.status == 404
                            ? 'This account takes no hourly bookings here.'
                            : 'We could not load the bookings.',
                        style: text.titleMedium,
                      )
                    else if (snapshot.data!.isEmpty)
                      Text('No booking requests.', style: text.bodyLarge)
                    else
                      for (final b in snapshot.data!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.x3),
                          child: _BookingCard(
                            b,
                            host: true,
                            onTap: () async {
                              await context.push(
                                Routes.hostedVenueBooking(book.id, b.id),
                                extra: book,
                              );
                              if (mounted) _load();
                            },
                          ),
                        ),
                    const SizedBox(height: Space.x4),
                    Text(
                      'Rates, opening hours and fees are set on the website; proposing another time is there too.',
                      style: text.bodySmall,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// One hourly booking, for its customer or its host ([book] set).
class VenueBookingScreen extends StatefulWidget {
  const VenueBookingScreen({super.key, required this.id, this.book});

  final String id;
  final ContactBook? book;

  @override
  State<VenueBookingScreen> createState() => _VenueBookingScreenState();
}

class _VenueBookingScreenState extends State<VenueBookingScreen> {
  Future<VenueBooking>? _loading;
  VenueBooking? _booking;
  ApiFailure? _failure;
  bool _busy = false;

  bool get _host => widget.book != null;
  VenueRepository get _repo => AppScope.of(context).venues;

  Future<VenueBooking> _get() {
    final book = widget.book;
    final load = book == null
        ? _repo.myBooking(widget.id)
        : _repo.hostedBooking(book.id, widget.id, personal: book.personal);
    return load.then((b) => _booking = b);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<void> _run(Future<VenueBooking> Function() action, String done) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final b = await action();
      if (!mounted) return;
      setState(() => _booking = b);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _failure = failure.withMessage(slotProblem(failure)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hostAction(String action) async {
    final book = widget.book!;
    String? reason;
    if (action == 'decline' || action == 'cancel') {
      reason = await askForText(
        context,
        title: action == 'decline'
            ? 'Decline this request?'
            : 'Cancel this booking?',
        label: 'Reason (sent to the customer)',
        action: action == 'decline' ? 'Decline' : 'Cancel booking',
        required: true,
      );
      if (reason == null || !mounted) return;
    }
    await _run(
      () => _repo.hostAction(
        book.id,
        widget.id,
        action,
        personal: book.personal,
        reason: reason,
      ),
      switch (action) {
        'confirm' => 'Confirmed. The time is held for them.',
        'decline' => 'Declined.',
        'cancel' => 'Cancelled.',
        'complete' => 'Marked as completed.',
        _ => 'Marked as a no-show.',
      },
    );
  }

  Future<void> _cancelMine(VenueBooking b) async {
    final free = b.freeUntil == null || DateTime.now().isBefore(b.freeUntil!);
    final reason = await askForText(
      context,
      title: 'Cancel this booking?',
      label: free
          ? 'Reason (optional). Cancelling is free now.'
          : 'Reason (optional). The free cancellation time has passed: ${b.policy}',
      action: 'Cancel booking',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => _repo.cancelMine(widget.id, reason: reason),
      'Cancelled. The host is told.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stamp = DateFormat('d MMM y, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Hourly booking')),
      body: FutureBuilder<VenueBooking>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final b = _booking;
          if (b == null) {
            final notFound =
                snapshot.error is ApiFailure &&
                (snapshot.error as ApiFailure).status == 404;
            return MessageView(
              icon: Icons.event_busy_outlined,
              title: notFound
                  ? 'Booking not found'
                  : 'We could not load this booking',
              body: notFound
                  ? 'It is not one this account can open.'
                  : 'Check your connection and try again.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(b.listingTitle, style: text.headlineSmall),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  AppBadge(b.statusLabel, tone: _tone(b.status)),
                ],
              ),
              Text(
                '${MarketTime.format(b.start, b.timeZone)} to ${_clock(b.end, b.timeZone)} · ${b.reference}',
                style: text.bodyLarge,
              ),
              if (_host && b.customerName != null) ...[
                const SizedBox(height: Space.x2),
                Text(b.customerName!, style: text.titleMedium),
                if (b.customerEmail != null) SelectableText(b.customerEmail!),
              ],
              if (b.attendees != null) Text('${b.attendees} people'),
              if (b.message != null) ...[
                const SizedBox(height: Space.x2),
                Text(b.message!, style: text.bodyLarge),
              ],
              if (b.proposal != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: Text(
                    '${b.proposal!.by == 'HOST' ? 'The host' : 'The customer'} proposed '
                    '${MarketTime.format(b.proposal!.start, b.timeZone)} to ${_clock(b.proposal!.end, b.timeZone)}.',
                    style: text.bodyLarge,
                  ),
                ),
              if (b.declineReason != null)
                Text('Declined: ${b.declineReason}', style: text.bodyLarge),
              if (b.cancellation != null)
                Text(
                  'Cancelled by the ${b.cancellation!.by == 'HOST' ? 'host' : 'customer'}'
                  '${b.cancellation!.reason == null ? '' : ': ${b.cancellation!.reason}'}'
                  '${b.cancellation!.free ? ' (free)' : ''}',
                  style: text.bodyLarge,
                ),
              const SizedBox(height: Space.x4),
              QuoteCard(b.quote),
              if (b.policy.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                Text('Cancelling', style: text.titleSmall),
                Text(
                  '${b.policy}${b.freeUntil == null ? '' : ' Free until ${MarketTime.format(b.freeUntil!, b.timeZone)}.'}',
                  style: text.bodyMedium,
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: Space.x3),
                FailureBox(_failure!),
              ],
              const SizedBox(height: Space.x4),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  if (!_host && b.actions.contains('accept'))
                    FilledButton(
                      key: const Key('venue-accept'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _repo.acceptProposal(b.id),
                              'Accepted.',
                            ),
                      child: const Text('Accept the new time'),
                    ),
                  if (!_host && b.actions.contains('cancel'))
                    OutlinedButton(
                      key: const Key('venue-cancel'),
                      onPressed: _busy ? null : () => _cancelMine(b),
                      child: const Text('Cancel the booking'),
                    ),
                  if (_host)
                    for (final a in const [
                      'confirm',
                      'decline',
                      'complete',
                      'no_show',
                      'cancel',
                    ])
                      if (b.actions.contains(a))
                        (a == 'confirm'
                            ? FilledButton.new
                            : OutlinedButton.new)(
                          key: Key('venue-host-$a'),
                          onPressed: _busy ? null : () => _hostAction(a),
                          child: Text(switch (a) {
                            'confirm' => 'Confirm',
                            'decline' => 'Decline',
                            'complete' => 'It took place',
                            'no_show' => 'They did not come',
                            _ => 'Cancel the booking',
                          }),
                        ),
                ],
              ),
              if (b.events.isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                const SectionHeading('History'),
                const SizedBox(height: Space.x2),
                for (final e in b.events.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: Text(
                      '${e.action.replaceAll('_', ' ').toLowerCase()}'
                      '${e.reason == null ? '' : ': ${e.reason}'}\n'
                      '${stamp.format(e.at.toLocal())}${e.actorName == null ? '' : ' · ${e.actorName}'}',
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
