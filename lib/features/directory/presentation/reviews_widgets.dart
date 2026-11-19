import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/searchable_select.dart';
import '../../appointments/appointment_screens.dart' show askForText;
import '../../auth/presentation/auth_screens.dart' show FailureBox;
import '../../contacts/contacts_repository.dart' show ContactBook;
import '../../contacts/contacts_screens.dart' show contactBooks;
import '../../workspace/workspace.dart';
import '../data/reviews_repository.dart';

final _day = DateFormat('d MMM y');

/// Five stars, read as "4 out of 5".
class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 18});

  /// 0 to 5, halves shown as a half star.
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '${value % 1 == 0 ? value.toInt() : value} out of 5 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              value >= i
                  ? Icons.star
                  : value >= i - 0.5
                  ? Icons.star_half
                  : Icons.star_border,
              size: size,
              color: c.accent,
            ),
        ],
      ),
    );
  }
}

String _basisLabel(String? kind) => switch (kind) {
  'MAINTENANCE' => 'After a maintenance job',
  'ENQUIRY' => 'After an enquiry',
  _ => '',
};

class ReviewCard extends StatelessWidget {
  const ReviewCard(this.review, {super.key, this.actions = const []});

  final Review review;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final r = review;
    final when = r.publishedAt ?? r.createdAt;
    return Container(
      key: Key('review-${r.id}'),
      margin: const EdgeInsets.only(bottom: Space.x3),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerTheme.color!),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Stars(r.rating.toDouble()),
              Text(r.reviewerName, style: text.titleSmall),
            ],
          ),
          if (r.profileName != null && r.reviewerName != r.profileName)
            Text('Of ${r.profileName}', style: text.bodySmall),
          Text(
            [
              _basisLabel(r.basisKind),
              ?r.basisReference,
              if (when != null) _day.format(when),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.x2),
          Text(r.text, style: text.bodyLarge),
          if (r.statusLabel != null && r.status != 'PUBLISHED') ...[
            const SizedBox(height: Space.x2),
            AppBadge(
              r.statusLabel!,
              tone: r.status == 'PENDING'
                  ? BadgeTone.primary
                  : BadgeTone.neutral,
            ),
            if ((r.moderationReason ?? '').isNotEmpty)
              Text('Moderator: ${r.moderationReason}', style: text.bodySmall),
          ],
          if (r.reply != null)
            Container(
              margin: const EdgeInsets.only(top: Space.x3),
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: c.sunken,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply${r.profileName == null ? '' : ' from ${r.profileName}'}',
                    style: text.titleSmall,
                  ),
                  Text(r.reply!.text, style: text.bodyMedium),
                  Text(_day.format(r.reply!.repliedAt), style: text.bodySmall),
                ],
              ),
            ),
          if (actions.isNotEmpty) Wrap(spacing: Space.x2, children: actions),
        ],
      ),
    );
  }
}

/// A service provider's rating and published reviews, with Report and
/// Write a review for people who are signed in.
class ProfileReviewsSection extends StatefulWidget {
  const ProfileReviewsSection({
    super.key,
    required this.kind,
    required this.slug,
    required this.name,
  });

  final String kind;
  final String slug;
  final String name;

  @override
  State<ProfileReviewsSection> createState() => _ProfileReviewsSectionState();
}

class _ProfileReviewsSectionState extends State<ProfileReviewsSection> {
  Future<ProfileReviews>? _loading;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<ProfileReviews> _get() =>
      AppScope.of(context).reviews.published(widget.kind, widget.slug);

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _report(Review r) async {
    final reviews = AppScope.of(context).reviews;
    final reason = await askForText(
      context,
      title: 'Report this review',
      label: 'What is wrong with it',
      action: 'Report',
      required: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await reviews.report(r.id, reason);
      _say('Reported. A moderator will look at it; it stays up meanwhile.');
    } on ApiFailure catch (failure) {
      _say(failure.message);
    }
  }

