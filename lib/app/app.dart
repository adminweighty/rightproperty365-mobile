import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/notifications/notification_bell.dart';
import 'app_scope.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class RightPropertyApp extends StatefulWidget {
  const RightPropertyApp({super.key, required this.services});

  final AppServices services;

  @override
  State<RightPropertyApp> createState() => _RightPropertyAppState();
}

class _RightPropertyAppState extends State<RightPropertyApp> {
  late final GoRouter _router = buildRouter();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final PushHandler _push = PushHandler(
    services: widget.services,
    router: _router,
    messenger: _messenger,
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back on screen: the count and the phone's permission may have changed.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        widget.services.notificationCentre.refresh();
        widget.services.notificationCentre.refreshPushState();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _push.start());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _push.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp.router(
        title: 'RightProperty365',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
