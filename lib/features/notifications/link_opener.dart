import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../auth/auth_controller.dart';
import 'notification_links.dart';

/// Website paths the app has under another path, or resolves first.
/// Returns where to go instead, or null for a path the app has as such
/// (`/listings/{slug}`, `/apply/{slug}`, `/sign/{token}`,
/// `/invitations/{token}`, `/verify-email`, `/reset-password`).
String? webLinkRedirect(Uri uri) {
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (path == '/listings') return Routes.search();
  if (s.isNotEmpty && s.first == 'directory' && s.length > 1) {
    return s.length == 2 ? '/profiles/${s[1]}' : '/profiles/${s[1]}/${s[2]}';
  }
  if (path == '/dashboard') return Routes.account;
  if (s.length > 1 && (s.first == 'account' || s.first == 'agent') ||
      path == '/agent') {
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return Uri(
      path: '/open',
      queryParameters: {'to': '$path$fragment'},
    ).toString();
  }
  return null;
}

/// Opens a website link that needs the account (and sometimes a lookup of
/// which organisation holds it): the app's screen, or the website in a
/// browser tab when the app has no such screen.
class LinkOpenerScreen extends StatefulWidget {
  const LinkOpenerScreen({super.key, required this.link});

  /// A relative website path, for example `/agent/maintenance/{id}`.
  final String link;

  @override
  State<LinkOpenerScreen> createState() => _LinkOpenerScreenState();
}

class _LinkOpenerScreenState extends State<LinkOpenerScreen> {
  bool _started = false;
  AuthController? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    final auth = _auth = AppScope.of(context).auth;
    if (auth.signedIn) {
      _started = true;
      // After this route has settled, never in the middle of it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    } else {
      // Launched from a link, the saved session may still be loading.
      auth.addListener(_authChanged);
    }
  }

  void _authChanged() {
    final auth = _auth!;
    if (!auth.signedIn || _started) return;
    auth.removeListener(_authChanged);
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _auth?.removeListener(_authChanged);
    super.dispose();
  }

  /// Leaving while this page is still sliding in would tangle the routes.
  Future<void> _arrived() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) return;
    final done = Completer<void>();
    void listen(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listen);
      done.complete();
    }

    animation.addStatusListener(listen);
    await done.future;
  }

  Future<void> _open() async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    final target = await resolveNotificationLink(widget.link, services);
    if (!mounted) return;
    await _arrived();
    if (!mounted) return;
    switch (target) {
      case InApp(:final location, :final extra, replace: true):
        router.go(location, extra: extra);
      case InApp(:final location, :final extra):
        router.go(Routes.home);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => router.push(location, extra: extra),
        );
      case OnWebsite(:final url):
        router.go(Routes.home);
        await services.openLink(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Opening the link')),
      body: ListenableBuilder(
        listenable: services.auth,
        builder: (context, _) => services.auth.signedIn || _started
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: MessageView(
                  icon: Icons.lock_outline,
                  title: 'Sign in to open this',
                  body:
                      'This link is to something in your account. Sign in '
                      'and it opens.',
                  actionLabel: 'Sign in',
                  onAction: () => context.push(Routes.signIn),
                ),
              ),
      ),
    );
  }
}
