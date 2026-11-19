import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../analytics/analytics_tracker.dart' show AnalyticsPlacement;
import '../directory/data/business_enquiry_repository.dart';
import '../directory/data/profile.dart';
import '../enquiries/presentation/enquiry_form.dart';
import '../listings/presentation/video_tour_section.dart';
import '../listings/presentation/widgets/listing_card.dart';
import 'development.dart';

/// A project's photo: a bundled sample, or the API's.
class DevelopmentImage extends StatelessWidget {
  const DevelopmentImage(
    this.photo, {
    super.key,
    this.aspectRatio = 16 / 10,
    this.decorative = false,
  });

  final DevelopmentPhoto? photo;
  final double aspectRatio;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = this.photo;
    final fallback = ColoredBox(
      color: c.sunken,
      child: Icon(Icons.apartment_outlined, color: c.subtle, size: 40),
    );
    final ImageProvider? image = photo == null
        ? null
        : photo.asset != null
        ? ResizeImage(AssetImage(photo.asset!), width: 900)
        : photo.url != null
        ? ResizeImage(NetworkImage(photo.url!), width: 900)
        : null;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: image == null
          ? fallback
          : Image(
              image: image,
              fit: BoxFit.cover,
              semanticLabel: decorative ? null : photo!.alt,
              excludeFromSemantics: decorative,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// A project in a list: photo, name, place, status and "from" price.
class DevelopmentCard extends StatelessWidget {
  const DevelopmentCard({
    super.key,
    required this.development,
    required this.onTap,
  });

  final Development development;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = development;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('development-${d.market}-${d.slug}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DevelopmentImage(d.cover, decorative: true),
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [
                      if (d.status != null) AppBadge(d.status!.label),
                      if (d.completion != null)
                        AppBadge('Completion ${d.completion}'),
                    ],
                  ),
                  const SizedBox(height: Space.x2),
                  Text(d.name, style: text.titleLarge),
                  Text(
                    d.place,
                    style: text.bodyMedium?.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: Space.x2),
                  Text(d.priceLabel, style: text.titleMedium),
                  if (d.unitTypeCount > 0)
                    Text(
                      d.unitTypeCount == 1
                          ? '1 unit type'
                          : '${d.unitTypeCount} unit types',
                      style: text.bodySmall,
                    ),
                  const SizedBox(height: Space.x1),
                  Text(
                    'By ${d.developer.name}'
                    '${d.developer.verified ? ' (verified)' : ''}',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// New developments: published projects of verified developers.
class DevelopmentsScreen extends StatefulWidget {
  const DevelopmentsScreen({super.key});

  @override
  State<DevelopmentsScreen> createState() => _DevelopmentsScreenState();
}

class _DevelopmentsScreenState extends State<DevelopmentsScreen> {
  final _query = TextEditingController();
  final _items = <Development>[];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  ApiFailure? _failure;

  DevelopmentsRepository get _repo => AppScope.of(context).developments;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == 0 && !_loading) unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.list(
        query: _query.text,
        page: reset ? 1 : _page + 1,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page = page.page;
        _totalPages = page.totalPages;
      });
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New developments')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(
              'Estates, apartments and stands from verified developers. '
              'Ask a developer through an enquiry.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.x3),
            TextField(
              key: const Key('developments-search'),
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Search by name or area',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _load(reset: true),
            ),
            const SizedBox(height: Space.x4),
            if (_failure != null)
              _Problem(
                message: _failure!.message,
                onRetry: () => _load(reset: _items.isEmpty),
              ),
            if (_items.isEmpty && !_loading && _failure == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x6),
                child: Text(
                  _query.text.trim().isEmpty
                      ? 'No projects are listed yet.'
                      : 'No projects match "${_query.text.trim()}".',
                  key: const Key('developments-empty'),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
              ),
            for (final d in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: DevelopmentCard(
                  development: d,
                  onTap: () =>
                      context.push(Routes.development(d.market, d.slug)),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(Space.x4),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading projects',
                  ),
                ),
              )
            else if (_page < _totalPages && _items.isNotEmpty)
              OutlinedButton(
                key: const Key('developments-more'),
                onPressed: _load,
                child: const Text('Show more projects'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.x4),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// A project's page: photos, the video tour, phases and unit types,
/// investment highlights, amenities and the listings for sale in it.
class DevelopmentScreen extends StatefulWidget {
  const DevelopmentScreen({
    super.key,
    required this.market,
    required this.slug,
    @visibleForTesting this.posterImage,
  });

  final String market;
  final String slug;
  final ImageProvider? posterImage;

  @override
  State<DevelopmentScreen> createState() => _DevelopmentScreenState();
}

class _DevelopmentScreenState extends State<DevelopmentScreen> {
  Future<Development>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).developments
        .get(widget.market, widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Development>(
      future: _loading,
      builder: (context, snapshot) {
        final d = snapshot.data;
        if (snapshot.hasError) {
          final failure = snapshot.error;
          return Scaffold(
            appBar: AppBar(),
            body: _Problem(
              message: failure is ApiFailure
                  ? failure.message
                  : 'This project could not be loaded.',
              onRetry: () => setState(
                () =>
                    _loading = AppScope.of(context).developments
                        .get(widget.market, widget.slug),
              ),
            ),
          );
        }
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading the project',
              ),
            ),
          );
        }
        return _DevelopmentPage(
          development: d,
          posterImage: widget.posterImage,
        );
      },
    );
  }
}

