// Sprint 4 US6: reminders before confirmed sessions
// (lib/backend/services/session_reminders.dart and
// device_session_reminders.dart). MOCKED: a fake scheduler and an in-memory
// store for the rules; a mocked plugin method channel for the Android
// scheduler. No real notification is scheduled or shown here.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/device_session_reminders.dart';
import 'package:maak_app/backend/services/session_reminders.dart';

/// Notifications by id, as the phone would hold them.
class FakeScheduler implements ReminderScheduler {
  @override
  bool isSupported = true;
  final scheduled = <int, ({DateTime at, String title, String body})>{};
  final canceled = <int>[];
  int calls = 0;

  @override
  Future<void> schedule({
    required int id,
    required DateTime atUtc,
    required String title,
    required String body,
  }) async {
    calls++;
    scheduled[id] = (at: atUtc, title: title, body: body);
  }

  @override
  Future<void> cancel(int id) async {
    calls++;
    canceled.add(id);
    scheduled.remove(id);
  }

  List<DateTime> get times =>
      scheduled.values.map((s) => s.at).toList()..sort();
}

class MemoryReminderStore implements ReminderStore {
  String? registry;
  final enabled = <String, bool>{};
  @override
  Future<String?> readRegistry() async => registry;
  @override
  Future<void> writeRegistry(String json) async => registry = json;
  @override
  Future<bool?> readEnabled(String userId) async => enabled[userId];
  @override
  Future<void> writeEnabled(String userId, bool value) async =>
      enabled[userId] = value;
}

final _now = DateTime.utc(2026, 11, 28, 12);

