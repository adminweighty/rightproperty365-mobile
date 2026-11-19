import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import 'legal.dart';

/// Above every screen while a legal document waits for acceptance. It never
/// stands in the way: "Later" hides it until the app starts again.
class LegalBanner extends StatelessWidget {
  const LegalBanner({
    super.key,
    required this.centre,
    required this.router,
    required this.child,
  });

  final LegalCentre centre;
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: centre,
    builder: (context, _) {
      if (!centre.showBanner) return child;
      final c = context.colors;
      final text = Theme.of(context).textTheme;
      final titles = centre.pending.map((p) => p.title).toList();
      return Column(
        children: [
          Material(
            key: const Key('legal-banner'),
            color: c.infoSoft,
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
                      child: Icon(Icons.gavel_outlined, size: 20),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          titles.length == 1
                              ? 'We have updated our ${titles.single}. '
                                    'Please review it.'
                              : 'We have updated ${titles.length} documents: '
                                    '${titles.join(', ')}. Please review them.',
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('legal-later'),
                      onPressed: centre.later,
                      child: const Text('Later'),
                    ),
                    TextButton(
                      key: const Key('legal-review'),
                      onPressed: () {
                        centre.later();
                        router.push(Routes.legalUpdates);
                      },
                      child: const Text('Review'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
    },
  );
}

/// Each document waiting for acceptance, with its text and Accept.
class LegalUpdatesScreen extends StatefulWidget {
  const LegalUpdatesScreen({super.key});

  @override
  State<LegalUpdatesScreen> createState() => _LegalUpdatesScreenState();
}

class _LegalUpdatesScreenState extends State<LegalUpdatesScreen> {
  bool _refreshed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_refreshed) {
      _refreshed = true;
      AppScope.of(context).legal.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final centre = AppScope.of(context).legal;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Updated terms')),
      body: ListenableBuilder(
        listenable: centre,
        builder: (context, _) {
          final pending = centre.pending;
          if (pending.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.x5),
                child: Text(
                  'Nothing to review. You have accepted the current versions.',
                  key: const Key('legal-none'),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Space.x4),
            children: [
              Text(
                'You can keep using the app while you read these.',
                style: text.bodyMedium,
              ),
              for (final item in pending)
                _PendingDocument(
                  key: ValueKey('${item.kind}-${item.version}'),
                  item: item,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingDocument extends StatefulWidget {
  const _PendingDocument({super.key, required this.item});

  final PendingLegal item;

  @override
  State<_PendingDocument> createState() => _PendingDocumentState();
}

class _PendingDocumentState extends State<_PendingDocument> {
  Future<LegalDocument>? _loading;
  bool _accepting = false;

  LegalCentre get _centre => AppScope.of(context).legal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _centre.repository.document(widget.item);
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _centre.accept(widget.item);
      messenger.showSnackBar(
        SnackBar(content: Text('Accepted: ${widget.item.title}.')),
      );
    } on ApiFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final from = item.effectiveFrom;
    return Card(
      margin: const EdgeInsets.only(top: Space.x4),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: FutureBuilder<LegalDocument>(
          future: _loading,
          builder: (context, snapshot) {
            final doc = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(doc?.title ?? item.title, style: text.titleLarge),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  [
                    'Version ${item.version}',
                    if (from != null)
                      'in effect from ${DateFormat('d MMMM y').format(from.toLocal())}',
                  ].join(', '),
                  style: text.bodySmall,
                ),
                if ((item.summaryOfChanges ?? '').isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  Text(
                    'What changed: ${item.summaryOfChanges}',
                    style: text.bodyMedium,
                  ),
                ],
                const SizedBox(height: Space.x3),
                if (snapshot.hasError)
                  _LoadFailed(
                    failure: snapshot.error,
                    onRetry: () => setState(
                      () => _loading = _centre.repository.document(item),
                    ),
                  )
                else if (doc == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(Space.x3),
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading the document',
                      ),
                    ),
                  )
                else ...[
                  if (doc.draftNotice)
                    Container(
                      key: Key('legal-draft-${item.kind}'),
                      padding: const EdgeInsets.all(Space.x3),
                      margin: const EdgeInsets.only(bottom: Space.x3),
                      decoration: BoxDecoration(
                        color: c.warningSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'DRAFT: this text is awaiting legal review and is not '
                        'final.',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  LegalMarkdown(doc.body),
                ],
                const SizedBox(height: Space.x3),
                FilledButton(
                  key: Key('legal-accept-${item.kind}'),
                  onPressed: _accepting || doc == null ? null : _accept,
                  child: Text(
                    _accepting ? 'Accepting…' : 'I accept the ${item.title}',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.failure, required this.onRetry});

  final Object? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f is ApiFailure && f.code == 'LEGAL_DOCUMENT_NOT_FOUND'
              ? 'This document is not available right now.'
              : f is ApiFailure
              ? f.message
              : 'The document could not be loaded.',
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

/// A small, safe reading of Markdown: headings, paragraphs, quotes, lists,
/// bold, italic and code. Everything is shown as text: HTML tags are
/// dropped and links show their words only (nothing in it is followed).
class LegalMarkdown extends StatelessWidget {
  const LegalMarkdown(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final blocks = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(
        _block(Text.rich(_inline(paragraph.join(' '), text.bodyMedium))),
      );
      paragraph.clear();
    }

    final clean = source
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'<[^>\n]*>'), '');
    for (final raw in clean.split('\n')) {
      final line = raw.trimRight();
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
      final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (line.trim().isEmpty) {
        flush();
      } else if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        blocks.add(
          _block(
            Semantics(
              header: true,
              child: Text.rich(
                _inline(
                  heading.group(2)!,
                  level <= 2 ? text.titleMedium : text.titleSmall,
                ),
              ),
            ),
          ),
        );
      } else if (line.startsWith('>')) {
        flush();
        blocks.add(
          _block(
            Container(
              padding: const EdgeInsets.only(left: Space.x3),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.lineStrong, width: 3)),
              ),
              child: Text.rich(
                _inline(
                  line.replaceFirst(RegExp(r'^>\s?'), ''),
                  text.bodyMedium,
                ),
              ),
            ),
          ),
        );
      } else if (bullet != null || numbered != null) {
        flush();
        final mark = bullet != null ? '•' : '${numbered!.group(1)}.';
        final body = bullet?.group(1) ?? numbered!.group(2)!;
        blocks.add(
          _block(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: ExcludeSemantics(
                    child: Text(mark, style: text.bodyMedium),
                  ),
                ),
                Expanded(child: Text.rich(_inline(body, text.bodyMedium))),
              ],
            ),
          ),
        );
      } else {
        paragraph.add(line.trim());
      }
    }
    flush();
    return Column(
      key: const Key('legal-body'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  static Widget _block(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x2),
    child: child,
  );

  /// Bold, italic and code within a line; a link keeps only its words.
  static TextSpan _inline(String line, TextStyle? style) {
    final unlinked = line.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (m) => m.group(1)!,
    );
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`',
    );
    var at = 0;
    for (final m in pattern.allMatches(unlinked)) {
      if (m.start > at) {
        spans.add(TextSpan(text: unlinked.substring(at, m.start)));
      }
      if (m.group(1) != null || m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(1) ?? m.group(2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m.group(3) != null || m.group(4) != null) {
        spans.add(
          TextSpan(
            text: m.group(3) ?? m.group(4),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(5),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      }
      at = m.end;
    }
    if (at < unlinked.length) spans.add(TextSpan(text: unlinked.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}
