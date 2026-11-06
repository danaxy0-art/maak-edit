import '../../backend/services/supabase_service.dart';
import 'ui.dart';

import 'package:flutter/material.dart';

import '../design/navigation.dart';
import '../widgets/maak_bottom_nav.dart';
import 'navigation.dart';
import 'home.dart';
import 'profile.dart';
import 'support.dart';
import 'in_app_banner.dart'; // ADDED: pop-up banner for new notifications

class AppShell extends StatefulWidget {
  final String role;

  /// Test hook: replaces the notification stream behind the pop-up banner.
  final Stream<List<Map<String, dynamic>>>? notifications;
  const AppShell({super.key, required this.role, this.notifications});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navigator = GlobalKey<NavigatorState>();
  int _index = 0;
  late final _unread = SupabaseService.unreadMessageCount();
  Widget _page(int index) => switch (index) {
    1 =>
      widget.role == 'volunteer' ? const RequestsPage() : const JourneyPage(),
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

   // === ADDED: open the screen a banner points to ===
  void _openNotification(Map<String, dynamic> n) {
    final id = n['id'];
    if (id is String) {
      SupabaseService.markNotificationRead(id).catchError((_) {});
    }
    final nav = _navigator.currentState;
    if (nav == null) return;
    // 'restricted': an administrator ended this conversation (reference_id is
    // the support request); open it so the member sees why.
    if ((n['kind'] == 'message' || n['kind'] == 'restricted') &&
        n['reference_id'] != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ConversationPage(
            requestId: n['reference_id'] as String,
            name: 'Conversation',
          ),
        ),
      );
    } else if (n['kind'] == 'request') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => widget.role == 'volunteer'
              ? const RequestsPage()
              : const JourneyPage(),
        ),
      );
    }
  }
  // === END ADDED ===


  @override
  Widget build(BuildContext context) => NotificationBannerHost(
enabled: widget.role == 'volunteer' || widget.role == 'help_seeker', // Pop-up for both roles
    stream: widget.notifications,
    onOpen: _openNotification,
    child: ShellScope(
      role: widget.role,
      selectTab: _select,
      child: BotanicalScaffold(
        body: NavigatorPopHandler(
          onPopWithResult: (_) => _navigator.currentState!.pop(),
          child: Navigator(
            key: _navigator,
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => _page(0)),
          ),
        ),
        bottomNavigationBar: StreamBuilder<int>(
          stream: _unread,
          builder: (context, snapshot) => MaakNavBar(
            currentIndex: _index,
            onTap: _select,
            items: [
              const MaakNavItem(icon: Icons.home_outlined, label: 'Home'),
              MaakNavItem(
                icon: widget.role == 'volunteer'
                    ? Icons.inbox_outlined
                    : Icons.eco_outlined,
                label: widget.role == 'volunteer' ? 'Requests' : 'Journey',
              ),
              MaakNavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Messages',
                unreadCount: snapshot.data ?? 0,
              ),
              const MaakNavItem(icon: Icons.person_outline, label: 'Profile'),
            ],
          ),
        ),
      ),
    ),
  );
}
