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

  /// The calendar's events, and the link stored in each.
  final events = <String, SessionCalendarEvent>{};
  final links = <String, String>{};

  /// Titles of events someone else wrote (ours have the neutral title).
  final titles = <String, String>{};

  /// Calendar errors (inconclusive answers) from lookups and searches.
  Object? lookupError, searchError;

  /// Partial failures: the event is written, then the read-back fails, or
  /// the calendar silently drops the new event.
  bool failNextLookupAfterCreate = false, dropCreated = false;
  int creates = 0, updates = 0, accessRequests = 0, searches = 0;
  final updated = <String>[];

  @override
  Future<CalendarAccess> requestAccess() async {
    accessRequests++;
    return access;
  }

  bool _justCreated = false;

  @override
  Future<String> create(
    SessionCalendarEvent event, {
    required String link,
  }) async {
    await holdCreate?.future;
    if (createError != null) throw createError!;
    creates++;
    if (nextId.isNotEmpty && !dropCreated) {
      events[nextId] = event;
      links[nextId] = link;
    }
    _justCreated = true;
    return nextId;
  }

  @override
  Future<CalendarEventInfo?> lookup(String eventId) async {
    if (_justCreated && failNextLookupAfterCreate) {
      _justCreated = false;
      failNextLookupAfterCreate = false;
      throw Exception('read-back failed');
    }
    _justCreated = false;
    if (lookupError != null) throw lookupError!;
    return events.containsKey(eventId)
        ? CalendarEventInfo(
            calendarId: 'cal-1',
            link: links[eventId],
            title: titles[eventId] ?? SessionCalendarEvent.title,
            startUtc: events[eventId]!.startUtc,
            endUtc: events[eventId]!.endUtc,
          )
        : null;
  }

  @override
  Future<(bool, CalendarEventInfo?)?> lookupWithoutPrompt(String id) async {
    if (!alreadyGranted) return null;
    final info = await lookup(id);
    return (info != null, info);
  }

  @override
  Future<String?> findByLink(String link, DateTime from, DateTime to) async {
    searches++;
    if (searchError != null) throw searchError!;
    for (final MapEntry(:key, :value) in events.entries) {
      if (links[key] == link &&
          !value.startUtc.isBefore(from) &&
          !value.endUtc.isAfter(to)) {
        return key;
      }
    }
    return null;
  }

  @override
  Future<void> update(String eventId, SessionCalendarEvent event) async {
    updates++;
    updated.add(eventId);
    events[eventId] = event;
  }
}

class MemoryStore implements SavedSessionStore {
  final saved = <String, SavedSessionEvent>{};
  bool failReads = false;

  /// Fails the write with this number (1 = the next write), once.
  int? failWrite;
  int writes = 0;

  @override
  Future<SavedSessionEvent?> read(String bookingId) async {
    if (failReads) throw StateError('storage unavailable');
    return saved[bookingId];
  }

  @override
  Future<void> write(SavedSessionEvent s) async {
    writes++;
    if (failWrite != null && writes == failWrite) {
      failWrite = null;
      throw StateError('storage full');
    }
    saved[s.bookingId] = s;
  }

  @override
  Future<void> remove(String bookingId) async => saved.remove(bookingId);
}