Map<String, dynamic> session({
  String id = 'booking-1',
  String slot = 'slot-1',
  String start = '2026-11-28T15:00:00Z',
  String end = '2026-11-28T16:00:00Z',
  String status = 'accepted',
  String? display,
  String role = 'help_seeker',
}) => {
  'id': id,
  'slot_id': slot,
  'starts_at': start,
  'ends_at': end,
  'status': status,
  'display_status': display ?? status,
  'role': role,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeScheduler scheduler;
  late MemoryReminderStore store;
  late SessionReminders reminders;

  setUp(() {
    scheduler = FakeScheduler();
    store = MemoryReminderStore();
    reminders = SessionReminders(scheduler: scheduler, store: store);
  });

  Future<void> sync(
    List<Map<String, dynamic>> sessions, {
    String user = 'user-a',
    DateTime? now,
  }) => reminders.reconcile(userId: user, sessions: sessions, now: now ?? _now);

  group('eligibility', () {
    test('a confirmed, upcoming session gets two reminders', () async {
      await sync([session()]);
      expect(scheduler.times, [
        DateTime.utc(2026, 11, 28, 14),
        DateTime.utc(2026, 11, 28, 14, 50),
      ]);
    });

    test('pending, declined, canceled, expired, live and finished sessions '
        'get none', () async {
      await sync([
        session(id: 'p', status: 'pending'),
        session(id: 'r', status: 'rejected'),
        session(id: 'c', status: 'canceled'),
        session(id: 'x', status: 'pending', display: 'expired'),
        session(id: 'l', display: 'live'),
        session(id: 'f', display: 'completed'),
      ]);
      expect(scheduler.scheduled, isEmpty);
    });

    test('a session that has started, or has bad data, gets none', () async {
      await sync([
        session(id: 's', start: '2026-11-28T11:00:00Z'),
        session(id: 'b', start: 'not a date'),
        session(id: 'e', start: '2026-11-28T15:00:00Z', end: '2026-11-28T15'),
        {'status': 'accepted', 'display_status': 'accepted'},
      ]);
      expect(scheduler.scheduled, isEmpty);
    });

    test('help seekers and volunteers both get them', () async {
      await sync([session(role: 'help_seeker')], user: 'seeker');
      final seeker = Map.of(scheduler.scheduled);
      final other = FakeScheduler();
      await SessionReminders(
        scheduler: other,
        store: MemoryReminderStore(),
      ).reconcile(
        userId: 'volunteer',
        sessions: [session(role: 'volunteer')],
        now: _now,
      );
      expect(seeker, hasLength(2));
      expect(other.scheduled, hasLength(2));
      expect(other.times, scheduler.times);
    });
  });

  group('reminder times', () {
    test('1 hour and 10 minutes before, with neutral text', () async {
      await sync([session()]);
      final bodies = scheduler.scheduled.values.map((s) => s.body).toSet();
      expect(bodies, {
        "Your Ma'ak session starts in 1 hour.",
        "Your Ma'ak session starts in 10 minutes.",
      });
      for (final s in scheduler.scheduled.values) {
        expect(s.title, 'Upcoming support session');
      }
    });

    test('a reminder time that has passed is skipped', () async {
      // 40 minutes before: only the 10-minute reminder is still ahead.
      await sync([session()], now: DateTime.utc(2026, 11, 28, 14, 20));
      expect(scheduler.times, [DateTime.utc(2026, 11, 28, 14, 50)]);
      // 5 minutes before: none.
      final late = FakeScheduler();
      await SessionReminders(
        scheduler: late,
        store: MemoryReminderStore(),
      ).reconcile(
        userId: 'user-a',
        sessions: [session()],
        now: DateTime.utc(2026, 11, 28, 14, 55),
      );
      expect(late.scheduled, isEmpty);
    });

    test('exactly at the reminder time counts as passed', () async {
      await sync([session()], now: DateTime.utc(2026, 11, 28, 14));
      expect(scheduler.times, [DateTime.utc(2026, 11, 28, 14, 50)]);
    });
  });

  group('time zones', () {
    test(
      'the same instant written with any offset gives the same reminders',
      () async {
        await sync([
          session(
            start: '2026-11-28T18:00:00+03:00',
            end: '2026-11-28T19:00:00+03:00',
          ),
        ]);
        final riyadh = scheduler.times;
        final other = FakeScheduler();
        await SessionReminders(
          scheduler: other,
          store: MemoryReminderStore(),
        ).reconcile(
          userId: 'user-a',
          sessions: [
            session(
              start: '2026-11-28T10:00:00-05:00',
              end: '2026-11-28T11:00:00-05:00',
            ),
          ],
          now: _now,
        );
        expect(riyadh, [
          DateTime.utc(2026, 11, 28, 14),
          DateTime.utc(2026, 11, 28, 14, 50),
        ]);
        expect(other.times, riyadh);
        for (final t in riyadh) {
          expect(t.isUtc, isTrue);
        }
      },
    );

    test('the text names no clock time, so it is right in any zone', () {
      for (final lead in SessionReminders.leadTimes) {
        expect(SessionReminders.bodyFor(lead), isNot(contains(':')));
      }
    });
  });

  group('keeping in step', () {
    test('reconciling again changes nothing and adds no duplicate', () async {
      await sync([session()]);
      final first = Map.of(scheduler.scheduled);
      await sync([session()]);
      await sync([session()]);
      expect(scheduler.scheduled.keys, first.keys);
      expect(scheduler.scheduled, hasLength(2));
      expect(scheduler.canceled, isEmpty);
    });

    test('the same booking listed twice is scheduled once', () async {
      await sync([session(), session()]);
      expect(scheduler.scheduled, hasLength(2));
    });

    test('rescheduled: the old times are canceled, the new ones set, under '
        'the same ids', () async {
      await sync([session()]);
      final ids = scheduler.scheduled.keys.toSet();
      await sync([
        session(
          slot: 'slot-2',
          start: '2026-11-29T10:00:00Z',
          end: '2026-11-29T11:00:00Z',
        ),
      ]);
      expect(scheduler.canceled.toSet(), ids);
      expect(scheduler.scheduled.keys.toSet(), ids);
      expect(scheduler.times, [
        DateTime.utc(2026, 11, 29, 9),
        DateTime.utc(2026, 11, 29, 9, 50),
      ]);
    });

    test('canceled: its reminders are canceled', () async {
      await sync([
        session(),
        session(
          id: 'booking-2',
          start: '2026-11-30T10:00:00Z',
          end: '2026-11-30T11:00:00Z',
        ),
      ]);
      expect(scheduler.scheduled, hasLength(4));
      await sync([
        session(status: 'canceled'),
        session(
          id: 'booking-2',
          start: '2026-11-30T10:00:00Z',
          end: '2026-11-30T11:00:00Z',
        ),
      ]);
      expect(scheduler.canceled, hasLength(2));
      expect(scheduler.times, [
        DateTime.utc(2026, 11, 30, 9),
        DateTime.utc(2026, 11, 30, 9, 50),
      ]);
    });

    test('gone from the list, or back to pending: canceled', () async {
      await sync([session()]);
      await sync([session(status: 'pending')]);
      expect(scheduler.scheduled, isEmpty);
      await sync([session()]);
      await sync([]);
      expect(scheduler.scheduled, isEmpty);
    });

    test('a reminder already shown is not removed while the session is '
        'still on', () async {
      await sync([session()]);
      // 14:20: the 1-hour reminder (14:00) was shown.
      await sync([session()], now: DateTime.utc(2026, 11, 28, 14, 20));
      expect(scheduler.canceled, isEmpty);
    });

    test(
      'after the session started, its reminders are simply forgotten',
      () async {
        await sync([session()]);
        await sync([session()], now: DateTime.utc(2026, 11, 28, 15, 30));
        expect(scheduler.canceled, isEmpty);
        expect(store.registry, isNot(contains('booking-1')));
      },
    );

    test('every reminder has its own id, kept across app restarts', () async {
      await sync([
        session(),
        session(
          id: 'booking-2',
          start: '2026-11-30T10:00:00Z',
          end: '2026-11-30T11:00:00Z',
        ),
      ]);
      final ids = scheduler.scheduled.keys.toSet();
      expect(ids, hasLength(4));
      for (final id in ids) {
        expect(
          id,
          inInclusiveRange(SessionReminders.firstId, SessionReminders.lastId),
        );
      }
      // A new app run reads the same registry: same ids, no new ones.
      final again = FakeScheduler();
      await SessionReminders(scheduler: again, store: store).reconcile(
        userId: 'user-a',
        sessions: [
          session(),
          session(
            id: 'booking-2',
            start: '2026-11-30T10:00:00Z',
            end: '2026-11-30T11:00:00Z',
          ),
        ],
        now: _now,
      );
      expect(again.scheduled.keys.toSet(), ids);
      expect(again.canceled, isEmpty);
    });

    test(
      'ids are not reused while in use, also after wrapping around',
      () async {
        store.registry =
            '{"next": ${SessionReminders.lastId}, "reminders": ['
            '{"user_id":"user-a","booking_id":"old","lead_minutes":10,'
            '"id":${SessionReminders.firstId},"at":"2026-11-28T13:00:00Z",'
            '"starts_at":"2026-11-28T13:10:00Z"}]}';
        await sync([
          session(
            id: 'old',
            start: '2026-11-28T13:10:00Z',
            end: '2026-11-28T14:00:00Z',
          ),
          session(),
        ]);
        final ids = scheduler.scheduled.keys.toList();
        expect(ids.toSet(), hasLength(ids.length));
        expect(ids, contains(SessionReminders.lastId));
        expect(ids, contains(SessionReminders.firstId));
      },
    );

    test('an unreadable registry starts afresh', () async {
      store.registry = 'not json';
      await sync([session()]);
      expect(scheduler.scheduled, hasLength(2));
    });
  });

  group('accounts', () {
    test(
      'another account signing in cancels the first one\'s reminders',
      () async {
        await sync([session()], user: 'user-a');
        final a = scheduler.scheduled.keys.toSet();
        await sync([
          session(
            id: 'booking-b',
            start: '2026-11-30T10:00:00Z',
            end: '2026-11-30T11:00:00Z',
          ),
        ], user: 'user-b');
        expect(scheduler.canceled.toSet(), a);
        expect(scheduler.scheduled.keys.toSet().intersection(a), isEmpty);
        expect(scheduler.scheduled, hasLength(2));
      },
    );

    test(
      'the same booking for two accounts on one phone gets separate ids',
      () async {
        await sync([session()], user: 'user-a');
        final a = scheduler.scheduled.keys.toSet();
        await sync([session()], user: 'user-b');
        expect(scheduler.scheduled.keys.toSet().intersection(a), isEmpty);
      },
    );

    test('signing out cancels every reminder on this phone', () async {
      await sync([session()], user: 'user-a');
      await reminders.cancelAll();
      expect(scheduler.scheduled, isEmpty);
      expect(store.registry, contains('"reminders":[]'));
    });
  });

  group('opt-out', () {
    test('on by default; turning it off cancels at once', () async {
      expect(await reminders.isEnabled('user-a'), isTrue);
      await sync([session()]);
      await reminders.setEnabled('user-a', false);
      expect(scheduler.scheduled, isEmpty);
      expect(await reminders.isEnabled('user-a'), isFalse);
    });

    test('while off nothing is scheduled; on again schedules them', () async {
      await reminders.setEnabled('user-a', false);
      await sync([session()]);
      expect(scheduler.scheduled, isEmpty);
      await reminders.setEnabled('user-a', true);
      await sync([session()]);
      expect(scheduler.scheduled, hasLength(2));
    });

    test('the setting belongs to one account only', () async {
      await reminders.setEnabled('user-a', false);
      await sync([session()], user: 'user-b');
      expect(scheduler.scheduled, hasLength(2));
    });
  });

  group('session pushes received while the app is closed', () {
    final b2 = session(
      id: 'booking-2',
      start: '2026-11-30T10:00:00Z',
      end: '2026-11-30T11:00:00Z',
    );

    test(
      'a push for a booking cancels only that booking\'s reminders',
      () async {
        await sync([session(), b2]);
        expect(scheduler.scheduled, hasLength(4));
        final handled = await reminders.handlePush({
          'kind': 'support_session',
          'reference_id': 'booking-1',
          'id': 'notification-1',
        });
        expect(handled, isTrue);
        expect(scheduler.canceled, hasLength(2));
        expect(scheduler.times, [
          DateTime.utc(2026, 11, 30, 9),
          DateTime.utc(2026, 11, 30, 9, 50),
        ]);
        expect(store.registry, isNot(contains('"booking-1"')));
      },
    );

    test('the next reconcile schedules the moved session again, under the '
        'same rules', () async {
      await sync([session()]);
      await reminders.handlePush({
        'kind': 'support_session',
        'reference_id': 'booking-1',
      });
      expect(scheduler.scheduled, isEmpty);
      await sync([
        session(
          slot: 'slot-2',
          start: '2026-11-29T10:00:00Z',
          end: '2026-11-29T11:00:00Z',
        ),
      ]);
      expect(scheduler.times, [
        DateTime.utc(2026, 11, 29, 9),
        DateTime.utc(2026, 11, 29, 9, 50),
      ]);
    });

    test(
      'other pushes, or a session push without a booking, change nothing',
      () async {
        await sync([session()]);
        for (final data in <Map<String, dynamic>>[
          {'kind': 'message', 'reference_id': 'booking-1'},
          {'kind': 'voice_call', 'reference_id': 'booking-1'},
          {'kind': 'support_session'},
          {'kind': 'support_session', 'reference_id': ''},
          {},
        ]) {
          expect(await reminders.handlePush(data), isFalse);
        }
        expect(scheduler.canceled, isEmpty);
        expect(scheduler.scheduled, hasLength(2));
      },
    );

    test(
      'a push for a booking without reminders (just confirmed) is safe',
      () async {
        await sync([session()]);
        expect(
          await reminders.handlePush({
            'kind': 'support_session',
            'reference_id': 'booking-new',
          }),
          isTrue,
        );
        expect(scheduler.canceled, isEmpty);
      },
    );
  });

  test('unsupported platform: nothing is scheduled or canceled', () async {
    scheduler.isSupported = false;
    await sync([session()]);
    await reminders.cancelAll();
    await reminders.setEnabled('user-a', false);
    expect(scheduler.calls, 0);
  });

  group('Android scheduler (mocked plugin channel)', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    late List<MethodCall> calls;
    late bool exactAllowed;
    late bool exactFails;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls = [];
      exactAllowed = true;
      exactFails = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'canScheduleExactNotifications':
                return exactAllowed;
              case 'zonedSchedule':
                final mode =
                    (call.arguments
                        as Map)['platformSpecifics']['scheduleMode'];
                if (exactFails && mode == 'exactAllowWhileIdle') {
                  throw PlatformException(code: 'exact_alarms_not_permitted');
                }
                return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    Map<dynamic, dynamic> lastSchedule() =>
        calls.lastWhere((c) => c.method == 'zonedSchedule').arguments as Map;

    Future<void> scheduleOne() => LocalReminderScheduler().schedule(
      id: 7,
      atUtc: DateTime.utc(2026, 11, 28, 14, 50),
      title: SessionReminders.title,
      body: SessionReminders.bodyFor(const Duration(minutes: 10)),
    );

    test('exact alarms allowed: exact timing, at the UTC instant', () async {
      await scheduleOne();
      final args = lastSchedule();
      expect(args['platformSpecifics']['scheduleMode'], 'exactAllowWhileIdle');
      expect(args['timeZoneName'], 'UTC');
      expect(args['scheduledDateTime'], '2026-11-28T14:50:00');
      expect(args['id'], 7);
      expect(args['payload'], SessionReminders.tapPayload);
      expect(
        args['platformSpecifics']['channelId'],
        LocalReminderScheduler.channelId,
      );
    });

    test('exact alarms not allowed: approximate timing instead', () async {
      exactAllowed = false;
      await scheduleOne();
      expect(
        lastSchedule()['platformSpecifics']['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    });

    test('exact alarms withdrawn while scheduling: falls back, still '
        'scheduled once', () async {
      exactFails = true;
      await scheduleOne();
      final schedules = calls.where((c) => c.method == 'zonedSchedule');
      expect(schedules, hasLength(2));
      expect(
        lastSchedule()['platformSpecifics']['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    });

    test('cancel removes that one id', () async {
      await LocalReminderScheduler().cancel(7);
      final cancel = calls.singleWhere((c) => c.method == 'cancel');
      expect((cancel.arguments as Map)['id'], 7);
    });

    test('supported on Android only', () {
      expect(sessionRemindersSupported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(sessionRemindersSupported, isFalse);
      expect(LocalReminderScheduler().isSupported, isFalse);
    });
  });
}
