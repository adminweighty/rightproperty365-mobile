import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/async_view.dart';

/// Bottom navigation around the four top-level sections.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerTheme.color!),
          ),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          // Tapping the current tab again returns to its first screen.
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder. My Property Activity needs sign-in, which is not built yet.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activity')),
    body: const MessageView(
      icon: Icons.inbox_outlined,
      title: 'Your activity will appear here',
      body:
          'Saved properties, enquiries, applications and viewings will be listed here once sign-in is available. '
          'Until then, keep the reference shown after you send a request.',
    ),
  );
}

/// Placeholder. Sign-in, preferences and account deletion are not built yet.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account')),
    body: const MessageView(
      icon: Icons.person_outline,
      title: 'Sign-in is not available yet',
      body:
          'You can browse and send requests as a guest. Accounts, notification preferences and '
          'account deletion will be added here.',
    ),
  );
}
