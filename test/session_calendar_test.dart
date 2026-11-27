// Sprint 4 US5: rules for adding a confirmed session to the phone calendar
// (lib/backend/services/session_calendar.dart). MOCKED: a fake calendar and
// an in-memory store stand in for the device; no real calendar is touched.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/session_calendar.dart';

class FakeCalendar implements CalendarGateway {
  @override
  bool isSupported = true;
  CalendarAccess access = CalendarAccess.granted;
  bool alreadyGranted = true;
  Object? createError;
  String nextId = 'evt-1';
  Completer<void>? holdCreate;
  final events = <String, SessionCalendarEvent>{};
  int creates = 0, updates = 0, accessRequests = 0;

  @override
  Future<CalendarAccess> requestAccess() async {
    accessRequests++;
    return access;
  }

  @override
  Future<CreatedCalendarEvent> create(SessionCalendarEvent event) async {
    await holdCreate?.future;
    if (createError != null) throw createError!;
    creates++;
    if (nextId.isNotEmpty) events[nextId] = event;
    return CreatedCalendarEvent(nextId, calendarId: 'cal-1');
  }

  @override
  Future<bool> exists(String eventId) async => events.containsKey(eventId);

  @override
  Future<bool?> existsWithoutPrompt(String eventId) async =>
      alreadyGranted ? events.containsKey(eventId) : null;

  @override
  Future<void> update(String eventId, SessionCalendarEvent event) async {
    updates++;
    events[eventId] = event;
  }
}

class MemoryStore implements SavedSessionStore {
  final saved = <String, SavedSessionEvent>{};
  bool failReads = false;
  @override
  Future<SavedSessionEvent?> read(String bookingId) async {
    if (failReads) throw StateError('storage unavailable');
    return saved[bookingId];
  }

  @override
  Future<void> write(SavedSessionEvent s) async => saved[s.bookingId] = s;
  @override
  Future<void> remove(String bookingId) async => saved.remove(bookingId);
}

final _now = DateTime.utc(2026, 11, 27, 9);

Map<String, dynamic> session({
  String status = 'accepted',
  String? display,
  String start = '2026-11-28T15:00:00+00:00',
  String end = '2026-11-28T16:00:00+00:00',
  String slot = 'slot-1',
  String id = 'booking-1',
}) => {
  'id': id,
  'slot_id': slot,
  'status': status,
  'display_status': display ?? status,
  'starts_at': start,
  'ends_at': end,
  'contact_name': 'Sara Omar',
  'is_volunteer': false,
};

