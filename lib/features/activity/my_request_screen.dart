import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import '../property_requests/presentation/request_thread.dart';
import 'my_requests_repository.dart';

final _stamp = DateFormat('d MMM y, HH:mm');

BadgeTone requestTone(String status) => switch (status) {
  'RESPONDED' || 'VIEWING_SCHEDULED' => BadgeTone.success,
  'CLOSED' => BadgeTone.neutral,
  _ => BadgeTone.primary,
};

/// A request the signed-in Property Seeker sent, in a list.
class MyRequestCard extends StatelessWidget {
  const MyRequestCard(this.request, {super.key, required this.onTap});

  final MyRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = request.listingTitle ?? 'Property no longer listed';
    return BrandCard(
      key: Key('my-request-${request.reference}'),
      onTap: onTap,
      semanticLabel:
          '$title. ${request.typeLabel}. ${request.statusLabel}. '
          '${request.unreadReply ? 'New reply. ' : ''}${request.reference}',
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: text.titleMedium)),
                const SizedBox(width: Space.x2),
                AppBadge(
                  request.statusLabel,
                  tone: requestTone(request.status),
                ),
              ],
            ),
            Text(
              '${request.typeLabel} · ${_stamp.format(request.createdAt.toLocal())}',
              style: text.bodyMedium,
            ),
            Text(request.reference, style: text.bodySmall),
            if (request.unreadReply)
              Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: AppBadge(
                  'New reply',
                  key: Key('new-reply-${request.reference}'),
                  tone: BadgeTone.accent,
                  icon: Icons.mark_chat_unread_outlined,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One request with its status history, as its sender sees it.
class MyRequestScreen extends StatefulWidget {
  const MyRequestScreen({super.key, required this.id});

  final String id;

  @override
  State<MyRequestScreen> createState() => _MyRequestScreenState();
}

class _MyRequestScreenState extends State<MyRequestScreen> {
  Future<MyRequest>? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request ??= AppScope.of(context).myRequests.get(widget.id);
  }

  void _reload() => setState(() {
    _request = AppScope.of(context).myRequests.get(widget.id);
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your enquiry')),
      body: AsyncView<MyRequest>(
        future: _request!,
        onRetry: _reload,
        builder: (context, r) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      r.listingTitle ?? 'Property no longer listed',
                      style: text.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(width: Space.x2),
                AppBadge(r.statusLabel, tone: requestTone(r.status)),
              ],
            ),
            Text(
              '${r.typeLabel} · ${r.reference}',
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x4),
            Text(_explain(r.status), style: text.bodyLarge),
            const SizedBox(height: Space.x4),
            Text('Your message', style: text.titleSmall),
            const SizedBox(height: Space.x1),
            Text(r.message, style: text.bodyLarge),
            const SizedBox(height: Space.x2),
            Text(
              'You asked to be contacted by ${switch (r.contactMethod) {
                'PHONE' => 'phone call',
                'WHATSAPP' => 'WhatsApp',
                _ => 'email',
              }}. Written replies also appear in the conversation below.',
              style: text.bodyMedium,
            ),
            if (r.listingSlug != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push(
                    Routes.listing(r.listingSlug!, heroScope: 'my-request'),
                  ),
                  child: const Text('View the property'),
                ),
              ),
            const SizedBox(height: Space.x4),
            const SectionHeading('Conversation'),
            const SizedBox(height: Space.x2),
            RequestThread(
              key: const Key('my-request-thread'),
              messages: r.messages,
              emptyText: "You'll see the agent's reply here.",
              blockedText: r.canReply || r.status != 'CLOSED'
                  ? null
                  : 'This request is closed, so it cannot be answered here.',
              onSend: r.canReply
                  ? (body) async {
                      final requests = AppScope.of(context).myRequests;
                      await requests.reply(widget.id, body);
                      if (mounted) _reload();
                    }
                  : null,
            ),
            if (r.timeline.isNotEmpty) ...[
              const SizedBox(height: Space.x4),
              const SectionHeading('History'),
              const SizedBox(height: Space.x2),
              for (final e in r.timeline)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Text(
                    '${e.received ? 'Received' : 'Now ${e.label.toLowerCase()}'} · '
                    '${_stamp.format(e.at.toLocal())}',
                    style: text.bodyLarge,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _explain(String status) => switch (status) {
    'RECEIVED' =>
      'Your enquiry has been received. Nobody has worked on it yet.',
    'IN_PROGRESS' => 'Someone is working on your enquiry.',
    'RESPONDED' =>
      'They have responded. See the conversation below, and check your '
          'email or phone.',
    'VIEWING_SCHEDULED' => 'A viewing has been arranged. See your viewings.',
    _ => 'This enquiry is closed.',
  };
}
