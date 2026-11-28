import '../../backend/services/push_notification_service.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/services/time_zone_sync.dart';
import 'ui.dart';

import 'package:flutter/material.dart';

import '../design/navigation.dart';
import '../widgets/maak_bottom_nav.dart';
import 'navigation.dart';
import 'home.dart';
import 'profile.dart';
import 'support.dart';
import 'matching_page.dart';
import '../patient/health_library_page.dart' show ArticleDetailsPage;
import 'sessions.dart' show SessionsPage;
import 'in_app_banner.dart'; // pop-up banner for new notifications

class AppShell extends StatefulWidget {
  final String role;

  /// Test hook: replaces the notification stream behind the pop-up banner.
  final Stream<List<Map<String, dynamic>>>? notifications;
  const AppShell({super.key, required this.role, this.notifications});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  int _index = 0;
  late final _unread = SupabaseService.unreadMessageCount();

  // Opens a push notification the user tapped (now, or before this shell existed).
  @override
  void initState() {
    super.initState();
    // Session notification times use this device's time zone.
    WidgetsBinding.instance.addObserver(this);
    TimeZoneSync.sync();
    PushNotificationService.pendingOpen.addListener(_openPendingPush);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingPush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.pendingOpen.removeListener(_openPendingPush);
    super.dispose();
  }

  // The device may have changed time zone (travel, daylight saving).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) TimeZoneSync.sync();
  }

  void _openPendingPush() {
    if (!mounted || PushNotificationService.pendingOpen.value == null) return;
    final n = PushNotificationService.takePendingOpen();
    if (n != null) _openNotification(n);
  }
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

   // Open the screen a banner points to
  void _openNotification(Map<String, dynamic> n) {
    final id = n['id'];
    if (id is String) {
      SupabaseService.markNotificationRead(id).catchError((_) {});
    }
    final nav = _navigator.currentState;
    if (nav == null) return;
    // 'restricted': an administrator ended this conversation (reference_id is
    // the support request); open it so the member sees why.
    if ((n['kind'] == 'message' ||
            n['kind'] == 'chat_reopen' ||
            n['kind'] == 'restricted' ||
            n['kind'] == 'restriction_lifted' ||
            // Missed voice call: open the chat so they can call back.
            n['kind'] == 'voice_call_missed') &&
        n['reference_id'] != null) {
      ConversationPage.open(
        context,
        requestId: n['reference_id'] as String,
        name: 'Conversation',
      );
    } else if (n['kind'] == 'request') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => widget.role == 'volunteer'
              ? const RequestsPage()
              : const JourneyPage(),
        ),
      );
    } else if (n['kind'] == 'article_reply' && n['reference_id'] != null) {
      // A reply to the member's Health Library comment (push, banner or list).
      nav.push(
        MaterialPageRoute(
          builder: (_) => ArticleDetailsPage(
            articleId: n['reference_id'] as String,
            scrollToComments: true,
          ),
        ),
      );
    } else if (n['kind'] == 'support_session') {
      // Session request / confirmation / cancellation / reschedule.
      nav.push(
        MaterialPageRoute(builder: (_) => SessionsPage(role: widget.role)),
      );
    } else if (n['kind'] == 'match' && widget.role == 'help_seeker') {
      nav.push(MaterialPageRoute(builder: (_) => const MatchingPage()));
    }
  }


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