class _DevelopmentPage extends StatelessWidget {
  const _DevelopmentPage({required this.development, this.posterImage});

  final Development development;
  final ImageProvider? posterImage;

  @override
  Widget build(BuildContext context) {
    final d = development;
    final detail = d.detail!;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final directory = AppScope.of(context).directory;
    final profile = directory.find(DirectoryKind.developers, d.developer.slug);
    void enquire([UnitType? unit]) => context.push(
      Routes.developmentEnquiry(d.market, d.slug, unitTypeId: unit?.id),
    );
    const gap = SizedBox(height: Space.x6);

    return Scaffold(
      appBar: AppBar(title: Text(d.name)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x2,
            Space.x4,
            Space.x3,
          ),
          child: FilledButton(
            key: const Key('development-enquire'),
            onPressed: enquire,
            child: Text('Send an enquiry to ${d.developer.name}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x6),
        children: [
          if (detail.photos.isNotEmpty)
            _Gallery(photos: detail.photos)
          else
            DevelopmentImage(d.cover),
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x1,
                  children: [
                    if (d.status != null) AppBadge(d.status!.label),
                    if (d.completion != null)
                      AppBadge('Completion ${d.completion}'),
                  ],
                ),
                const SizedBox(height: Space.x2),
                Semantics(
                  header: true,
                  child: Text(d.name, style: text.headlineSmall),
                ),
                Text(d.place, style: text.bodyLarge?.copyWith(color: c.muted)),
                const SizedBox(height: Space.x2),
                Text(d.priceLabel, style: text.titleLarge),
                const SizedBox(height: Space.x2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: profile == null
                      ? Text(
                          'By ${d.developer.name}'
                          '${d.developer.verified ? ' (verified)' : ''}',
                          style: text.bodyMedium,
                        )
                      : TextButton.icon(
                          key: const Key('development-developer'),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () =>
                              context.push(Routes.profile(profile)),
                          icon: const Icon(Icons.business_outlined),
                          label: Text(
                            'By ${d.developer.name}'
                            '${d.developer.verified ? ' (verified)' : ''}',
                          ),
                        ),
                ),
                if (d.summary.isNotEmpty) ...[
                  const SizedBox(height: Space.x3),
                  Text(d.summary, style: text.bodyLarge),
                ],
                if (detail.description.isNotEmpty) ...[
                  gap,
                  const SectionHeading('About the project'),
                  const SizedBox(height: Space.x3),
                  Text(
                    detail.description,
                    style: text.bodyLarge?.copyWith(color: c.muted),
                  ),
                ],
                gap,
                if (detail.video != null)
                  VideoTourSection(
                    slug: d.slug,
                    title: d.name,
                    tour: Future.value(detail.video),
                    posterImage: posterImage,
                  ),
                const SectionHeading('Phases and unit types'),
                for (final phase in detail.phases)
                  _PhaseSection(phase: phase, onAsk: enquire),
                if (detail.highlights.items.isNotEmpty) ...[
                  gap,
                  _Highlights(highlights: detail.highlights),
                ],
                if (detail.amenities.isNotEmpty) ...[
                  gap,
                  const SectionHeading('Amenities'),
                  const SizedBox(height: Space.x3),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x2,
                    children: [for (final a in detail.amenities) AppBadge(a)],
                  ),
                ],
                if (detail.availableUnits.isNotEmpty) ...[
                  gap,
                  const SectionHeading('For sale now'),
                  const SizedBox(height: Space.x3),
                  for (final unit in detail.availableUnits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (unit.unitTypeId != null &&
                              detail.unitType(unit.unitTypeId!) != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.x1),
                              child: Text(
                                detail.unitType(unit.unitTypeId!)!.name,
                                style: text.labelLarge,
                              ),
                            ),
                          ListingCard(
                            listing: unit.listing,
                            heroScope: 'development-${d.slug}',
                            placement: AnalyticsPlacement.rail,
                            onTap: () => context.push(
                              Routes.listing(
                                unit.listing.slug,
                                heroScope: 'development-${d.slug}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                gap,
                Text(
                  'Contact is through RightProperty365 only: your enquiry goes '
                  'to the developer, who replies to you.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.photos});

  final List<DevelopmentPhoto> photos;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: PageView.builder(
            key: const Key('development-photos'),
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => DevelopmentImage(photos[i]),
          ),
        ),
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Space.x1),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Photo ${_index + 1} of ${photos.length}. Swipe for more.',
                style: text.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({required this.phase, required this.onAsk});

  final Phase phase;
  final void Function(UnitType unit) onAsk;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(phase.name, style: text.titleMedium),
          ),
          Text(
            [
              if (phase.status != null) phase.status!.label,
              if (phase.completion != null) 'completion ${phase.completion}',
            ].join(', '),
            style: text.bodySmall,
          ),
          for (final unit in phase.unitTypes)
            Card(
              key: Key('unit-type-${unit.id}'),
              margin: const EdgeInsets.only(top: Space.x2),
              child: Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unit.name, style: text.titleSmall),
                    if (unit.facts.isNotEmpty)
                      Text(
                        unit.facts,
                        style: text.bodyMedium?.copyWith(color: c.muted),
                      ),
                    const SizedBox(height: Space.x1),
                    Text(unit.price.label, style: text.titleMedium),
                    if (unit.availability != null)
                      Text(unit.availability!, style: text.bodySmall),
                    if (unit.availableListings > 0)
                      Text(
                        unit.availableListings == 1
                            ? '1 listed for sale below'
                            : '${unit.availableListings} listed for sale below',
                        style: text.bodySmall,
                      ),
                    TextButton(
                      key: Key('unit-ask-${unit.id}'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => onAsk(unit),
                      child: Text('Ask about the ${unit.name}'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.highlights});

  final InvestmentHighlights highlights;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Container(
      key: const Key('development-highlights'),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Investment highlights'),
          Text(
            'Stated by the developer, not advice',
            style: text.labelLarge?.copyWith(color: c.warning),
          ),
          const SizedBox(height: Space.x3),
          for (final item in highlights.items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: text.bodySmall),
                  Text(item.value, style: text.titleMedium),
                ],
              ),
            ),
          Text(highlights.disclaimer, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// The enquiry about a project, or one of its unit types. It reaches the
/// developer through POST /v1/business-enquiries; no contact details are
/// ever shown here.
class DevelopmentEnquiryScreen extends StatefulWidget {
  const DevelopmentEnquiryScreen({
    super.key,
    required this.market,
    required this.slug,
    this.unitTypeId,
  });

  final String market;
  final String slug;
  final String? unitTypeId;

  @override
  State<DevelopmentEnquiryScreen> createState() =>
      _DevelopmentEnquiryScreenState();
}

class _DevelopmentEnquiryScreenState extends State<DevelopmentEnquiryScreen> {
  Future<Development>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= AppScope.of(context).developments
        .get(widget.market, widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Send an enquiry')),
      body: FutureBuilder<Development>(
        future: _loading,
        builder: (context, snapshot) {
          final d = snapshot.data;
          if (snapshot.hasError) {
            final failure = snapshot.error;
            return _Problem(
              message: failure is ApiFailure
                  ? failure.message
                  : 'This project could not be loaded.',
              onRetry: () => setState(
                () => _loading = services.developments.get(
                  widget.market,
                  widget.slug,
                ),
              ),
            );
          }
          if (d == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final unit = widget.unitTypeId == null
              ? null
              : d.detail?.unitType(widget.unitTypeId!);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x4),
            child: EnquiryForm(
              title: unit == null ? d.name : '${unit.name}, ${d.name}',
              subtitle: '${d.developer.name} · ${d.place}',
              recipientName: d.developer.name,
              defaultMessage: unit == null
                  ? 'Hello, I would like to know more about ${d.name}.'
                  : 'Hello, is the ${unit.name} at ${d.name} still available?',
              submitLabel: 'Send enquiry',
              onSubmit: (input) async {
                final receipt = await services.businessEnquiries.submit(
                  BusinessEnquiryDraft(
                    development: (
                      market: d.market,
                      slug: d.slug,
                      unitTypeId: unit?.id,
                    ),
                    message: input.message,
                    contactMethod: input.contactMethod,
                    contact: input.contact,
                    consentAccepted: input.consentAccepted,
                    privacyVersion: AppConfig.privacyNoticeVersion,
                  ),
                );
                await services.activity.recordRequest(
                  receipt: receipt,
                  title: unit == null
                      ? 'Enquiry about ${d.name}'
                      : 'Enquiry about the ${unit.name}, ${d.name}',
                  recipient: d.developer.name,
                  route: Routes.development(d.market, d.slug),
                );
                return receipt;
              },
            ),
          );
        },
      ),
    );
  }
}

/// A developer's public projects, on their directory profile.
class DeveloperProjectsSection extends StatefulWidget {
  const DeveloperProjectsSection({super.key, required this.slug});

  final String slug;

  @override
  State<DeveloperProjectsSection> createState() =>
      _DeveloperProjectsSectionState();
}

class _DeveloperProjectsSectionState extends State<DeveloperProjectsSection> {
  Future<List<Development>>? _projects;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _projects ??= AppScope.of(context).developments.ofDeveloper(widget.slug);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Development>>(
    future: _projects,
    builder: (context, snapshot) {
      final projects = snapshot.data ?? const [];
      if (projects.isEmpty) return const SizedBox.shrink();
      return Column(
        key: const Key('developer-projects'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.x6),
          const SectionHeading('Projects'),
          const SizedBox(height: Space.x3),
          for (final d in projects)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x4),
              child: DevelopmentCard(
                development: d,
                onTap: () => context.push(Routes.development(d.market, d.slug)),
              ),
            ),
        ],
      );
    },
  );
}
