import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../auth/presentation/auth_screens.dart' show FailureBox;
import '../data/request_message.dart';

final _stamp = DateFormat('d MMM y, HH:mm');

/// The conversation on a property request, oldest first, with a composer.
/// Used on both sides; the private notes are a separate section.
class RequestThread extends StatefulWidget {
  const RequestThread({
    super.key,
    required this.messages,
    required this.emptyText,
    this.blockedText,
    this.onSend,
    this.sendLabel = 'Send',
  });

  final List<RequestMessage> messages;

  /// Shown while there are no messages.
  final String emptyText;

  /// Shown instead of the composer, for example on a closed request.
  final String? blockedText;

  /// Sends a message; throws [ApiFailure]. Null: no composer.
  final Future<void> Function(String body)? onSend;
  final String sendLabel;

  @override
  State<RequestThread> createState() => _RequestThreadState();
}

class _RequestThreadState extends State<RequestThread> {
  final _body = TextEditingController();
  bool _sending = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await widget.onSend!(_body.text.trim());
      if (!mounted) return;
      _body.clear();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.messages.isEmpty)
          Text(
            widget.emptyText,
            key: const Key('thread-empty'),
            style: text.bodyLarge,
          ),
        for (final m in widget.messages) _Bubble(m),
        if (widget.blockedText != null) ...[
          const SizedBox(height: Space.x2),
          Text(
            widget.blockedText!,
            key: const Key('thread-blocked'),
            style: text.bodyMedium,
          ),
        ] else if (widget.onSend != null) ...[
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('thread-input'),
            controller: _body,
            maxLength: requestMessageMax,
            minLines: 2,
            maxLines: 6,
            enabled: !_sending,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Write a reply'),
          ),
          if (_failure != null) ...[
            FailureBox(_failure!),
            const SizedBox(height: Space.x2),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('thread-send'),
              onPressed: _sending || _body.text.trim().isEmpty ? null : _send,
              icon: const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Sending…' : widget.sendLabel),
            ),
          ),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final RequestMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final who = message.mine ? 'You' : message.authorName;
    final when = _stamp.format(message.at.toLocal());
    return Semantics(
      container: true,
      label: '$who, $when',
      child: Align(
        alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.88,
          child: Container(
            key: Key('thread-message-${message.id}'),
            margin: const EdgeInsets.only(top: Space.x3),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: message.mine ? c.primarySoft : c.sunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    '$who · $when',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: Space.x1),
                SelectableText(message.body, style: text.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