  /// The person's own enquiries, and the jobs of each book they work in.
  Future<void> _write() async {
    final services = AppScope.of(context);
    setState(() => _checking = true);
    final found = <Eligibility>[];
    try {
      List<ContactBook> books = const [];
      try {
        books = contactBooks(
          await services.workspace.load(),
          services.auth.user,
        );
      } on ApiFailure {
        // No work area: the person's own enquiries only.
      }
      final names = {for (final b in books) b.id: b.name};
      final checks = <Future<Eligibility?>>[
        services.reviews
            .eligibility(widget.kind, widget.slug)
            .then<Eligibility?>((e) => e)
            .catchError((Object _) => null),
        for (final b in books)
          services.reviews
              .eligibility(widget.kind, widget.slug, book: b.id)
              .then<Eligibility?>((e) => e)
              .catchError((Object _) => null),
      ];
      found.addAll([for (final e in await Future.wait(checks)) ?e]);
      if (!mounted) return;
      final bases = [for (final e in found) ...e.bases];
      if (bases.isNotEmpty) {
        final written = await Navigator.of(context).push<Review>(
          MaterialPageRoute(
            builder: (_) => WriteReviewScreen(
              profileId: found.first.profileId,
              providerName: widget.name,
              bases: bases,
              bookNames: names,
            ),
          ),
        );
        if (written != null) {
          _say('Thank you. Your review is awaiting moderation.');
        }
        return;
      }
      final upcoming = [for (final e in found) ...e.upcoming];
      final reviewed = found.fold(0, (n, e) => n + e.reviewedCount);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not yet'),
          content: Text(
            [
              if (found.isNotEmpty && !found.first.reviewable)
                'Your own organisation cannot be reviewed.'
              else if (upcoming.isEmpty && reviewed == 0)
                'A review can be written after ${widget.name} has finished a '
                    'maintenance job for you, or replied to an enquiry you '
                    'sent at least 14 days ago.',
              for (final u in upcoming)
                '${u.basis.label}: ${switch (u.reason) {
                  'TOO_RECENT' => 'you can review it from ${u.eligibleFrom == null ? 'later' : _day.format(u.eligibleFrom!)}',
                  'NOT_REPLIED' => 'once ${widget.name} marks it replied',
                  'NOT_COMPLETED' => 'once the job is resolved',
                  _ => 'not yet',
                }}.',
              if (reviewed > 0)
                'You have already reviewed '
                    '${reviewed == 1 ? 'one of them' : '$reviewed of them'}.',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final services = AppScope.of(context);
    return FutureBuilder<ProfileReviews>(
      future: _loading,
      builder: (context, snapshot) {
        final data = snapshot.data;
        // A profile the API does not have (sample data) shows no section.
        if (snapshot.hasError) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: services.auth,
          builder: (context, _) {
            final signedIn = services.auth.signedIn;
            return Column(
              key: const Key('profile-reviews'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.x6),
                const SectionHeading('Reviews'),
                const SizedBox(height: Space.x3),
                if (data == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (data.rating.count == 0)
                    Text('No reviews yet.', style: text.bodyLarge)
                  else
                    Wrap(
                      spacing: Space.x2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Stars(
                          double.tryParse(data.rating.average ?? '') ?? 0,
                          size: 22,
                        ),
                        Text(
                          '${data.rating.average} out of 5 from '
                          '${data.rating.count} ${data.rating.count == 1 ? 'review' : 'reviews'}',
                          key: const Key('profile-rating'),
                          style: text.titleSmall,
                        ),
                      ],
                    ),
                  const SizedBox(height: Space.x3),
                  for (final r in data.items)
                    ReviewCard(
                      r,
                      actions: [
                        if (signedIn)
                          TextButton(
                            key: Key('report-review-${r.id}'),
                            onPressed: () => _report(r),
                            child: const Text('Report'),
                          ),
                      ],
                    ),
                  Text(
                    'Reviews come from customers with a finished job or a '
                    'replied enquiry, and are checked before they appear.',
                    style: text.bodySmall,
                  ),
                  if (signedIn)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('write-review'),
                        onPressed: _checking ? null : _write,
                        icon: const Icon(Icons.rate_review_outlined),
                        label: Text(_checking ? 'Checking…' : 'Write a review'),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// A rating and text on one finished job or replied enquiry.
class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({
    super.key,
    required this.profileId,
    required this.providerName,
    required this.bases,
    this.bookNames = const {},
  });

  final String profileId;
  final String providerName;
  final List<ReviewBasis> bases;
  final Map<String, String> bookNames;

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  late ReviewBasis? _basis = widget.bases.length == 1
      ? widget.bases.single
      : null;
  int _rating = 0;
  String? _ratingProblem;
  bool _saving = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _label(ReviewBasis b) => b.book == null
      ? 'Your ${b.label}'
      : '${widget.bookNames[b.book] ?? 'Your organisation'}: ${b.label}';

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    setState(
      () => _ratingProblem = _rating == 0 ? 'Choose 1 to 5 stars.' : null,
    );
    if (!valid || _rating == 0) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final review = await AppScope.of(context).reviews.write(
        profileId: widget.profileId,
        basis: _basis!,
        rating: _rating,
        text: _text.text,
      );
      if (mounted) Navigator.of(context).pop(review);
    } on ApiFailure catch (failure) {
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text('Review ${widget.providerName}')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            SearchableSelectField<String>(
              key: const Key('review-basis'),
              label: 'What you are reviewing',
              value: _basis?.id,
              options: [
                for (final b in widget.bases) SelectOption(b.id, _label(b)),
              ],
              onChanged: (id) => setState(
                () => _basis = widget.bases.firstWhere((b) => b.id == id),
              ),
              validator: (v) => v == null ? 'Choose the job or enquiry.' : null,
            ),
            const SizedBox(height: Space.x4),
            Text('Your rating', style: text.titleSmall),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: Key('review-star-$i'),
                    tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                    isSelected: _rating >= i,
                    icon: Icon(
                      _rating >= i ? Icons.star : Icons.star_border,
                      color: c.accent,
                      size: 32,
                    ),
                    onPressed: () => setState(() {
                      _rating = i;
                      _ratingProblem = null;
                    }),
                  ),
              ],
            ),
            if (_ratingProblem != null)
              Text(
                _ratingProblem!,
                style: text.bodySmall?.copyWith(color: c.danger),
              ),
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const Key('review-text'),
              controller: _text,
              maxLength: 2000,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Your review',
                helperText:
                    'At least 20 characters. Shown with your first '
                    'name and initial, or your organisation\'s name.',
                helperMaxLines: 3,
              ),
              validator: (v) => (v ?? '').trim().length < 20
                  ? 'Write at least 20 characters.'
                  : null,
            ),
            Text(
              'Reviews are checked before they appear.',
              style: text.bodySmall,
            ),
            if (_failure != null) ...[
              const SizedBox(height: Space.x3),
              FailureBox(_failure!),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('review-send'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Sending…' : 'Send the review'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reviews the person wrote (and their organisations), and, for a service
/// provider's members, the reviews their business received, with replies.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, this.tab});

  /// `received` to open on the business's reviews.
  final String? tab;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  Future<({List<ContactBook> books, List<WorkOrganisation> providers})>? _work;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _work ??= _load();
  }

  Future<({List<ContactBook> books, List<WorkOrganisation> providers})>
  _load() async {
    final services = AppScope.of(context);
    try {
      final work = await services.workspace.load();
      return (
        books: contactBooks(work, services.auth.user),
        providers: [
          for (final o in work.organisations)
            if (o.kind == 'SERVICE_PROVIDER') o,
        ],
      );
    } on ApiFailure {
      return (
        books: const <ContactBook>[],
        providers: const <WorkOrganisation>[],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _work,
      builder: (context, snapshot) {
        final work = snapshot.data;
        if (work == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reviews')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final provider = work.providers.isNotEmpty;
        return DefaultTabController(
          length: provider ? 2 : 1,
          initialIndex: provider && widget.tab == 'received' ? 1 : 0,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Reviews'),
              bottom: provider
                  ? const TabBar(
                      tabs: [
                        Tab(text: 'Written'),
                        Tab(text: 'Of your business'),
                      ],
                    )
                  : null,
            ),
            body: provider
                ? TabBarView(
                    children: [
                      _WrittenView(books: work.books),
                      _ReceivedView(providers: work.providers),
                    ],
                  )
                : _WrittenView(books: work.books),
          ),
        );
      },
    );
  }
}

class _WrittenView extends StatefulWidget {
  const _WrittenView({required this.books});

  final List<ContactBook> books;

  @override
  State<_WrittenView> createState() => _WrittenViewState();
}

class _WrittenViewState extends State<_WrittenView> {
  Future<List<({Review review, String? book})>>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<List<({Review review, String? book})>> _get() async {
    final reviews = AppScope.of(context).reviews;
    final lists = await Future.wait([
      reviews.written().then(
        (l) => [for (final r in l) (review: r, book: null as String?)],
      ),
      for (final b in widget.books)
        reviews
            .written(book: b.id)
            .then(
              (l) => [for (final r in l) (review: r, book: b.id as String?)],
            )
            .catchError((Object _) => <({Review review, String? book})>[]),
    ]);
    return [for (final l in lists) ...l]..sort(
      (a, b) => (b.review.createdAt ?? DateTime(0)).compareTo(
        a.review.createdAt ?? DateTime(0),
      ),
    );
  }

  Future<void> _delete(Review r, String? book) async {
    final reviews = AppScope.of(context).reviews;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this review?'),
        content: const Text(
          'It is removed for good, from the profile too if it was published.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('review-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await reviews.delete(r.id, book: book);
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
    if (mounted) {
      setState(() {
        _loading = _get();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView(
    future: _loading!,
    onRetry: () => setState(() {
      _loading = _get();
    }),
    builder: (context, items) => items.isEmpty
        ? const MessageView(
            icon: Icons.rate_review_outlined,
            title: 'No reviews written',
            body:
                'Review a service provider from their profile after a '
                'finished job or a replied enquiry.',
          )
        : ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              for (final e in items)
                ReviewCard(
                  e.review,
                  actions: [
                    if (e.review.canDelete)
                      TextButton(
                        key: Key('review-delete-${e.review.id}'),
                        onPressed: () => _delete(e.review, e.book),
                        child: const Text('Delete'),
                      ),
                  ],
                ),
            ],
          ),
  );
}

class _ReceivedView extends StatefulWidget {
  const _ReceivedView({required this.providers});

  final List<WorkOrganisation> providers;

  @override
  State<_ReceivedView> createState() => _ReceivedViewState();
}

class _ReceivedViewState extends State<_ReceivedView> {
  Future<List<({Review review, String book, bool canReply})>>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _get();
  }

  Future<List<({Review review, String book, bool canReply})>> _get() async {
    final reviews = AppScope.of(context).reviews;
    final lists = await Future.wait([
      for (final o in widget.providers)
        reviews
            .received(o.id)
            .then(
              (r) => [
                for (final i in r.items)
                  (review: i, book: o.id, canReply: r.canReply),
              ],
            ),
    ]);
    return [for (final l in lists) ...l];
  }

  Future<void> _reply(Review r, String book) async {
    final reviews = AppScope.of(context).reviews;
    final text = await askForText(
      context,
      title: 'Reply to ${r.reviewerName}',
      label: 'Your reply, shown under the review',
      action: 'Publish the reply',
      required: true,
      maxLength: 2000,
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await reviews.reply(book, r.id, text);
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
    if (mounted) {
      setState(() {
        _loading = _get();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AsyncView(
      future: _loading!,
      onRetry: () => setState(() {
        _loading = _get();
      }),
      builder: (context, items) => items.isEmpty
          ? const MessageView(
              icon: Icons.reviews_outlined,
              title: 'No published reviews yet',
              body:
                  'Reviews of your business show here once a moderator '
                  'publishes them.',
            )
          : ListView(
              padding: const EdgeInsets.all(Space.x4),
              children: [
                Text(
                  'One reply per review, published at once. A reply can be '
                  'changed for 7 days, on the website.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.x3),
                for (final e in items)
                  ReviewCard(
                    e.review,
                    actions: [
                      if (e.canReply &&
                          e.review.canReply &&
                          e.review.reply == null)
                        TextButton(
                          key: Key('review-reply-${e.review.id}'),
                          onPressed: () => _reply(e.review, e.book),
                          child: const Text('Reply'),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
