// Sprint 4 US5: the device_calendar_plus gateway and the shared_preferences
// store (lib/backend/services/device_session_calendar.dart). MOCKED: a fake
// plugin object and in-memory preferences; no real calendar is touched.
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/device_session_calendar.dart';
import 'package:maak_app/backend/services/session_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every call; answers like the plugin would.
class FakePlugin implements DeviceCalendar {
  CalendarPermissionStatus status = CalendarPermissionStatus.notDetermined;
  CalendarPermissionStatus afterPrompt = CalendarPermissionStatus.granted;
  List<Calendar> calendars = const [
    Calendar(id: 'cal-1', name: 'Personal', readOnly: false, isPrimary: true),
  ];
  final events = <String, Event>{};
  final calls = <String>[];
  bool dropAfterCreate = false;
  CalendarAccessLevel? requestedLevel;

  @override
  Future<CalendarPermissionStatus> hasPermissions() async {
    calls.add('has');
    return status;
  }

  @override
  Future<CalendarPermissionStatus> requestPermissions({
    CalendarAccessLevel level = CalendarAccessLevel.full,
  }) async {
    calls.add('request');
    requestedLevel = level;
    return status = afterPrompt;
  }

  @override
  Future<List<Calendar>> listCalendars() async => calendars;

  @override
  Future<String> createEvent({
    String? calendarId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    bool isAllDay = false,
    String? description,
    String? location,
    String? url,
    String? timeZone,
    EventAvailability availability = EventAvailability.busy,
    RecurrenceRule? recurrenceRule,
    List<Duration>? reminders,
    EventOptionsAndroid? android,
  }) async {
    calls.add('create');
    final id = 'evt-${events.length + 1}';
    if (!dropAfterCreate) {
      events[id] = _event(id, title, startDate, endDate, description);
    }
    lastCreate = (title: title, start: startDate, timeZone: timeZone);
    return id;
  }

  ({String title, DateTime start, String? timeZone})? lastCreate;

  @override
  Future<Event?> getEvent(String id) async {
    calls.add('get');
    return events[id];
  }

  @override
  Future<void> updateEvent({
    required String instanceId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    Patch<String>? description,
    Patch<String>? location,
    Patch<String>? url,
    bool? isAllDay,
    String? timeZone,
    EventAvailability? availability,
    Patch<List<Duration>>? reminders,
    EventUpdateOptionsAndroid? android,
  }) async {
    calls.add('update');
    final old = events[instanceId];
    if (old == null) {
      throw const DeviceCalendarException(
        errorCode: DeviceCalendarError.notFound,
        message: 'gone',
      );
    }
    events[instanceId] = _event(
      instanceId,
      title ?? old.title,
      startDate ?? old.startDate,
      endDate ?? old.endDate,
      old.description,
    );
  }

  @override
  Future<void> openAppSettings() async => calls.add('settings');