/// Predictable recovery tokens for tests: token-1, token-2, ...
String Function() tokens() {
  var n = 0;
  return () => 'token-${++n}';
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
    sessions = SessionCalendar(
      gateway: calendar,
      store: store,
      newToken: tokens(),
    );
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
        // Only the token is kept (no event id), ready for a safe retry.
        expect(store.saved['booking-1']!.eventId, isNull);
        expect(store.saved['booking-1']!.token, 'token-1');
        calendar
          ..createError = null
          ..nextId = '';
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.failed,
        );
        expect(store.saved['booking-1']!.eventId, isNull);
        expect(calendar.events, isEmpty);
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

    test('every event carries its own random recovery link', () async {
      await sessions.add(session(), now: _now);
      calendar.nextId = 'evt-2';
      await sessions.add(session(id: 'booking-2'), now: _now);
      expect(calendar.links['evt-1'], recoveryLink('token-1'));
      expect(calendar.links['evt-2'], recoveryLink('token-2'));
      expect(recoveryLink('token-1'), 'maak-session:token-1');
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

  group('partial failures and retries', () {
    test(
      'saving the token fails first: nothing is written to the calendar',
      () async {
        store.failWrite = 1;
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.failed,
        );
        expect(calendar.creates, 0);
        expect(store.saved, isEmpty);
      },
    );

    test('read-back fails after the event was written: failed now, '
        'the retry recognises it (no second event)', () async {
      calendar.failNextLookupAfterCreate = true;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.failed,
      );
      expect(calendar.events, hasLength(1));
      expect(
        store.saved['booking-1']!.eventId,
        'evt-1',
        reason: 'id saved early',
      );
      calendar.nextId = 'evt-2';
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
      expect(
        store.saved['booking-1']!.calendarId,
        'cal-1',
        reason: 'completed',
      );
    });

    test(
      'saving the event id fails: the retry finds the event by its token',
      () async {
        store.failWrite = 2; // 1 = token, 2 = event id
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.failed,
        );
        expect(calendar.events, hasLength(1));
        expect(store.saved['booking-1']!.eventId, isNull);
        calendar.nextId = 'evt-2';
        expect(
          await sessions.add(session(), now: _now),
          CalendarAddResult.alreadyAdded,
        );
        expect(calendar.creates, 1, reason: 'no duplicate');
        expect(calendar.searches, 1);
        expect(store.saved['booking-1']!.eventId, 'evt-1');
      },
    );

    test('interrupted (app closed) after the event was written, before its '
        'id was saved: label offers Add, the tap adopts the event', () async {
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      store.saved['booking-1'] = SavedSessionEvent.of(e, token: 'token-9');
      calendar
        ..events['evt-7'] = e
        ..links['evt-7'] = recoveryLink('token-9');
      expect(
        await sessions.stateOf(session(), now: _now),
        SessionCalendarState.notAdded,
      );
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 0);
      expect(store.saved['booking-1']!.eventId, 'evt-7');
    });

    test('interrupted before the event was written: the retry adds it once, '
        'reusing the saved token', () async {
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      store.saved['booking-1'] = SavedSessionEvent.of(e, token: 'token-9');
      expect(await sessions.add(session(), now: _now), CalendarAddResult.added);
      expect(calendar.creates, 1);
      expect(calendar.links['evt-1'], recoveryLink('token-9'));
    });

    test(
      'an interrupted add found after a reschedule is moved, not duplicated',
      () async {
        final old = SessionCalendarEvent.fromSession(session(), now: _now)!;
        store.saved['booking-1'] = SavedSessionEvent.of(old, token: 'token-9');
        calendar
          ..events['evt-7'] = old
          ..links['evt-7'] = recoveryLink('token-9');
        final moved = session(
          slot: 'slot-2',
          start: '2026-11-28T17:00:00Z',
          end: '2026-11-28T18:00:00Z',
        );
        expect(await sessions.add(moved, now: _now), CalendarAddResult.updated);
        expect(calendar.creates, 0);
        expect(calendar.updated, ['evt-7']);
      },
    );

    test('the calendar does not return the new event: failed, only the '
        'token is kept, and the next tap writes it again', () async {
      calendar.dropCreated = true;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.failed,
      );
      final pending = store.saved['booking-1']!;
      expect(pending.eventId, isNull);
      expect(pending.token, isNotNull);
      calendar.dropCreated = false;
      expect(await sessions.add(session(), now: _now), CalendarAddResult.added);
      expect(calendar.events, hasLength(1));
      expect(calendar.links.values.single, recoveryLink(pending.token!));
    });

    test('an event that appears after the read-back is adopted, '
        'not written twice', () async {
      calendar.dropCreated = true;
      await sessions.add(session(), now: _now);
      // The slow calendar shows the event later, under its token.
      final token = store.saved['booking-1']!.token!;
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      calendar.events['evt-late'] = e;
      calendar.links['evt-late'] = recoveryLink(token);
      calendar.dropCreated = false;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
      expect(store.saved['booking-1']!.eventId, 'evt-late');
    });

    test(
      'an id that now belongs to an unrelated event is never moved',
      () async {
        // The saved id points to someone else's event (different link).
        final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
        store.saved['booking-1'] = SavedSessionEvent.of(
          e,
          eventId: 'evt-x',
          token: 'token-9',
        );
        final other = SessionCalendarEvent.fromSession(
          session(
            id: 'other-booking',
            start: '2026-11-30T09:00:00Z',
            end: '2026-11-30T10:00:00Z',
          ),
          now: _now,
        )!;
        calendar
          ..events['evt-x'] = other
          ..links['evt-x'] = 'https://example.com/not-ours';
        final moved = session(
          slot: 'slot-2',
          start: '2026-11-29T10:00:00Z',
          end: '2026-11-29T11:00:00Z',
        );
        calendar.nextId = 'evt-new';
        expect(await sessions.add(moved, now: _now), CalendarAddResult.added);
        expect(calendar.updated, isEmpty, reason: 'unrelated event untouched');
        expect(calendar.events['evt-x'], other);
        expect(store.saved['booking-1']!.eventId, 'evt-new');
      },
    );

    test('another booking at the same time is never adopted', () async {
      // Booking 2 was interrupted; booking 1's event has the same time.
      await sessions.add(session(), now: _now); // evt-1, token-1
      final e2 = SessionCalendarEvent.fromSession(
        session(id: 'booking-2'),
        now: _now,
      )!;
      store.saved['booking-2'] = SavedSessionEvent.of(e2, token: 'token-b');
      calendar.nextId = 'evt-2';
      expect(
        await sessions.add(session(id: 'booking-2'), now: _now),
        CalendarAddResult.added,
      );
      expect(store.saved['booking-2']!.eventId, 'evt-2');
      expect(store.saved['booking-1']!.eventId, 'evt-1');
      expect(calendar.events, hasLength(2));
    });

    test('records from before recovery tokens still work', () async {
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      store.saved['booking-1'] = SavedSessionEvent.of(e, eventId: 'evt-1');
      calendar.events['evt-1'] = e; // created by the previous version, no link
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 0);
    });

    test('a legacy record is still updated after a reschedule', () async {
      final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
      store.saved['booking-1'] = SavedSessionEvent.of(e, eventId: 'evt-1');
      calendar.events['evt-1'] = e;
      final moved = session(
        slot: 'slot-2',
        start: '2026-11-29T10:00:00Z',
        end: '2026-11-29T11:00:00Z',
      );
      expect(await sessions.add(moved, now: _now), CalendarAddResult.updated);
      expect(calendar.updated, ['evt-1']);
      expect(calendar.creates, 0);
    });

    for (final (what, change) in <(String, void Function(FakeCalendar))>[
      ('another title', (c) => c.titles['evt-1'] = 'Dentist'),
      (
        'other times',
        (c) => c.events['evt-1'] = SessionCalendarEvent.fromSession(
          session(start: '2026-11-30T09:00:00Z', end: '2026-11-30T10:00:00Z'),
          now: _now,
        )!,
      ),
      ('a link', (c) => c.links['evt-1'] = 'https://example.com/x'),
    ]) {
      test('a legacy id now used by an event with $what is never '
          'modified', () async {
        final e = SessionCalendarEvent.fromSession(session(), now: _now)!;
        store.saved['booking-1'] = SavedSessionEvent.of(e, eventId: 'evt-1');
        calendar.events['evt-1'] = e;
        change(calendar);
        final before = calendar.events['evt-1'];
        calendar.nextId = 'evt-new';
        final moved = session(
          slot: 'slot-2',
          start: '2026-11-29T10:00:00Z',
          end: '2026-11-29T11:00:00Z',
        );
        expect(await sessions.add(moved, now: _now), CalendarAddResult.added);
        expect(calendar.updated, isEmpty);
        expect(calendar.events['evt-1'], before);
        expect(store.saved['booking-1']!.eventId, 'evt-new');
        expect(store.saved['booking-1']!.token, isNotNull);
      });
    }
  });

  group('uncertain calendar answers never create a second event', () {
    test('a failing lookup: failed, nothing created, record kept', () async {
      await sessions.add(session(), now: _now);
      final before = store.saved['booking-1'];
      calendar.lookupError = Exception('provider busy');
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.failed,
      );
      expect(calendar.creates, 1);
      expect(store.saved['booking-1'], same(before));
      calendar.lookupError = null;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
    });

    test('a failing search by token: failed, nothing created', () async {
      await sessions.add(session(), now: _now);
      // Not found by its id, and the search that would confirm it fails.
      final kept = calendar.events.remove('evt-1')!;
      calendar.searchError = Exception('provider busy');
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.failed,
      );
      expect(calendar.creates, 1);
      calendar
        ..searchError = null
        ..events['evt-1'] = kept;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
    });

    test('missing by its id but found by its token (new id): adopted, '
        'not created again', () async {
      await sessions.add(session(), now: _now);
      final e = calendar.events.remove('evt-1')!;
      final link = calendar.links.remove('evt-1')!;
      calendar
        ..events['evt-9'] = e
        ..links['evt-9'] = link;
      expect(
        await sessions.add(session(), now: _now),
        CalendarAddResult.alreadyAdded,
      );
      expect(calendar.creates, 1);
      expect(store.saved['booking-1']!.eventId, 'evt-9');
    });

    test('confirmed gone by id and by token: written again under the same '
        'token', () async {
      await sessions.add(session(), now: _now);
      final token = store.saved['booking-1']!.token;
      calendar.events.clear();
      calendar.nextId = 'evt-2';
      expect(await sessions.add(session(), now: _now), CalendarAddResult.added);
      expect(calendar.creates, 2);
      expect(store.saved['booking-1']!.token, token);
      expect(calendar.links['evt-2'], recoveryLink(token!));
    });
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
        expect(
          store.saved['booking-1']!.token,
          isNotNull,
          reason: 'kept: the tap still searches by token first',
        );
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
      eventId: 'evt-9',
      calendarId: 'cal-3',
      token: 'token-3',
    );
    final back = SavedSessionEvent.fromJson(s.toJson())!;
    expect(back.eventId, 'evt-9');
    expect(back.calendarId, 'cal-3');
    expect(back.token, 'token-3');
    expect(back.startUtc, s.startUtc);
    expect(SavedSessionEvent.fromJson({'event_id': 1}), isNull);
    // A record written by the previous version (no token) still loads.
    final legacy = s.toJson()..remove('token');
    expect(SavedSessionEvent.fromJson(legacy)!.token, isNull);
    // Neither id nor token: nothing to find the event by.
    expect(
      SavedSessionEvent.fromJson({
        ...s.toJson(),
        'event_id': null,
        'token': null,
      }),
      isNull,
    );
  });
}
