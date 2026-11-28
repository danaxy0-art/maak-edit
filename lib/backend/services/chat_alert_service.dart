import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_media_policy.dart';
import 'push_notification_service.dart';
import 'session_reminders.dart' show SessionReminders;
import 'supabase_service.dart';

/// New-message alerts built without Firebase Cloud Messaging.
///
/// While the app is running (open or in the background), it listens to new
/// rows in public.messages through Supabase Realtime and shows a local phone
/// notification for each message from the other participant. Row Level
/// Security only delivers messages from the signed-in member's own chats.
///
///  * One notification per conversation, listing its latest messages.
///  * No alert for the chat that is open on screen; opening a chat clears its
///    notification.
///  * A message deleted for everyone removes its notification.
///  * After the connection drops and comes back, messages sent meanwhile are
///    still announced (once each).
///  * Tapping the notification opens the conversation.
///
/// Without FCM nothing can wake a closed app, so there are no alerts after the
/// app has been fully closed (or stopped by the system). Not used on the web.
class ChatAlertService {
  ChatAlertService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'maak_alerts'; // created in MainActivity
  static const _channelName = "Ma'ak notifications";

  /// Messages sent while offline older than this are not announced late.
  static const _catchUpWindow = Duration(minutes: 15);
  static const _maxLines = 5;

  static bool _initialized = false;
  static RealtimeChannel? _channel;
  static String? _userId;
  static DateTime _since = DateTime.now().toUtc();
  static AppLifecycleListener? _lifecycle;

  /// Start/stop run one at a time, in order.
  static Future<void> _queue = Future.value();
  static void _enqueue(Future<void> Function() step) {
    _queue = _queue.then((_) => step()).catchError((Object e) {
      debugPrint('Chat alerts: $e');
    });
  }

  /// Chats on screen, innermost last (set by ConversationPage).
  static final List<String> _openChats = [];

  /// Message ids already announced, so a message is never shown twice.
  static final Set<String> _announced = {};

  /// Per conversation: lines shown in its notification, and their message ids.
  static final Map<String, List<String>> _lines = {};
  static final Map<String, List<String>> _lineIds = {};