  static Event _event(
    String id,
    String title,
    DateTime start,
    DateTime end,
    String? description,
  ) => Event(
    eventId: id,
    instanceId: id,
    calendarId: 'cal-1',
    title: title,
    description: description,
    startDate: start,
    endDate: end,
    isAllDay: false,
    availability: EventAvailability.busy,
    status: EventStatus.confirmed,
    isRecurring: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final _now = DateTime.utc(2026, 11, 27, 9);
Map<String, dynamic> _session({String slot = 'slot-1', int day = 28}) => {
  'id': 'booking-1',
  'slot_id': slot,
  'status': 'accepted',
  'display_status': 'accepted',
  'starts_at': '2026-11-${day}T15:00:00Z',
  'ends_at': '2026-11-${day}T16:00:00Z',
};

void main() {
  late FakePlugin plugin;
  late DeviceCalendarGateway gateway;
  setUp(() {
    plugin = FakePlugin();
    gateway = DeviceCalendarGateway(plugin: plugin);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('platforms', () {
    test('Android and iOS are supported; desktop is not', () {
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = p;
        expect(gateway.isSupported, isTrue, reason: '$p');
      }
      for (final p in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(gateway.isSupported, isFalse, reason: '$p');
      }
    });
  });

  group('permissions', () {
    test('not asked yet: one prompt, for FULL access', () async {
      expect(await gateway.requestAccess(), CalendarAccess.granted);
      expect(plugin.calls.where((c) => c == 'request'), hasLength(1));
      expect(plugin.requestedLevel, CalendarAccessLevel.full);
    });

    test('already granted: no prompt', () async {
      plugin.status = CalendarPermissionStatus.granted;
      expect(await gateway.requestAccess(), CalendarAccess.granted);
      expect(plugin.calls, isNot(contains('request')));
    });

    test('write-only is upgraded; if refused it counts as denied', () async {
      plugin
        ..status = CalendarPermissionStatus.writeOnly
        ..afterPrompt = CalendarPermissionStatus.writeOnly;
      expect(await gateway.requestAccess(), CalendarAccess.denied);
      expect(plugin.requestedLevel, CalendarAccessLevel.full);
    });

    test('declined at the prompt: denied', () async {
      plugin.afterPrompt = CalendarPermissionStatus.denied;
      expect(await gateway.requestAccess(), CalendarAccess.denied);
    });

    test('permanently denied: denied without prompting again', () async {
      plugin.status = CalendarPermissionStatus.denied;
      expect(await gateway.requestAccess(), CalendarAccess.denied);
      expect(plugin.calls, isNot(contains('request')));
    });

    test('restricted by device policy: restricted, no prompt', () async {
      plugin.status = CalendarPermissionStatus.restricted;
      expect(await gateway.requestAccess(), CalendarAccess.restricted);
      expect(plugin.calls, isNot(contains('request')));
    });

    test('no writable calendar account: unavailable', () async {
      plugin.calendars = const [
        Calendar(id: 'h', name: 'Holidays', readOnly: true),
      ];
      expect(await gateway.requestAccess(), CalendarAccess.unavailable);
      plugin.calendars = const [];
      expect(await gateway.requestAccess(), CalendarAccess.unavailable);
    });

    test('checking an event without access never prompts', () async {
      expect(await gateway.existsWithoutPrompt('evt-1'), isNull);
      expect(plugin.calls, ['has']);
    });
  });

  group('events', () {
    final event = SessionCalendarEvent.fromSession(_session(), now: _now)!;

    test(
      'created with neutral text and the exact instant, no time zone',
      () async {
        final created = await gateway.create(event);
        expect(created.eventId, 'evt-1');
        expect(created.calendarId, 'cal-1');
        expect(plugin.lastCreate!.title, "Ma'ak support session");
        expect(plugin.lastCreate!.start, DateTime.utc(2026, 11, 28, 15));
        expect(
          plugin.lastCreate!.timeZone,
          isNull,
          reason: 'a time zone would reinterpret the wall-clock time',
        );
        expect(plugin.events['evt-1']!.description, SessionCalendarEvent.notes);
      },
    );

    test(
      'an id for an event the calendar did not keep is not a save',
      () async {
        plugin.dropAfterCreate = true;
        await expectLater(gateway.create(event), throwsStateError);
      },
    );

    test('exists / deleted / update', () async {
      await gateway.create(event);
      expect(await gateway.exists('evt-1'), isTrue);
      final moved = SessionCalendarEvent.fromSession(
        _session(slot: 'slot-2', day: 29),
        now: _now,
      )!;
      await gateway.update('evt-1', moved);
      expect(plugin.events['evt-1']!.startDate, DateTime.utc(2026, 11, 29, 15));
      plugin.events.clear();
      expect(await gateway.exists('evt-1'), isFalse);
    });
  });

  group('local records', () {
    test('kept per signed-in member and booking', () async {
      String? user = 'user-a';
      final store = PrefsSavedSessionStore(userId: () => user);
      final event = SessionCalendarEvent.fromSession(_session(), now: _now)!;
      await store.write(
        SavedSessionEvent.of(event, 'evt-1', calendarId: 'cal-1'),
      );
      expect((await store.read('booking-1'))!.eventId, 'evt-1');

      user = 'user-b'; // another account on the same phone
      expect(await store.read('booking-1'), isNull);

      user = 'user-a';
      expect((await store.read('booking-1'))!.calendarId, 'cal-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'maak.session_calendar.v1.user-a.booking-1'});
      await store.remove('booking-1');
      expect(await store.read('booking-1'), isNull);
    });

    test('signed out: refuses to read or write', () async {
      final store = PrefsSavedSessionStore(userId: () => null);
      await expectLater(store.read('booking-1'), throwsStateError);
    });

    test('a damaged record counts as never added', () async {
      SharedPreferences.setMockInitialValues({
        'maak.session_calendar.v1.user-a.booking-1': '{not json',
      });
      final store = PrefsSavedSessionStore(userId: () => 'user-a');
      expect(await store.read('booking-1'), isNull);
    });
  });

  test(
    'end to end with the fake plugin: add, duplicate, reschedule, deleted',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calendar = SessionCalendar(
        gateway: gateway,
        store: PrefsSavedSessionStore(userId: () => 'user-a'),
      );
      expect(
        await calendar.add(_session(), now: _now),
        CalendarAddResult.added,
      );
      expect(
        await calendar.add(_session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(
        await calendar.add(_session(slot: 'slot-2', day: 29), now: _now),
        CalendarAddResult.updated,
      );
      expect(plugin.events, hasLength(1), reason: 'never a second event');
      plugin.events.clear(); // deleted in the calendar app
      expect(
        await calendar.add(_session(slot: 'slot-2', day: 29), now: _now),
        CalendarAddResult.added,
      );
      expect(plugin.events, hasLength(1));
    },
  );
}
