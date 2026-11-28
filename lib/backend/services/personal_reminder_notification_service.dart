import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'chat_alert_service.dart';

class PersonalReminderNotificationService {
  PersonalReminderNotificationService._();
  static FlutterLocalNotificationsPlugin get _plugin => ChatAlertService.notificationPlugin;
  static const _channelId = 'maak_personal_reminders';
  static const _channelName = 'Personal health reminders';
  static const monthlyHorizon = 12;
  static bool _initialized = false;
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void initialize() {
    if (_initialized || !isSupported) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    if (await android.requestNotificationsPermission() == false) return false;
    if (await android.canScheduleExactNotifications() == true) return true;
    return await android.requestExactAlarmsPermission() ?? false;
  }

  static Future<bool> hasPermissions() async {
    if (!isSupported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.areNotificationsEnabled() == true &&
        await android.canScheduleExactNotifications() == true;
  }

  static int notificationId(String reminderId) {
    int hash = 0;
    for (final unit in reminderId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return -1 - hash;
  }

  static String reminderIdFromPayload(String payload) =>
      payload.substring('personal_reminder:'.length).split(':').first;

  static List<tz.TZDateTime> _monthlyTimes(Map<String, dynamic> reminder) {
    initialize();
    final location = tz.getLocation('Asia/Riyadh');
    final start = tz.TZDateTime.from(DateTime.parse(reminder['scheduled_at'].toString()), location);
    final anchor = (reminder['anchor_day'] as num?)?.toInt() ?? start.day;
    final lead = Duration(minutes: (reminder['remind_before_minutes'] as num?)?.toInt() ?? 0);
    final now = tz.TZDateTime.now(location);
    final times = <tz.TZDateTime>[];
    final elapsedMonths = (now.year - start.year) * 12 + now.month - start.month;
    for (int offset = elapsedMonths > 1 ? elapsedMonths - 1 : 0; times.length < monthlyHorizon; offset++) {
      final month = tz.TZDateTime(location, start.year, start.month + offset);
      final lastDay = tz.TZDateTime(location, month.year, month.month + 1, 0).day;
      final day = anchor.clamp(1, lastDay).toInt();
      final occurrence = offset == 0 ? start : tz.TZDateTime(location, month.year, month.month, day, start.hour, start.minute, start.second, start.millisecond, start.microsecond);
      final time = occurrence.subtract(lead);
      if (time.isAfter(now)) times.add(time);
    }
    return times;
  }

  static String _monthlyPayload(String id, tz.TZDateTime time) => 'personal_reminder:$id:monthly:${time.millisecondsSinceEpoch}';

  static Future<void> _schedule(int id, tz.TZDateTime time, String payload, {DateTimeComponents? components}) async {
    await _plugin.zonedSchedule(
      id: id,
      title: 'Ma’ak Health Reminder',
      body: 'You have a personal health reminder.',
      scheduledDate: time,
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
        _channelId, _channelName,
        channelDescription: 'Personal appointments and health reminders',
        importance: Importance.high, priority: Priority.high, playSound: true, enableVibration: true,
      )),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: components,
      payload: payload,
    );
  }

  static Future<bool> scheduleReminder(Map<String, dynamic> reminder, {bool requestPermission = true}) async {
    if (!isSupported) return false;
    initialize();
    final id = reminder['id'].toString();
    if (reminder['is_completed'] == true) {
      await cancelReminder(id);
      return false;
    }
    final allowed = requestPermission ? await requestPermissions() : await hasPermissions();
    if (!allowed) return false;
    final repeat = reminder['repeat_type'] as String? ?? 'none';
    if (repeat == 'monthly') {
      final times = _monthlyTimes(reminder);
      final desired = <String, tz.TZDateTime>{for (final time in times) _monthlyPayload(id, time): time};
      final pending = await _plugin.pendingNotificationRequests();
      final existing = <String>{};
      for (final n in pending) {
        final payload = n.payload;
        if (payload == null || !payload.startsWith('personal_reminder:') || reminderIdFromPayload(payload) != id) continue;
        if (!desired.containsKey(payload)) {
          await _plugin.cancel(id: n.id);
        } else {
          existing.add(payload);
        }
      }
      for (final entry in desired.entries) {
        if (!existing.contains(entry.key)) {
          await _schedule(notificationId(entry.key), entry.value, entry.key);
        }
      }
      return true;
    }
    await cancelReminder(id);
    final location = tz.getLocation('Asia/Riyadh');
    final lead = Duration(minutes: (reminder['remind_before_minutes'] as num?)?.toInt() ?? 0);
    var time = tz.TZDateTime.from(DateTime.parse(reminder['scheduled_at'].toString()), location).subtract(lead);
    final now = tz.TZDateTime.now(location);
    DateTimeComponents? components;
    if (repeat == 'daily' || repeat == 'weekly') {
      final interval = Duration(days: repeat == 'daily' ? 1 : 7);
      components = repeat == 'daily' ? DateTimeComponents.time : DateTimeComponents.dayOfWeekAndTime;
      if (!time.isAfter(now)) {
        final steps = now.difference(time).inMilliseconds ~/ interval.inMilliseconds + 1;
        time = time.add(Duration(milliseconds: interval.inMilliseconds * steps));
      }
    }
    if (!time.isAfter(now)) return false;
    await _schedule(notificationId(id), time, 'personal_reminder:$id', components: components);
    return true;
  }

  static Future<void> cancelReminder(String reminderId) async {
    if (!isSupported) return;
    await _plugin.cancel(id: notificationId(reminderId));
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      final payload = n.payload;
      if (payload != null && payload.startsWith('personal_reminder:') && reminderIdFromPayload(payload) == reminderId) {
        await _plugin.cancel(id: n.id);
      }
    }
  }

  static Future<void> cancelAllPersonalReminders() async {
    if (!isSupported) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.payload?.startsWith('personal_reminder:') == true) await _plugin.cancel(id: n.id);
    }
  }
}
