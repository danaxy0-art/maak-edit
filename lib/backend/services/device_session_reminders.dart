import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'session_reminders.dart';
import 'supabase_service.dart';

// Sprint 4 US6 on the phone: flutter_local_notifications schedules each
// reminder with Android's AlarmManager, so it is shown even when the app is
// closed (not when it was force-stopped). The plugin's boot receiver
// (AndroidManifest.xml) restores scheduled reminders after a restart.
//
// The plugin itself is initialised by ChatAlertService (Dana's new-message
// alerts), which owns the tap handler; this file never initialises it again,
// so her handler stays in place. Reminders carry SessionReminders.tapPayload,
// which that handler sends to the Sessions screen (also when the tap launches
// the app). ChatAlertService leaves notifications on this channel alone when
// it clears its own.

/// Firebase calls this, in its own isolate, for each push received while the
/// app is closed or in the background (registered in main.dart). Only Razan's
/// session pushes matter here: that booking's reminders are canceled. No
/// network call and no sign-in happen here.
@pragma('vm:entry-point')
Future<void> sessionRemindersOnBackgroundMessage(RemoteMessage message) async {
  if (!sessionRemindersSupported) return;
  // Plugins implemented in Dart (the notification and preferences plugins on
  // Android) must be registered in a background isolate.
  DartPluginRegistrant.ensureInitialized();
  try {
    await AppSessionReminders.reminders.handlePush(message.data);
  } catch (e) {
    debugPrint('Session reminders: background push: ${e.runtimeType}');
  }
}

/// Android only; nothing is scheduled on the web, desktop or iOS.
bool get sessionRemindersSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Exact timing when the app may use exact alarms, otherwise Android's
/// approximate timing (usually within a few minutes).
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  static const channelId = SessionReminders.channelId;
  static const channelName = 'Session reminders';

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  bool get isSupported => sessionRemindersSupported;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Reminders before your confirmed support sessions',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      // Same icon ChatAlertService initialises the plugin with.
      icon: '@mipmap/ic_launcher',
    ),
  );

  @override
  Future<void> schedule({
    required int id,
    required DateTime atUtc,
    required String title,
    required String body,
  }) async {
    // An exact instant: a time-zone change on the phone never moves it.
    final at = tz.TZDateTime.from(atUtc.toUtc(), tz.UTC);
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: mode,
      payload: SessionReminders.tapPayload,
    );
    if (await canScheduleExact()) {
      try {
        return await go(AndroidScheduleMode.exactAllowWhileIdle);
      } on PlatformException {
        // Permission withdrawn in the meantime: approximate timing instead.
      }
    }
    await go(AndroidScheduleMode.inexactAllowWhileIdle);
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  /// Exact alarms allowed (always below Android 12; a setting from 12 on).
  Future<bool> canScheduleExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's "Alarms & reminders" setting for the app.
  Future<void> requestExact() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Notifications allowed for the app (null if unknown).
  Future<bool?> notificationsEnabled() async {
    try {
      return await _android?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }
}

/// shared_preferences: one registry for this device, and one setting per
/// account.
class PrefsReminderStore implements ReminderStore {
  static const _registry = 'maak.session_reminders.v1.registry';
  static const _enabled = 'maak.session_reminders.v1.enabled';

  @override
  Future<String?> readRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    // The background push handler runs in another isolate with its own
    // cached copy: read what is on disk, not a copy that may be stale.
    await prefs.reload();
    return prefs.getString(_registry);
  }

  @override
  Future<void> writeRegistry(String json) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      _registry,
      json,
    );
    if (!ok) throw StateError('Could not save session reminders.');
  }

  @override
  Future<bool?> readEnabled(String userId) async =>
      (await SharedPreferences.getInstance()).getBool('$_enabled.$userId');

  @override
  Future<void> writeEnabled(String userId, bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(
      '$_enabled.$userId',
      enabled,
    );
  }
}

/// Keeps the signed-in member's reminders in step with their sessions.
///
/// Fresh session data is loaded, and reminders reconciled:
///  * when the app starts with someone signed in, and after sign-in;
///  * when the app returns to the foreground;
///  * when a support_session notification arrives for this member while the
///    app runs (the other participant confirmed, canceled or rescheduled);
///  * when the Sessions screen shows a change ([sessionsChanged]), which
///    covers this member's own accept, cancel and reschedule.
/// Sign-out cancels every reminder on this device. If the session list
/// cannot be loaded, the reminders already scheduled are left as they are.
class AppSessionReminders {
  AppSessionReminders._();

  static final scheduler = LocalReminderScheduler();
  static final reminders = SessionReminders(
    scheduler: scheduler,
    store: PrefsReminderStore(),
  );

  static bool _started = false;
  static RealtimeChannel? _channel;
  static String? _channelUser;
  static AppLifecycleListener? _lifecycle;
  static Timer? _debounce;

  /// Call once, after runApp and after ChatAlertService.init().
  static void init() {
    if (_started || !sessionRemindersSupported) return;
    _started = true;
    _lifecycle = AppLifecycleListener(onResume: refresh);
    SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(_unsubscribe());
        unawaited(reminders.cancelAll());
      } else if (state.event == AuthChangeEvent.signedIn) {
        refresh();
      }
    });
    if (SupabaseService.currentUser != null) refresh();
  }

  /// The Sessions screen showed a session change: reconcile shortly (calls
  /// within half a second are combined).
  static void sessionsChanged() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), refresh);
  }

  /// The setting on the Account settings page.
  static Future<bool> isEnabled() async {
    final user = SupabaseService.currentUser?.id;
    return user != null && await reminders.isEnabled(user);
  }

  static Future<void> setEnabled(bool enabled) async {
    final user = SupabaseService.currentUser?.id;
    if (user == null) return;
    await reminders.setEnabled(user, enabled);
    if (enabled) await refresh();
  }

  static Future<void>? _running;
  static bool _again = false;

  /// Loads the member's sessions and reconciles. Overlapping calls run once
  /// more after the current one, never side by side.
  static Future<void> refresh() {
    if (!_started) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _refreshOnce().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        unawaited(refresh());
      }
    });
    return _running = run;
  }

  static Future<void> _refreshOnce() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    _subscribe(user.id);
    final List<Map<String, dynamic>> sessions;
    try {
      sessions = await SupabaseService.getMySessions();
    } catch (e) {
      // Offline or refused: keep what is scheduled rather than guess.
      debugPrint('Session reminders: sessions unavailable: ${e.runtimeType}');
      return;
    }
    // Signed out or switched while loading: that answer is not for this one.
    if (SupabaseService.currentUser?.id != user.id) return;
    try {
      await reminders.reconcile(userId: user.id, sessions: sessions);
    } catch (e) {
      debugPrint('Session reminders: could not schedule: ${e.runtimeType}');
    }
  }

  // Listens for this member's new support_session notifications (Razan's
  // rows) only as a signal to reload; their content is never used.
  static void _subscribe(String userId) {
    if (_channelUser == userId && _channel != null) return;
    unawaited(_unsubscribe());
    _channelUser = userId;
    _channel = SupabaseService.client
        .channel('maak-session-reminders-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (payload.newRecord['kind'] == 'support_session') {
              sessionsChanged();
            }
          },
        )
        .subscribe();
  }

  static Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    _channelUser = null;
    if (channel == null) return;
    try {
      await SupabaseService.client.removeChannel(channel);
    } catch (_) {}
  }

  @visibleForTesting
  static void debugDispose() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _debounce?.cancel();
    _started = false;
  }
}