  /// Conversation id -> the other participant's name.
  static final Map<String, String> _names = {};

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Call once, after runApp.
  static Future<void> init() async {
    if (_initialized || !_supported) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _onTap,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _onTap(response);
      }
    } catch (e) {
      debugPrint('Chat alerts: could not initialise notifications: $e');
      _initialized = false;
      return;
    }

    _lifecycle = AppLifecycleListener(
      onResume: () {
        // Back in a chat that was open in the background: its alert is read.
        final open = _openChats.isEmpty ? null : _openChats.last;
        if (open != null) unawaited(_clear(open));
      },
    );

    if (SupabaseService.currentUser != null) _enqueue(_start);
    SupabaseService.client.auth.onAuthStateChange.listen((state) {
      final user = state.session?.user;
      if (state.event == AuthChangeEvent.signedOut || user == null) {
        _enqueue(_stop);
      } else {
        _enqueue(_start);
      }
    });
  }

  /// ConversationPage calls this when a chat opens.
  static void conversationOpened(String requestId) {
    _openChats.add(requestId);
    unawaited(_clear(requestId));
  }

  /// ConversationPage calls this when a chat closes.
  static void conversationClosed(String requestId) {
    _openChats.remove(requestId);
  }

  static Future<void> _start() async {
    final user = SupabaseService.currentUser;
    // Already listening for this member (for example after a token refresh).
    if (user != null && user.id == _userId && _channel != null) return;
    await _stop();
    if (user == null) return;
    _userId = user.id;
    _since = DateTime.now().toUtc();
    await _requestPermission();
    final channel = SupabaseService.client.channel('maak-chat-alerts-${user.id}');
    _channel = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => unawaited(_onMessage(payload.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) => unawaited(_onUpdate(payload.newRecord)),
        )
        .subscribe((status, error) {
          // Also fires after a reconnect: announce what arrived meanwhile.
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_catchUp());
          }
        });
  }

  static Future<void> _stop() async {
    final channel = _channel;
    _channel = null;
    _userId = null;
    _announced.clear();
    _lines.clear();
    _lineIds.clear();
    _names.clear();
    if (channel != null) {
      try {
        await SupabaseService.client.removeChannel(channel);
      } catch (_) {}
    }
    // Nobody else's messages stay on this phone after sign-out.
    if (_initialized) await _clearShown();
  }

  /// Removes every notification on screen except session reminders (Sprint 4
  /// US6). cancelAll() would also delete the reminders scheduled for later,
  /// and this runs at every start and sign-in, not only at sign-out;
  /// SessionReminders cancels its own on sign-out. If the list cannot be
  /// read, everything is cleared as before.
  @visibleForTesting
  static Future<void> clearShownForTesting() => _clearShown();

  @visibleForTesting
  static void onTapForTesting(NotificationResponse response) =>
      _onTap(response);

  static Future<void> _clearShown() async {
    try {
      for (final n in await _plugin.getActiveNotifications()) {
        final id = n.id;
        if (id == null || n.channelId == SessionReminders.channelId) continue;
        await _plugin.cancel(id: id, tag: n.tag);
      }
    } catch (_) {
      try {
        await _plugin.cancelAll();
      } catch (_) {}
    }
  }

  static Future<void> _requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Chat alerts: permission request failed: $e');
    }
  }

  /// Messages that arrived while the connection was down.
  static Future<void> _catchUp() async {
    final me = _userId;
    if (me == null) return;
    final floor = DateTime.now().toUtc().subtract(_catchUpWindow);
    final since = _since.isBefore(floor) ? floor : _since;
    try {
      final rows = await SupabaseService.client
          .from('messages')
          .select('id,request_id,sender_id,body,message_type,created_at')
          .neq('sender_id', me)
          .isFilter('read_at', null)
          .isFilter('deleted_at', null)
          .gt('created_at', since.toIso8601String())
          .order('created_at')
          .limit(20);
      for (final row in rows) {
        await _onMessage(row);
      }
    } catch (e) {
      debugPrint('Chat alerts: catch-up failed: $e');
    }
  }

  static Future<void> _onMessage(Map<String, dynamic> m) async {
    final me = _userId;
    final id = m['id'] as String?;
    final requestId = m['request_id'] as String?;
    if (me == null || id == null || requestId == null) return;
    if (m['sender_id'] == me || m['deleted_at'] != null) return;
    if (!_announced.add(id)) return;
    final created = DateTime.tryParse('${m['created_at']}')?.toUtc();
    if (created != null && created.isAfter(_since)) _since = created;

    // The chat is on screen: the member is already reading it.
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (foreground && _openChats.isNotEmpty && _openChats.last == requestId) {
      return;
    }

    final name = await _nameFor(requestId);
    if (_userId != me) return; // signed out meanwhile
    final lines = _lines.putIfAbsent(requestId, () => []);
    final ids = _lineIds.putIfAbsent(requestId, () => []);
    lines.add(_preview(m));
    ids.add(id);
    while (lines.length > _maxLines) {
      lines.removeAt(0);
      ids.removeAt(0);
    }
    await _show(requestId, name);
  }

  /// A message deleted for everyone disappears from the notification.
  static Future<void> _onUpdate(Map<String, dynamic> m) async {
    if (m['deleted_at'] == null) return;
    final requestId = m['request_id'] as String?;
    final ids = _lineIds[requestId];
    if (requestId == null || ids == null) return;
    final index = ids.indexOf('${m['id']}');
    if (index < 0) return;
    ids.removeAt(index);
    _lines[requestId]!.removeAt(index);
    if (ids.isEmpty) {
      await _clear(requestId);
    } else {
      await _show(requestId, await _nameFor(requestId));
    }
  }

  static Future<void> _show(String requestId, String name) async {
    final lines = List<String>.of(_lines[requestId] ?? const []);
    if (lines.isEmpty || !_initialized) return;
    final count = lines.length;
    final title = count > 1 ? '$name ($count new messages)' : name;
    try {
      await _plugin.show(
        id: _notificationId(requestId),
        title: title,
        body: lines.last,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: count > 1
                ? InboxStyleInformation(lines, contentTitle: title)
                : BigTextStyleInformation(lines.last),
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: requestId),
        ),
        payload: requestId,
      );
    } catch (e) {
      debugPrint('Chat alerts: could not show notification: $e');
    }
  }

  static Future<void> _clear(String requestId) async {
    _lines.remove(requestId);
    _lineIds.remove(requestId);
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _notificationId(requestId));
    } catch (_) {}
  }

  static void _onTap(NotificationResponse response) {
    final requestId = response.payload;
    if (requestId == null || requestId.isEmpty) return;
    // Sprint 4 US6: a session reminder opens Sessions, not a conversation.
    if (requestId == SessionReminders.tapPayload) {
      PushNotificationService.pendingOpen.value = Map.of(
        SessionReminders.tapTarget,
      );
      return;
    }
    unawaited(_clear(requestId));
    // AppShell opens the conversation (same path as a tapped notification row).
    PushNotificationService.pendingOpen.value = {
      'id': null,
      'kind': 'message',
      'reference_id': requestId,
    };
  }

  static Future<String> _nameFor(String requestId) async {
    final known = _names[requestId];
    if (known != null) return known;
    try {
      for (final r in await SupabaseService.getRequests()) {
        final id = r['id'] as String?;
        final name = (r['contact_name'] as String?)?.trim();
        if (id != null && name != null && name.isNotEmpty) _names[id] = name;
      }
    } catch (_) {}
    return _names[requestId] ?? 'New message';
  }

  /// Same wording as the in-app chat: media shows an icon plus its caption.
  static String _preview(Map<String, dynamic> m) {
    final type = m['message_type'] as String? ?? 'text';
    if (type == 'image' || type == 'voice' || type == 'video') {
      final icon = type == 'image'
          ? '📷'
          : type == 'voice'
          ? '🎤'
          : '🎥';
      final caption = chatMediaCaption(m['body']);
      return '$icon ${caption ?? chatMediaDefaultBody(type)}';
    }
    final text = '${m['body'] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'New message';
    return text.length > 200 ? '${text.substring(0, 199)}…' : text;
  }

  /// A stable notification id per conversation (within this app run).
  /// Never one of the ids session reminders use (Sprint 4 US6).
  static int _notificationId(String requestId) =>
      SessionReminders.outsideReminderIds(requestId.hashCode & 0x7fffffff);

  @visibleForTesting
  static void disposeForTest() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _openChats.clear();
  }
}
