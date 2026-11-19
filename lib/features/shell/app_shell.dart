import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';

/// Bottom navigation around the five top-level sections.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final centre = AppScope.of(context).notificationCentre;
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerTheme.color!),
          ),
        ),
        child: ListenableBuilder(
          listenable: centre,
          builder: (context, _) => _bar(centre.unreadCount),
        ),
      ),
    );
  }

  Widget _bar(int unread) {
    Widget activity(IconData icon) => unread == 0
        ? Icon(icon)
        : Badge.count(count: unread, child: Icon(icon));
    return NavigationBar(
      selectedIndex: shell.currentIndex,
      // Tapping the current tab again returns to its first screen.
      onDestinationSelected: (index) =>
          shell.goBranch(index, initialLocation: index == shell.currentIndex),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Directory',
        ),
        NavigationDestination(
          icon: activity(Icons.inbox_outlined),
          selectedIcon: activity(Icons.inbox),
          label: 'Activity',
          tooltip: unread == 0
              ? null
              : 'Activity, $unread unread notifications',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Account',
        ),
      ],
    );
  }
}
