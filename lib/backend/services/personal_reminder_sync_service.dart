
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_alert_service.dart';
import 'personal_reminder_service.dart';
import 'personal_reminder_notification_service.dart';

class PersonalReminderSyncService {
  PersonalReminderSyncService._();

  static bool _initialized = false;

  static String? _userId;

  static StreamSubscription<AuthState>? _authSubscription;

  static AppLifecycleListener? _lifecycle;

  static Future<void> _queue = Future.value();

  static SupabaseClient get _client =>
      Supabase.instance.client;

  static void initialize() {
    if (_initialized ||
        !PersonalReminderNotificationService.isSupported) {
      return;
    }

    _initialized = true;

    _userId = _client.auth.currentUser?.id;

    _enqueue(_sync);

    _authSubscription =
        _client.auth.onAuthStateChange.listen((state) {
          final newUserId = state.session?.user.id;

          if (newUserId != _userId) {
            _userId = newUserId;

            _enqueue(() async {
              await PersonalReminderNotificationService
                  .cancelAllPersonalReminders();

              await _sync();
            });
          }
        });

    _lifecycle = AppLifecycleListener(
      onResume: () {
        _enqueue(_sync);
      },
    );
  }

  static void _enqueue(
      Future<void> Function() operation,
      ) {
    _queue = _queue.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint(
          'Personal reminder sync failed: $error',
        );
      }
    });
  }

  static Future<void> _sync() async {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      await PersonalReminderNotificationService
          .cancelAllPersonalReminders();
      return;
    }

    // Fetch reminders before changing notifications.
    final reminders =
    await PersonalReminderService.getReminders();

    if (_client.auth.currentUser?.id != userId) {
      return;
    }

    final upcoming = <String, Map<String, dynamic>>{
      for (final reminder in reminders)
        if (reminder['is_completed'] != true)
          reminder['id'].toString(): reminder,
    };

    final plugin = ChatAlertService.notificationPlugin;

    final pending =
    await plugin.pendingNotificationRequests();

    final existingIds = <String>{};

    // Cancel notifications that no longer belong
    // to an upcoming reminder.
    for (final notification in pending) {
      final payload = notification.payload;

      if (payload == null ||
          !payload.startsWith('personal_reminder:')) {
        continue;
      }

      if (_client.auth.currentUser?.id != userId) {
        return;
      }

      final reminderId =
      PersonalReminderNotificationService
          .reminderIdFromPayload(payload);

      if (!upcoming.containsKey(reminderId)) {
        await plugin.cancel(id: notification.id);
      } else {
        existingIds.add(reminderId);
      }
    }

    // Check permissions without showing a prompt.
    final allowed =
    await PersonalReminderNotificationService
        .hasPermissions();

    if (!allowed) {
      debugPrint(
        'Personal reminder sync: permissions unavailable',
      );
      return;
    }

    // Restore missing notifications only.
    for (final entry in upcoming.entries) {
      if (_client.auth.currentUser?.id != userId) {
        return;
      }

      final isMonthly =
          entry.value['repeat_type'] == 'monthly';

      if (!isMonthly && existingIds.contains(entry.key)) {
        continue;
      }

      try {
        await PersonalReminderNotificationService
            .scheduleReminder(
          entry.value,
          requestPermission: false,
        );
      } catch (error) {
        debugPrint(
          'Could not restore reminder notification: $error',
        );
      }
    }

    debugPrint('Personal reminder sync completed');
  }
}
