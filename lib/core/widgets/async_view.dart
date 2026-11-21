import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart' show branchForbiddenMessage;
import '../branch.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';

/// Renders the loading, error and data states of a future the same way on
/// every screen.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (isBranchForbidden(snapshot.error)) {
          return const MessageView(
            key: Key('branch-forbidden'),
            icon: Icons.lock_outline,
            title: 'Another branch',
            body: branchForbiddenMessage,
          );
        }
        if (snapshot.hasError) {
          return MessageView(
            icon: Icons.cloud_off_outlined,
            title: 'We could not load this',
            body: 'Check your connection and try again.',
            actionLabel: onRetry == null ? null : 'Try again',
            onAction: onRetry,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Semantics(
              label: 'Loading',
              child: const CircularProgressIndicator(),
            ),
          );
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}

/// Centred icon, title and explanation, with an optional action. Used for
/// empty, error and not-built-yet states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 40, color: context.colors.subtle),
            ),
            const SizedBox(height: Space.x4),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.x2),
            Text(
              body,
              style: text.bodyLarge?.copyWith(color: context.colors.muted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.x6),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