void main() {
  late FakeCalendar calendar;
  late MemoryStore store;
  late SessionCalendar sessions;
  setUp(() {
    calendar = FakeCalendar();
    store = MemoryStore();
    sessions = SessionCalendar(gateway: calendar, store: store);
  });

  group('eligibility', () {
    test('a confirmed, upcoming session can be added', () {
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      expect(e.bookingId, 'booking-1');
      expect(e.slotId, 'slot-1');
      expect(e.startUtc, DateTime.utc(2026, 11, 28, 15));
      expect(e.endUtc, DateTime.utc(2026, 11, 28, 16));
    });

    test('pending, declined, canceled, expired, live and finished cannot', () {
      for (final s in [
        session(status: 'pending'),
        session(status: 'rejected'),
        session(status: 'canceled'),
        session(status: 'pending', display: 'expired'),
        session(display: 'in_progress'),
        session(display: 'completed'),
      ]) {
        expect(
          SessionCalendarEvent.fromSession(s, now: _now),
          isNull,
          reason: '${s['status']}/${s['display_status']}',
        );
      }
    });

    test('a session that has started, or has bad data, cannot be added', () {
      final cases = {
        'start time reached': (session(), DateTime.utc(2026, 11, 28, 15)),
        'ends when it starts': (session(end: '2026-11-28T15:00:00Z'), _now),
        'no booking id': ({...session(), 'id': null}, _now),
        'bad date': (session(start: 'not a date'), _now),
      };
      cases.forEach((why, c) {
        expect(
          SessionCalendarEvent.fromSession(c.$1, now: c.$2),
          isNull,
          reason: why,
        );
      });
    });
  });

  group('time zones', () {
    test('the same instant written with any offset gives the same event', () {
      final utc = SessionCalendarEvent.fromSession(session(), now: _now)!;
      final riyadh = SessionCalendarEvent.fromSession(
        session(
          start: '2026-11-28T18:00:00+03:00',
          end: '2026-11-28T19:00:00+03:00',
        ),
        now: _now,
      )!;
      expect(riyadh.startUtc, utc.startUtc);
      expect(riyadh.endUtc, utc.endUtc);
      expect(riyadh.startUtc.isUtc, isTrue);
    });

    test('a session across a daylight-saving change keeps its real length', () {
      // 2027-03-28 01:00 UTC: much of Europe moves its clocks forward.
      final e = SessionCalendarEvent.fromSession(
        session(start: '2027-03-28T00:30:00Z', end: '2027-03-28T01:30:00Z'),
        now: _now,
      )!;
      expect(e.endUtc.difference(e.startUtc), const Duration(hours: 1));
    });
  });

  test('the event never contains names, roles or health details', () {
    final text = '${SessionCalendarEvent.title} ${SessionCalendarEvent.notes}'
        .toLowerCase();
    for (final word in ['sara', 'omar', 'volunteer', 'seeker', 'condition']) {
      expect(text, isNot(contains(word)));
    }
  });

  group('adding', () {
    test('added only after the calendar returns an event id', () async {
      expect(await sessions.add(session(), now: _now), CalendarAddResult.added);
      expect(calendar.creates, 1);
      expect(store.saved['booking-1']!.eventId, 'evt-1');
      expect(store.saved['booking-1']!.calendarId, 'cal-1');
    });

    test('adding twice does not create a duplicate', () async {
      await sessions.add(session(), now: _now);
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
    });

    test('simultaneous presses create one event', () async {
      calendar.holdCreate = Completer<void>();
      final first = sessions.add(session(), now: _now);
      final second = sessions.add(session(), now: _now);
      calendar.holdCreate!.complete();
      expect(await first, CalendarAddResult.added);
      expect(await second, CalendarAddResult.added, reason: 'joined the first');
      expect(calendar.creates, 1);
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
    });

    test('different sessions are not merged', () async {
      await sessions.add(session(), now: _now);
      calendar.nextId = 'evt-2';
      expect(
        await sessions.add(session(id: 'booking-2'), now: _now),
        CalendarAddResult.added,
      );
      expect(calendar.creates, 2);
    });

    test(
      'a rescheduled session updates the same event, not a new one',
      () async {
        await sessions.add(session(), now: _now);
        final moved = session(
          slot: 'slot-2',
          start: '2026-11-29T10:00:00Z',
          end: '2026-11-29T11:00:00Z',
        );
        expect(await sessions.add(moved, now: _now), CalendarAddResult.updated);
        expect(calendar.creates, 1);
        expect(calendar.updates, 1);
        expect(
          calendar.events['evt-1']!.startUtc,
          DateTime.utc(2026, 11, 29, 10),
        );
        expect(store.saved['booking-1']!.slotId, 'slot-2');
        expect(store.saved['booking-1']!.calendarId, 'cal-1');
      },
    );

    test(
      'deleted in the calendar app: the stale record goes, added again',
      () async {
        await sessions.add(session(), now: _now);
        calendar.events.clear();
        calendar.nextId = 'evt-2';
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.added,
        );
        expect(store.saved['booking-1']!.eventId, 'evt-2');
        expect(calendar.creates, 2);
      },
    );

    test(
      'permission is asked before reading anything, on the tap only',
      () async {
        await sessions.stateOf(session(), now: _now);
        expect(calendar.accessRequests, 0, reason: 'labels never prompt');
        await sessions.add(session(), now: _now);
        expect(calendar.accessRequests, 1);
      },
    );

    for (final (access, result) in [
      (CalendarAccess.denied, CalendarAddResult.permissionDenied),
      (CalendarAccess.restricted, CalendarAddResult.restricted),
      (CalendarAccess.unavailable, CalendarAddResult.unavailable),
    ]) {
      test('${access.name}: $result, nothing written or remembered', () async {
        calendar.access = access;
        expect(await sessions.add(session(), now: _now), result);
        expect(calendar.creates, 0);
        expect(store.saved, isEmpty);
      });
    }

    test(
      'web and desktop: unavailable, the calendar is never touched',
      () async {
        calendar.isSupported = false;
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.unavailable,
        );
        expect(calendar.accessRequests, 0);
        expect(
          await sessions.stateOf(session(), now: _now),
          SessionCalendarState.hidden,
        );
      },
    );

    test(
      'a calendar error or an empty id is never reported as saved',
      () async {
        calendar.createError = Exception('calendar provider crashed');
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.failed,
        );
        expect(store.saved, isEmpty);
        calendar
          ..createError = null
          ..nextId = '';
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.failed,
        );
        expect(store.saved, isEmpty);
      },
    );

    test('local storage failing is a failure, not a false success', () async {
      store.failReads = true;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.failed,
      );
      expect(calendar.creates, 0);
    });

    test(
      'an unconfirmed session is refused before asking for permission',
      () async {
        expect(
          await sessions.add(session(status: 'pending'), now: _now),
          CalendarAddResult.notEligible,
        );
        expect(calendar.accessRequests, 0);
      },
    );
  });

  group('button state', () {
    test('not added, added, then outdated after a reschedule', () async {
      expect(
        await sessions.stateOf(session(), now: _now),
        SessionCalendarState.notAdded,
      );
      await sessions.add(session(), now: _now);
      expect(
        await sessions.stateOf(session(), now: _now),
        SessionCalendarState.added,
      );
      expect(
        await sessions.stateOf(
          session(
            slot: 'slot-2',
            start: '2026-11-29T10:00:00Z',
            end: '2026-11-29T11:00:00Z',
          ),
          now: _now,
        ),
        SessionCalendarState.outdated,
      );
      expect(
        await sessions.stateOf(session(status: 'canceled'), now: _now),
        SessionCalendarState.hidden,
      );
    });

    test(
      'deleted in the calendar app, access already granted: not added',
      () async {
        await sessions.add(session(), now: _now);
        calendar.events.clear();
        expect(
          await sessions.stateOf(session(), now: _now),
          SessionCalendarState.notAdded,
        );
        expect(store.saved, isEmpty, reason: 'stale record removed');
      },
    );

    test(
      'without access the label trusts the record (checked on the tap)',
      () async {
        await sessions.add(session(), now: _now);
        calendar
          ..events.clear()
          ..alreadyGranted = false;
        expect(
          await sessions.stateOf(session(), now: _now),
          SessionCalendarState.added,
        );
        expect(calendar.accessRequests, 1, reason: 'no prompt from the label');
      },
    );
  });

  test('saved records survive a round trip through storage', () {
    final s = SavedSessionEvent.of(
      SessionCalendarEvent.fromSession(session(), now: _now)!,
      'evt-9',
      calendarId: 'cal-3',
    );
    final back = SavedSessionEvent.fromJson(s.toJson())!;
    expect(back.eventId, 'evt-9');
    expect(back.calendarId, 'cal-3');
    expect(back.startUtc, s.startUtc);
    expect(SavedSessionEvent.fromJson({'event_id': 1}), isNull);
  });
}
