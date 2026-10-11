import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'feedback.dart';
import 'support.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final Stream<List<Map<String, dynamic>>> _stream;
  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.notificationStream();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, s) {
          final count = (s.data ?? [])
              .where((r) => r['is_read'] == false)
              .length;
          return IconButton(
            tooltip: 'Notifications${count > 0 ? ', $count unread' : ''}',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            ),
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 99 ? '99+' : '$count'),
              backgroundColor: AppColors.error,
              child: const Icon(Icons.notifications_none_outlined, size: 28),
            ),
          );
        },
      );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _marking = false;
  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.notificationStream();
  }

  Future<void> _markAll() async {
    setState(() => _marking = true);
    try {
      await SupabaseService.markAllNotificationsRead();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    try {
      await SupabaseService.markNotificationRead(n['id'] as String);
      if (!mounted) return;
      if (n['kind'] == 'message' && n['reference_id'] != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationPage(
              requestId: n['reference_id'] as String,
              name: 'Conversation',
            ),
          ),
        );
      } else if (n['kind'] == 'request') {
        final role = await SupabaseService.getMyRole();
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => role == 'volunteer'
                  ? const RequestsPage()
                  : const JourneyPage(),
            ),
          );
        }
      } else if (n['kind'] == 'session') {
        final role = await SupabaseService.getMyRole();
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => role == 'volunteer'
                  ? const SchedulePage()
                  : const JourneyPage(),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        TextButton(
          onPressed: _marking ? null : _markAll,
          child: const Text('Mark all as read', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
    body: ResponsiveBody(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError) {
            return EmptyState(
              'Could not load notifications',
              friendlyError(s.error!),
              retry: () => setState(
                () => _stream = SupabaseService.notificationStream(),
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.isEmpty) {
            return const EmptyState(
              'You’re all caught up',
              'New requests and messages will appear here.',
              icon: Icons.notifications_none,
            );
          }
          final unread = s.data!.where((r) => r['is_read'] == false).toList();
          final read = s.data!.where((r) => r['is_read'] == true).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (unread.isNotEmpty) const SectionTitle('New'),
              for (final n in unread) _tile(n),
              if (read.isNotEmpty) const SectionTitle('Earlier'),
              for (final n in read) _tile(n),
            ],
          );
        },
      ),
    ),
  );
  Widget _tile(Map<String, dynamic> n) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SurfaceCard(
      onTap: () => _open(n),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Icon(
              n['kind'] == 'message'
                  ? Icons.chat_bubble_outline
                  : Icons.notifications_outlined,
              color: AppColors.primaryNavy,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n['title'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeAgo(n['created_at'] as String),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  n['body'] as String,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (n['is_read'] == false)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.circle,
                color: AppColors.selectedCardBorder,
                size: 9,
              ),
            ),
        ],
      ),
    ),
  );
}

String timeAgo(String value) {
  final d = DateTime.now().difference(DateTime.parse(value).toLocal());
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}
