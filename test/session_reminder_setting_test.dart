// Sprint 4 US6: the "Session reminders" switch on Account settings
// (lib/frontend/redesign/session_reminder_setting.dart). MOCKED settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/session_reminder_setting.dart';

class FakeSettings implements ReminderSettings {
  @override
  bool supported = true;
  bool enabled = true;
  bool? notifications = true;
  bool exact = true;
  int exactRequests = 0;
  final changes = <bool>[];

  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    changes.add(value);
    enabled = value;
  }

  @override
  Future<bool?> notificationsEnabled() async => notifications;
  @override
  Future<bool> exactTiming() async => exact;
  @override
  Future<void> requestExactTiming() async => exactRequests++;
}

Future<void> pump(WidgetTester tester, FakeSettings s) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SessionReminderSetting(settings: s)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on by default; turning it off and on again', (tester) async {
    final s = FakeSettings();
    await pump(tester, s);
    expect(find.text(SessionReminderSetting.title), findsOneWidget);
    expect(find.text(SessionReminderSetting.subtitle), findsOneWidget);
    final sw = find.byKey(const ValueKey('session_reminders_switch'));
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.changes, [false]);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.changes, [false, true]);
  });

  testWidgets('notifications blocked on the phone: says so', (tester) async {
    await pump(tester, FakeSettings()..notifications = false);
    expect(find.text(SessionReminderSetting.blocked), findsOneWidget);
    expect(find.text(SessionReminderSetting.approximate), findsNothing);
  });

  testWidgets('no exact alarms: offers exact timing', (tester) async {
    final s = FakeSettings()..exact = false;
    await pump(tester, s);
    expect(find.text(SessionReminderSetting.approximate), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session_reminders_exact')));
    expect(s.exactRequests, 1);
  });

  testWidgets('turned off: no permission notes', (tester) async {
    await pump(
      tester,
      FakeSettings()
        ..enabled = false
        ..notifications = false
        ..exact = false,
    );
    expect(find.text(SessionReminderSetting.blocked), findsNothing);
    expect(find.text(SessionReminderSetting.approximate), findsNothing);
  });

  testWidgets('unsupported platform (web): nothing shown', (tester) async {
    await pump(tester, FakeSettings()..supported = false);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SessionReminderSetting(
                settings: FakeSettings()..exact = false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
