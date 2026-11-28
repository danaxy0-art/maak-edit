// Sprint 4 US6: how session reminders fit with the app's other local
// notifications (Dana's ChatAlertService). MOCKED: the plugin's method
// channel; nothing is shown on a device.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/chat_alert_service.dart';
import 'package:maak_app/backend/services/push_notification_service.dart';
import 'package:maak_app/backend/services/session_reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;
  late Object? active;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    active = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getActiveNotifications') {
            if (active is Exception) throw active!;
            return active;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('notification ids', () {
    test('ids derived elsewhere never fall in the reminders\' range', () {
      const first = SessionReminders.firstId, last = SessionReminders.lastId;
      for (final id in [
        first,
        first + 1,
        (first + last) ~/ 2,
        last - 1,
        last,
      ]) {
        final mapped = SessionReminders.outsideReminderIds(id);
        expect(mapped < first || mapped > last, isTrue, reason: '$id');
        expect(mapped, inInclusiveRange(0, 0x7fffffff));
      }
    });

    test('ids outside the range are unchanged', () {
      for (final id in [
        0,
        1,
        SessionReminders.firstId - 1,
        SessionReminders.lastId + 1,
        0x7fffffff,
      ]) {
        expect(SessionReminders.outsideReminderIds(id), id);
      }
    });
  });

  group('tapping a notification', () {
    tearDown(() => PushNotificationService.pendingOpen.value = null);

    NotificationResponse tap(String payload) => NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: payload,
    );

    test('a session reminder opens Sessions, marking nothing as read', () {
      ChatAlertService.onTapForTesting(tap(SessionReminders.tapPayload));
      expect(PushNotificationService.pendingOpen.value, {
        'id': null,
        'kind': 'support_session',
        'reference_id': null,
      });
      expect(calls.map((c) => c.method), isNot(contains('cancel')));
    });

    test('a chat alert still opens its conversation', () {
      const chat = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
      ChatAlertService.onTapForTesting(tap(chat));
      expect(PushNotificationService.pendingOpen.value, {
        'id': null,
        'kind': 'message',
        'reference_id': chat,
      });
    });
  });

  group('chat alerts clearing notifications', () {
    test('clears chat alerts and pushes, keeps session and personal '
        'reminders, and never touches scheduled ones', () async {
      active = [
        {'id': 11, 'channelId': 'maak_alerts', 'tag': null},
        {'id': 0, 'channelId': 'maak_calls', 'tag': 'call-r1'},
        {'id': 12, 'channelId': SessionReminders.channelId, 'tag': null},
        {
          'id': -5,
          'channelId': 'maak_personal_reminders',
          'payload': 'personal_reminder:r1',
        },
      ];
      await ChatAlertService.clearShownForTesting();
      final cancels = calls.where((c) => c.method == 'cancel').toList();
      expect(cancels.map((c) => (c.arguments as Map)['id']), [11, 0]);
      expect((cancels[1].arguments as Map)['tag'], 'call-r1');
      expect(calls.map((c) => c.method), isNot(contains('cancelAll')));
    });

    test('if the shown list cannot be read, only known chat alerts are '
        'cleared (reminders stay)', () async {
      active = PlatformException(code: 'unavailable');
      await ChatAlertService.clearShownForTesting(['chat-1', 'chat-2']);
      expect(calls.map((c) => c.method), isNot(contains('cancelAll')));
      expect(calls.where((c) => c.method == 'cancel'), hasLength(2));
    });
  });
}
