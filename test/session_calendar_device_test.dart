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
    createdIn = calendarId;
    final id = 'evt-${++_created}';
    if (!dropAfterCreate) {
      events[id] = _event(id, title, startDate, endDate, description, url);
    }
    lastCreate = (title: title, start: startDate, timeZone: timeZone, url: url);
    return id;
  }

  int _created = 0;
  ({String title, DateTime start, String? timeZone, String? url})? lastCreate;
  String? createdIn;

  /// getEvent returns null this many times before finding the event, like
  /// an Android calendar that is slow to return a new event.
  int slowReads = 0;

  @override
  Future<Event?> getEvent(String id) async {
    calls.add('get');
    if (slowReads > 0) {
      slowReads--;
      return null;
    }
    return events[id];
  }

  @override
  Future<List<Event>> listEvents(
    DateTime startDate,
    DateTime endDate, {
    List<String>? calendarIds,
  }) async {
    calls.add('list');
    return [
      for (final e in events.values)
        if (e.startDate.isBefore(endDate) && e.endDate.isAfter(startDate)) e,
    ];
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
      old.url,
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
    String? url,
  ) => Event(
    eventId: id,
    instanceId: id,
    calendarId: 'cal-1',
    title: title,
    description: description,
    url: url,
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
      expect(await gateway.lookupWithoutPrompt('evt-1'), isNull);
      expect(plugin.calls, ['has']);
    });
  });

  group('events', () {
    final event = SessionCalendarEvent.fromSession(_session(), now: _now)!;
    final link = recoveryLink('token-1');
    setUp(() => DeviceCalendarGateway.readBackDelay = Duration.zero);

    test('goes into the primary writable calendar', () async {
      plugin.calendars = const [
        Calendar(id: 'h', name: 'Holidays', readOnly: true, isPrimary: true),
        Calendar(id: 'w', name: 'Work', readOnly: false),
        Calendar(id: 'p', name: 'Personal', readOnly: false, isPrimary: true),
      ];
      expect(await gateway.requestAccess(), CalendarAccess.granted);
      await gateway.create(event, link: link);
      expect(plugin.createdIn, 'p');
    });

    test('no primary writable calendar: the first writable one', () {
      expect(
        DeviceCalendarGateway.pickCalendar(const [
          Calendar(id: 'h', name: 'Holidays', readOnly: true, isPrimary: true),
          Calendar(id: 'w', name: 'Work', readOnly: false),
        ])?.id,
        'w',
      );
    });

    test('a calendar slow to return the new event: create waits until it '
        'can be read, without a second event', () async {
      plugin.slowReads = 2;
      expect(await gateway.create(event, link: link), 'evt-1');
      expect(plugin.calls.where((c) => c == 'create'), hasLength(1));
      expect(plugin.calls.where((c) => c == 'get'), hasLength(3));
      expect(await gateway.lookup('evt-1'), isNotNull);
    });

    test('created with neutral text, the exact instant, no time zone, and only '
        'the opaque recovery link', () async {
      expect(await gateway.create(event, link: link), 'evt-1');
      expect(plugin.lastCreate!.title, "Ma'ak support session");
      expect(plugin.lastCreate!.start, DateTime.utc(2026, 11, 28, 15));
      expect(
        plugin.lastCreate!.timeZone,
        isNull,
        reason: 'a time zone would reinterpret the wall-clock time',
      );
      expect(plugin.lastCreate!.url, 'maak-session:token-1');
      expect(plugin.events['evt-1']!.description, SessionCalendarEvent.notes);
    });

    test(
      'lookup reports the calendar and the link; a missing event is null',
      () async {
        await gateway.create(event, link: link);
        final info = await gateway.lookup('evt-1');
        expect(info!.calendarId, 'cal-1');
        expect(info.link, link);
        expect(await gateway.lookup('evt-404'), isNull);
      },
    );

    test('found again by its link, only inside the searched window', () async {
      await gateway.create(event, link: link);
      expect(
        await gateway.findByLink(
          link,
          DateTime.utc(2026, 11, 27),
          DateTime.utc(2026, 11, 29),
        ),
        'evt-1',
      );
      expect(
        await gateway.findByLink(
          recoveryLink('token-2'),
          DateTime.utc(2026, 11, 27),
          DateTime.utc(2026, 11, 29),
        ),
        isNull,
        reason: 'another booking or account has another token',
      );
    });

    test('update moves the event and keeps its link', () async {
      await gateway.create(event, link: link);
      final moved = SessionCalendarEvent.fromSession(
        _session(slot: 'slot-2', day: 29),
        now: _now,
      )!;
      await gateway.update('evt-1', moved);
      expect(plugin.events['evt-1']!.startDate, DateTime.utc(2026, 11, 29, 15));
      expect(plugin.events['evt-1']!.url, link);
      plugin.events.clear();
      expect(await gateway.lookup('evt-1'), isNull);
    });
  });

  group('local records', () {
    test('kept per signed-in member and booking', () async {
      String? user = 'user-a';
      final store = PrefsSavedSessionStore(userId: () => user);
      final event = SessionCalendarEvent.fromSession(_session(), now: _now)!;
      await store.write(
        SavedSessionEvent.of(
          event,
          eventId: 'evt-1',
          calendarId: 'cal-1',
          token: 'token-1',
        ),
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
      var n = 0;
      final calendar = SessionCalendar(
        gateway: gateway,
        store: PrefsSavedSessionStore(userId: () => 'user-a'),
        newToken: () => 'token-${++n}',
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

  test(
    'end to end: the app stops between writing the event and saving its id; '
    'the next tap finds it through the real record store, no duplicate',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final store = PrefsSavedSessionStore(userId: () => 'user-a');
      final event = SessionCalendarEvent.fromSession(_session(), now: _now)!;
      // What an interrupted first attempt leaves: the saved token, and the
      // event it wrote.
      await store.write(SavedSessionEvent.of(event, token: 'token-1'));
      await gateway.create(event, link: recoveryLink('token-1'));
      final calendar = SessionCalendar(
        gateway: gateway,
        store: store,
        newToken: () => fail('no new token needed'),
      );
      expect(
        await calendar.add(_session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(plugin.events, hasLength(1));
      expect((await store.read('booking-1'))!.eventId, 'evt-1');
    },
  );
}
