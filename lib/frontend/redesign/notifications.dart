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
  /// Test hook: replaces the Supabase notification stream.
  final Stream<List<Map<String, dynamic>>>? stream;
  const NotificationsPage({super.key, this.stream});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _marking = false;
  @override
  void initState() {
    super.initState();
    _stream = widget.stream ?? SupabaseService.notificationStream();
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
      if ((n['kind'] == 'message' ||
              n['kind'] == 'chat_reopen' ||
              n['kind'] == 'restricted') &&
          n['reference_id'] != null) {
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
                  : n['kind'] == 'restricted'
                  ? Icons.admin_panel_settings_outlined
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
                if (n['kind'] == 'chat_reopen' &&
                    n['title'] == 'Chat reopen request' &&
                    n['reference_id'] != null) ...[
                  const SizedBox(height: 12),
                  _ChatReopenNotificationActions(
                    requestId: n['reference_id'].toString(),
                    notificationId: n['id'].toString(),
                    notificationCreatedAt: n['created_at'].toString(),
                  ),
                ],
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


/// Decision actions are only offered to the recipient of a pending request.
/// The database RPC performs the final authorization and atomic update.
class _ChatReopenNotificationActions extends StatefulWidget {
  final String requestId;
  final String notificationId;
  final String notificationCreatedAt;
  const _ChatReopenNotificationActions({
    required this.requestId,
    required this.notificationId,
    required this.notificationCreatedAt,
  });

  @override
  State<_ChatReopenNotificationActions> createState() =>
      _ChatReopenNotificationActionsState();
}

class _ChatReopenNotificationActionsState
    extends State<_ChatReopenNotificationActions> {
  bool _busy = false;
  bool _completed = false;
  late Stream<List<Map<String, dynamic>>> _requests;

  @override
  void initState() {
    super.initState();
    _requests = SupabaseService.chatReopenRequestsStream(widget.requestId);
  }

  Future<void> _decide(bool accept) async {
    if (_busy || _completed) return;
    setState(() => _busy = true);
    Object? decisionError;
    try {
      await SupabaseService.decideChatReopen(widget.requestId, accept: accept);
    } catch (e) {
      decisionError = e;
    }
    if (!mounted) return;
    if (decisionError != null) {
      // A lost RPC response can occur after the server commits. Re-read state.
      try {
        final row = await SupabaseService.client
            .from('support_requests')
            .select('ended_at')
            .eq('id', widget.requestId)
            .single();
        if (accept && row['ended_at'] == null) {
          decisionError = null;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (decisionError != null) {
      setState(() => _busy = false);
      showAppError(context, decisionError);
      return;
    }
    setState(() {
      _completed = true;
      _busy = false;
    });
    // The decision is already saved. A read-receipt failure is non-fatal.
    try {
      await SupabaseService.markNotificationRead(widget.notificationId);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(accept
          ? 'Conversation reopened successfully.'
          : 'Reopen request declined.'),
    ));
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _requests,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() => _requests =
                  SupabaseService.chatReopenRequestsStream(widget.requestId)),
              child: const Text('Retry loading request'),
            );
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          // Each notification belongs to the request created immediately before
          // that notification. reference_id is the conversation ID (not the
          // individual reopen request ID), so checking for *any* pending request
          // would incorrectly reactivate buttons on old notifications.
          final notificationTime = DateTime.tryParse(widget.notificationCreatedAt);
          final eligible = snapshot.data!.where((row) =>
              row['recipient_id'] == SupabaseService.currentUser?.id &&
              DateTime.tryParse(row['created_at']?.toString() ?? '') != null).toList();
          eligible.sort((a, b) =>
              DateTime.parse(b['created_at'].toString()).compareTo(
                  DateTime.parse(a['created_at'].toString())));
          Map<String, dynamic>? corresponding;
          if (notificationTime != null) {
            for (final row in eligible) {
              final requestTime = DateTime.parse(row['created_at'].toString());
              // Both timestamps are generated in the same database transaction.
              // Allow a small clock/precision margin, never bind an older
              // notification to a later request.
              if (!requestTime.isAfter(notificationTime.add(
                  const Duration(seconds: 1)))) {
                corresponding = row;
                break;
              }
            }
          }
          if (_completed || corresponding == null ||
              corresponding['status'] != 'pending') {
            return const Text('Request no longer pending.',
                style: TextStyle(color: AppColors.textMuted));
          }
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _decide(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB54747),
                  side: const BorderSide(color: Color(0xFFB54747), width: 1.5),
                ),
                child: const Text('Decline'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _decide(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF287A57),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB0B0B0),
                ),
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: Text(_busy ? 'Saving...' : 'Accept & reopen'),
              ),
            ],
          );
        },
      );
}

String timeAgo(String value) {
  final d = DateTime.now().difference(DateTime.parse(value).toLocal());
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}
