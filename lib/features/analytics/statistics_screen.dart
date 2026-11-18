import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../workspace/workspace.dart';
import 'analytics_repository.dart';

final _number = NumberFormat.decimalPattern('en');
String _percent(double? v) =>
    v == null ? 'No views yet' : '${(v * 100).toStringAsFixed(1)}%';

const _sourceLabels = {
  'direct': 'Direct',
  'search_engine': 'Search engines',
  'social': 'Social media',
  'internal': 'Within RightProperty365',
  'email': 'Email',
  'other': 'Other',
  'unknown': 'Unknown',
};
const _deviceLabels = {
  'mobile': 'Phones',
  'tablet': 'Tablets',
  'desktop': 'Computers',
  'unknown': 'Unknown',
};

/// Listing statistics for an organisation's listings (or, for an Estate
/// Agent, the ones assigned to them): totals, a daily views chart with the
/// same figures as text, conversion with the API's definitions, sources,
/// devices and top listings. Detailed reports are on the website.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.organisations});

  final List<WorkOrganisation> organisations;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late WorkOrganisation? _organisation = widget.organisations.firstOrNull;
  String _period = '30d';
  Future<AnalyticsReport>? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _report ??= _load();
  }

  Future<AnalyticsReport> _load() {
    final organisation = _organisation;
    if (organisation == null) {
      return Future.error(
        const ApiFailure(status: 403, code: 'FORBIDDEN', message: ''),
      );
    }
    return AppScope.of(context).analyticsReports
        .organisation(organisation.id, _period);
  }

  void _reload() => setState(() {
    _report = _load();
  });

  Future<void> _openWeb(String path) =>
      AppScope.of(context).openLink(Uri.parse('${AppConfig.webBaseUrl}$path'));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Listing statistics')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          if (widget.organisations.length > 1) ...[
            SearchableSelectField<String>(
              value: _organisation?.id,
              label: 'Agency or business',
              options: [
                for (final o in widget.organisations)
                  SelectOption(o.id, o.name),
              ],
              onChanged: (id) {
                _organisation = widget.organisations.firstWhere(
                  (o) => o.id == id,
                );
                _reload();
              },
            ),
            const SizedBox(height: Space.x3),
          ],
          SegmentedButton<String>(
            key: const Key('statistics-period'),
            segments: const [
              ButtonSegment(value: '24h', label: Text('24 hours')),
              ButtonSegment(value: '7d', label: Text('7 days')),
              ButtonSegment(value: '30d', label: Text('30 days')),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              _period = s.first;
              _reload();
            },
          ),
          const SizedBox(height: Space.x4),
          FutureBuilder<AnalyticsReport>(
            future: _report,
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
              final error = snapshot.error;
              if (error != null) {
                final denied =
                    error is ApiFailure &&
                    (error.status == 403 || error.status == 404);
                return MessageView(
                  icon: denied ? Icons.lock_outline : Icons.cloud_off_outlined,
                  title: denied
                      ? 'No statistics for this account here'
                      : 'We could not load the statistics',
                  body: denied
                      ? 'Statistics are for the people who manage listings in this organisation.'
                      : 'Check your connection and try again.',
                  actionLabel: denied ? null : 'Try again',
                  onAction: denied ? null : _reload,
                );
              }
              return _Report(snapshot.data!, onOpenWeb: _openWeb);
            },
          ),
          const SizedBox(height: Space.x4),
          Text(
            'These figures are counted by RightProperty365 itself. They are not Google Analytics figures.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report(this.report, {required this.onOpenWeb});

  final AnalyticsReport report;
  final Future<void> Function(String path) onOpenWeb;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final r = report;
    final days = DateFormat('d MMM');
    final refreshed = r.refreshedAt == null
        ? 'Not counted yet'
        : 'Updated ${DateFormat('d MMM y, HH:mm').format(r.refreshedAt!.toLocal())}';

    Widget tile(String label, int value, {Key? key}) => Semantics(
      container: true,
      label: '$label: ${_number.format(value)}',
      excludeSemantics: true,
      child: Container(
        key: key,
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: c.sunken,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_number.format(value), style: text.headlineSmall),
            Text(label, style: text.bodyMedium),
          ],
        ),
      ),
    );

    final views = r.total('views');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${days.format(r.from)} to ${days.format(r.to)} · ${r.timezone.split('/').last.replaceAll('_', ' ')} days'
          '${r.assignedOnly ? ' · your assigned listings' : ''}',
          style: text.bodyMedium,
        ),
        if (r.label != null)
          Text(r.label!, style: text.bodyMedium?.copyWith(color: c.warning)),
        Text(refreshed, style: text.bodySmall),
        const SizedBox(height: Space.x4),
        if (views == 0 && r.total('impressions') == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x4),
            child: Text(
              'No views yet in this period.',
              style: text.titleMedium,
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 520 ? 3 : 2;
            final width = (box.maxWidth - Space.x2 * (columns - 1)) / columns;
            final tiles = [
              tile('Views', views, key: const Key('stat-views')),
              tile('Unique views', r.total('unique_views')),
              tile('Seen in lists', r.total('impressions')),
              tile('Contact clicks', r.total('contact_clicks')),
              tile('Enquiries', r.total('enquiries')),
              tile('Saves', r.total('saves')),
              tile('Viewing requests', r.total('viewing_requests')),
              tile('Video plays', r.total('video_plays')),
            ];
            return Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              children: [
                for (final t in tiles) SizedBox(width: width, child: t),
              ],
            );
          },
        ),
        const SizedBox(height: Space.x5),
        const SectionHeading('Conversion'),
        const SizedBox(height: Space.x2),
        Text(
          'Enquiries per view: ${_percent(r.conversion)}',
          style: text.titleMedium,
        ),
        if (r.conversionDefinition != null)
          Text(r.conversionDefinition!, style: text.bodySmall),
        const SizedBox(height: Space.x2),
        Text(
          'Contact clicks per view: ${_percent(r.ctr)}',
          style: text.titleMedium,
        ),
        if (r.ctrDefinition != null)
          Text(r.ctrDefinition!, style: text.bodySmall),
        if (r.daily.length > 1) ...[
          const SizedBox(height: Space.x5),
          const SectionHeading('Views each day'),
          const SizedBox(height: Space.x2),
          _DailyChart(r.daily),
          ExpansionTile(
            key: const Key('daily-table'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Show the figures as a table'),
            children: [
              for (final d in r.daily.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 72, child: Text(days.format(d.date))),
                      Expanded(
                        child: Text(
                          '${d.views} views · ${d.uniqueViews} unique · ${d.enquiries} enquiries',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: Space.x5),
        const SectionHeading('Where views came from'),
        const SizedBox(height: Space.x2),
        _Breakdown(r.sources, _sourceLabels),
        const SizedBox(height: Space.x4),
        const SectionHeading('Devices'),
        const SizedBox(height: Space.x2),
        _Breakdown(r.devices, _deviceLabels),
        if (r.topListings.isNotEmpty) ...[
          const SizedBox(height: Space.x5),
          const SectionHeading('Most viewed listings'),
          const SizedBox(height: Space.x2),
          for (final t in r.topListings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.title),
              subtitle: Text(
                '${t.reference} · ${_number.format(t.views)} views · ${t.enquiries} enquiries',
              ),
              trailing: t.slug == null ? null : const Icon(Icons.chevron_right),
              onTap: t.slug == null
                  ? null
                  : () => context.push(
                      Routes.listing(t.slug!, heroScope: 'statistics'),
                    ),
            ),
        ],
        if (r.filteredBotEvents > 0 || r.lateEventsDropped > 0) ...[
          const SizedBox(height: Space.x3),
          Text(
            'Left out: ${r.filteredBotEvents} automated visits and '
            '${r.lateEventsDropped} events that arrived too late.',
            style: text.bodySmall,
          ),
        ],
        const SizedBox(height: Space.x4),
        Wrap(
          spacing: Space.x2,
          children: [
            TextButton(
              key: const Key('how-we-count'),
              onPressed: () => onOpenWeb(r.definitionsPath),
              child: const Text('How we count'),
            ),
            TextButton(
              onPressed: () => onOpenWeb('/agent/analytics'),
              child: const Text('Detailed reports on the website'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Daily views as bars, with a text summary for screen readers (the table
/// below has every figure).
class _DailyChart extends StatelessWidget {
  const _DailyChart(this.days);

  final List<AnalyticsDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final most = days.fold<int>(0, (m, d) => d.views > m ? d.views : m);
    final total = days.fold<int>(0, (s, d) => s + d.views);
    final busiest = days.isEmpty
        ? null
        : days.reduce((a, b) => b.views > a.views ? b : a);
    final summary = busiest == null || most == 0
        ? 'No views in this period.'
        : '$total views over ${days.length} days. The busiest day was '
              '${DateFormat('d MMMM').format(busiest.date)} with ${busiest.views}.';
    return Semantics(
      container: true,
      label: summary,
      excludeSemantics: true,
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: (most == 0 ? 1 : most).toDouble(),
            barTouchData: BarTouchData(enabled: false),
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (var i = 0; i < days.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: days[i].views.toDouble(),
                      color: c.primary,
                      width: days.length > 14 ? 5 : 12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown(this.counts, this.labels);

  final List<({String key, int count})> counts;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = counts.fold<int>(0, (s, e) => s + e.count);
    final shown = [
      for (final e in counts)
        if (e.count > 0) e,
    ];
    if (shown.isEmpty) return Text('Nothing yet.', style: text.bodyMedium);
    return Column(
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Row(
              children: [
                Expanded(child: Text(labels[e.key] ?? e.key)),
                Text(
                  '${_number.format(e.count)} (${(e.count * 100 / total).round()}%)',
                ),
              ],
            ),
          ),
      ],
    );
  }
}
