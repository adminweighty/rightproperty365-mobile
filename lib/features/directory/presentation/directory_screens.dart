import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/reveal.dart';
import '../data/profile.dart';
import 'widgets/profile_widgets.dart';

/// Entry point to the six directories.
class DirectoryHubScreen extends StatelessWidget {
  const DirectoryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final directory = AppScope.of(context).directory;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Directory')),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Text(
            'Find Real Estate Agencies, Estate Agents, Property Developers, Landlords and Property Managers, hosts and '
            'property services. Contact is by enquiry through RightProperty365.',
            style: text.bodyLarge?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: Space.x5),
          for (final (index, info) in directory.directories.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: Reveal(
                index: index,
                child: DirectoryTile(
                  info: info,
                  count: directory.ofKind(info.kind).length,
                  onTap: () => context.push(Routes.directoryKind(info.kind)),
                ),
              ),
            ),
          Text('Profiles shown are sample data.', style: text.bodySmall),
        ],
      ),
    );
  }
}

/// A directory's title, description and size. Also used on the home screen.
class DirectoryTile extends StatelessWidget {
  const DirectoryTile({
    super.key,
    required this.info,
    required this.count,
    required this.onTap,
  });

  final DirectoryInfo info;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return BrandCard(
      onTap: onTap,
      semanticLabel: '${info.title}, $count listed. ${info.description}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(directoryIcon(info.kind), color: c.primaryInk),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.title, style: text.titleMedium),
                  Text(info.description, style: text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: Space.x2),
            Text(
              '$count',
              style: text.titleMedium?.copyWith(color: c.primaryInk),
            ),
            Icon(Icons.chevron_right, color: c.subtle),
          ],
        ),
      ),
    );
  }
}

/// The profiles of one directory. Sponsored first; service providers are
/// grouped by trade.
class DirectoryListScreen extends StatelessWidget {
  const DirectoryListScreen({super.key, required this.kind});

  final DirectoryKind? kind;

  @override
  Widget build(BuildContext context) {
    final kind = this.kind;
    if (kind == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const MessageView(
          icon: Icons.menu_book_outlined,
          title: 'We could not find that directory',
          body: 'Go back and choose one from the list.',
        ),
      );
    }

    final directory = AppScope.of(context).directory;
    final info = directory.info(kind);
    final text = Theme.of(context).textTheme;

    Widget card(Profile profile) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: ProfileCard(
        profile: profile,
        onTap: () => context.push(Routes.profile(profile)),
      ),
    );

    if (directory.ofKind(kind).isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(info.title)),
        body: MessageView(
          icon: directoryIcon(kind),
          title: 'No ${info.title} listed yet',
          body:
              '${info.description} Profiles appear here once they have been verified.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(info.title)),
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Text(
            info.description,
            style: text.bodyLarge?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: Space.x5),
          if (kind == DirectoryKind.serviceProviders)
            for (final group in directory.serviceCategories()) ...[
              SectionHeading(group.category),
              const SizedBox(height: Space.x3),
              ...group.entries.map(card),
              const SizedBox(height: Space.x3),
            ]
          else
            ...directory.ofKind(kind).map(card),
        ],
      ),
    );
  }
}
