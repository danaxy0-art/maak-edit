import 'ui.dart';
import 'package:flutter/material.dart';
import '../widgets/maak_bottom_nav.dart';
import 'navigation.dart';
import 'home.dart';
import 'profile.dart';
import 'support.dart';

class AppShell extends StatefulWidget {
  final String role;
  const AppShell({super.key, required this.role});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navigator = GlobalKey<NavigatorState>();
  int _index = 0;
  Widget _page(int index) => switch (index) {
    1 =>
      widget.role == 'volunteer' ? const SchedulePage() : const JourneyPage(),
    2 => const ConversationsPage(),
    3 => ProfilePage(role: widget.role),
    _ => HomePage(role: widget.role),
  };
  void _select(int index) {
    setState(() => _index = index);
    _navigator.currentState!.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _page(index)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    role: widget.role,
    selectTab: _select,
    child: BotanicalScaffold(
      body: NavigatorPopHandler(
        onPopWithResult: (_) => _navigator.currentState!.pop(),
        child: Navigator(
          key: _navigator,
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _page(0)),
        ),
      ),
      bottomNavigationBar: MaakBottomNav(
        currentIndex: _index,
        onTap: _select,
        items: [
          const MaakNavItem(icon: Icons.home_outlined, label: 'Home'),
          MaakNavItem(
            icon: widget.role == 'volunteer'
                ? Icons.calendar_month_outlined
                : Icons.eco_outlined,
            label: widget.role == 'volunteer' ? 'Schedule' : 'Journey',
          ),
          const MaakNavItem(icon: Icons.chat_bubble_outline, label: 'Messages'),
          const MaakNavItem(icon: Icons.person_outline, label: 'Profile'),
        ],
      ),
    ),
  );
}
