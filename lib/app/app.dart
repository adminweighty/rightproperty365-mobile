import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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

  @override
  void dispose() {
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
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
