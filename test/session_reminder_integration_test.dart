// Sprint 4 US6: how session reminders fit with the app's other local
// notifications (Dana's ChatAlertService). MOCKED: the plugin's method
// channel; nothing is shown on a device.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/chat_alert_service.dart';
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

  group('chat alerts clearing notifications', () {
    test('clears chat alerts and pushes, keeps session reminders, and never '
        'touches scheduled ones', () async {
      active = [
        {'id': 11, 'channelId': 'maak_alerts', 'tag': null},
        {'id': 0, 'channelId': 'maak_calls', 'tag': 'call-r1'},
        {'id': 12, 'channelId': SessionReminders.channelId, 'tag': null},
      ];
      await ChatAlertService.clearShownForTesting();
      final cancels = calls.where((c) => c.method == 'cancel').toList();
      expect(cancels.map((c) => (c.arguments as Map)['id']), [11, 0]);
      expect((cancels[1].arguments as Map)['tag'], 'call-r1');
      expect(calls.map((c) => c.method), isNot(contains('cancelAll')));
    });

    test(
      'if the shown list cannot be read, everything is cleared as before',
      () async {
        active = PlatformException(code: 'unavailable');
        await ChatAlertService.clearShownForTesting();
        expect(calls.map((c) => c.method), contains('cancelAll'));
      },
    );
  });
}
