import 'package:flutter/foundation.dart';

// Sprint 4 US5: add a confirmed support session to the phone's calendar.
//
// Sessions come from Razan's session scheduling (my_maak_sessions() in
// supabase/migrations/20261121100000_session_scheduling.sql): each row has the
// booking id, the slot id, UTC start/end, status and display_status. Nothing
// here changes that workflow or the database.
//
// This file holds the rules, independent of the calendar plugin:
//  * which sessions can be added (confirmed and still upcoming),
//  * what the event contains (no names, roles, conditions or chat content),
//  * how a saved event is found again, and updated after a reschedule,
//  * that "added" is only reported after the calendar confirmed the event,
//  * that permission is only asked for when the member taps the button.
// The device calendar sits behind [CalendarGateway]; what this device added
// sits behind [SavedSessionStore] (local, per signed-in member).
//
// Partial failures. Every event this device writes carries a recovery token:
// a random value, unique per member and booking, stored in the event's link
// field (`maak-session:<random>`). It reveals nothing about the session or
// the people in it. The token is saved locally BEFORE the event is created,
// and the event id right after, so an attempt that was interrupted, or whose
// confirmation or local save failed, is found again on the next tap instead
// of being created twice. An event is only ever moved when both its id and
// its token match this device's record, so an unrelated event is never
// touched. A record from before tokens existed matches only an event that
// is still exactly what this app wrote (neutral title, saved times, no
// link). No event is ever deleted.
//
// Uncertain answers. A new event is written only after the calendar answered
// that the saved one does not exist, by id and by token. A calendar error
// during those checks reports "failed" and leaves the record as it was, so
// an uncertain answer never leads to a second event.
//
// Limits: events are not kept in sync automatically. A rescheduled session is
// updated only when the member taps "Update calendar", and a canceled session
// stays in the calendar until the member deletes it there. Recovery needs the
// local record: after a reinstall, on another phone, or if the calendar
// account drops the link field, a session can be added a second time.

/// What is written to the device calendar for one session.
@immutable
class SessionCalendarEvent {
  /// Booking id: stays the same when the session is rescheduled.
  final String bookingId;

  /// Slot id: changes when the session moves to another time.
  final String slotId;

  /// Exact instants (UTC). The calendar shows them in the device's time
  /// zone, so a time-zone or daylight-saving change cannot shift the session.
  final DateTime startUtc, endUtc;

  const SessionCalendarEvent({
    required this.bookingId,
    required this.slotId,
    required this.startUtc,
    required this.endUtc,
  });

  /// Neutral wording only: the event may be visible to anyone who sees the
  /// phone, or synced to a shared calendar.
  static const title = "Ma'ak support session";
  static const notes =
      "A peer support session you booked in Ma'ak. Open the app for details.";

  /// The calendar event for [session] (a row of my_maak_sessions()), or null
  /// when it cannot be added: not confirmed, already started, or incomplete.
  static SessionCalendarEvent? fromSession(
    Map<String, dynamic> session, {
    DateTime? now,
  }) {
    if (session['status'] != 'accepted' ||
        session['display_status'] != 'accepted') {
      return null;
    }
    final id = session['id'], slot = session['slot_id'];
    final start = DateTime.tryParse('${session['starts_at']}');
    final end = DateTime.tryParse('${session['ends_at']}');
    if (id is! String || slot is! String || start == null || end == null) {
      return null;
    }
    if (!end.isAfter(start)) return null;
    if (!start.isAfter(now ?? DateTime.now())) return null;
    return SessionCalendarEvent(
      bookingId: id,
      slotId: slot,
      startUtc: start.toUtc(),
      endUtc: end.toUtc(),
    );
  }

  /// Same session at the same time as an event saved earlier.
  bool sameTimeAs(SavedSessionEvent saved) =>
      saved.slotId == slotId &&
      saved.startUtc.isAtSameMomentAs(startUtc) &&
      saved.endUtc.isAtSameMomentAs(endUtc);
}

/// The link stored in each event this app writes: an opaque random token.
@visibleForTesting
String recoveryLink(String token) => 'maak-session:$token';

/// What the calendar reports about one event.
@immutable
class CalendarEventInfo {
  final String? calendarId;

  /// The event's link field ([recoveryLink] for events this app wrote).
  final String? link;

  /// Title and exact instants, to recognise events written before recovery
  /// tokens existed (null when the calendar did not report them).
  final String? title;
  final DateTime? startUtc, endUtc;
  const CalendarEventInfo({
    this.calendarId,
    this.link,
    this.title,
    this.startUtc,
    this.endUtc,
  });
}

/// A session this device put in its calendar, or is putting there.
@immutable
class SavedSessionEvent {
  final String bookingId, slotId;

  /// Null while the event is being created (the token is already saved).
  final String? eventId;
  final String? calendarId;

  /// Random value written into the event's link; null for records made
  /// before recovery tokens existed.
  final String? token;
  final DateTime startUtc, endUtc;
  const SavedSessionEvent({
    required this.bookingId,
    required this.slotId,
    required this.startUtc,
    required this.endUtc,
    this.eventId,
    this.calendarId,
    this.token,
  });

  factory SavedSessionEvent.of(
    SessionCalendarEvent e, {
    String? eventId,
    String? calendarId,
    String? token,
  }) => SavedSessionEvent(
    bookingId: e.bookingId,
    eventId: eventId,
    calendarId: calendarId,
    token: token,
    slotId: e.slotId,
    startUtc: e.startUtc,
    endUtc: e.endUtc,
  );

  /// The event with [info] is the one this record describes: its link holds
  /// this record's token. A record from before tokens existed has only the
  /// id, which the calendar may since have given to another event, so it
  /// owns the event only if it is still exactly what this app wrote: the
  /// neutral title, the saved times and no link.
  bool owns(CalendarEventInfo info) {
    final t = token;
    if (t != null) return info.link == recoveryLink(t);
    final start = info.startUtc, end = info.endUtc;
    return (info.link == null || info.link!.isEmpty) &&
        info.title == SessionCalendarEvent.title &&
        start != null &&
        end != null &&
        start.isAtSameMomentAs(startUtc) &&
        end.isAtSameMomentAs(endUtc);
  }

  Map<String, Object?> toJson() => {
    'booking_id': bookingId,
    'event_id': eventId,
    'calendar_id': calendarId,
    'token': token,
    'slot_id': slotId,
    'starts_at': startUtc.toIso8601String(),
    'ends_at': endUtc.toIso8601String(),
  };

  static SavedSessionEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = DateTime.tryParse('${json['starts_at']}');
    final end = DateTime.tryParse('${json['ends_at']}');
    final booking = json['booking_id'], slot = json['slot_id'];
    final eventId = json['event_id'], token = json['token'];
    if (start == null || end == null || booking is! String || slot is! String) {
      return null;
    }
    // Neither an id nor a token: nothing to find the event by.
    if (eventId is! String && token is! String) return null;
    final calendarId = json['calendar_id'];
    return SavedSessionEvent(
      bookingId: booking,
      slotId: slot,
      eventId: eventId is String ? eventId : null,
      calendarId: calendarId is String ? calendarId : null,
      token: token is String ? token : null,
      startUtc: start.toUtc(),
      endUtc: end.toUtc(),
    );
  }
}

/// Calendar access, as the plugin reports it.
enum CalendarAccess {
  granted,

  /// The member declined, now or earlier (may be changed in Settings).
  denied,

  /// Blocked by device policy (iOS Screen Time / MDM): cannot be granted.
  restricted,

  /// No device calendar, or no calendar account that can take events.
  unavailable,
}

/// The device calendar. Implemented with device_calendar_plus.
abstract class CalendarGateway {
  /// False on platforms without a device calendar (web, desktop). When false
  /// no other member is ever called, so no plugin code runs there.
  bool get isSupported;

  /// Asks for permission if needed (shows the system prompt). Call only
  /// from a member's tap.
  Future<CalendarAccess> requestAccess();

  /// Writes the event with [link] in its link field and returns its id as
  /// soon as the calendar assigns one. Throws if nothing was written.
  Future<String> create(SessionCalendarEvent event, {required String link});

  /// The event with [eventId], or null if it no longer exists. Needs access.
  Future<CalendarEventInfo?> lookup(String eventId);

  /// Like [lookup], but only if access was already granted: null when it
  /// cannot be checked without prompting, otherwise (exists, info).
  Future<(bool, CalendarEventInfo?)?> lookupWithoutPrompt(String eventId);

  /// The id of the event carrying [link] between [from] and [to], if any.
  Future<String?> findByLink(String link, DateTime from, DateTime to);

  /// Moves an existing event to the session's new time.
  Future<void> update(String eventId, SessionCalendarEvent event);
}

/// What this device added, per signed-in member. Survives app restarts, not
/// a reinstall, and is not shared between devices.
abstract class SavedSessionStore {
  Future<SavedSessionEvent?> read(String bookingId);
  Future<void> write(SavedSessionEvent saved);
  Future<void> remove(String bookingId);
}

enum CalendarAddResult {
  /// A new event was saved and the calendar confirmed it.
  added,

  /// The saved event was moved to the rescheduled time.
  updated,

  /// The event is already in the calendar at this time: nothing written.
  alreadyAdded,

  /// The member did not allow calendar access.
  permissionDenied,

  /// Calendar access is blocked by device policy.
  restricted,

  /// No device calendar here (web, desktop, or no calendar account).
  unavailable,

  /// The session cannot be added (not confirmed, or already started).
  notEligible,

  /// The calendar refused or failed, or could not confirm the event; nothing
  /// is reported as saved. A retry finds any event this attempt did write.
  failed,
}

enum SessionCalendarState {
  /// Not shown: no device calendar, or the session cannot be added.
  hidden,
  notAdded,
  added,

  /// Saved at a time the session no longer has (it was rescheduled).
  outdated,
}

/// Adds sessions to the device calendar without duplicates.
class SessionCalendar {
  final CalendarGateway gateway;
  final SavedSessionStore store;

  /// New recovery tokens (random; replaced in tests).
  final String Function() newToken;
  SessionCalendar({
    required this.gateway,
    required this.store,
    required this.newToken,
  });

  /// How far around the saved time an interrupted event is searched for.
  static const searchMargin = Duration(days: 1);

  // One operation per booking at a time: a second tap, or a tap on another
  // card for the same session, joins the running one instead of creating a
  // second event.
  final _running = <String, Future<CalendarAddResult>>{};

  /// Adds [session] (a row of my_maak_sessions()), or updates the event this
  /// device saved before if the session was rescheduled. Call from a tap.
  Future<CalendarAddResult> add(Map<String, dynamic> session, {DateTime? now}) {
    if (!gateway.isSupported) {
      return Future.value(CalendarAddResult.unavailable);
    }
    final event = SessionCalendarEvent.fromSession(session, now: now);
    if (event == null) return Future.value(CalendarAddResult.notEligible);
    // Block body: remove() returns this same future, and whenComplete would
    // wait for a returned future, so an arrow here would never finish.
    return _running[event.bookingId] ??= _add(event).whenComplete(() {
      _running.remove(event.bookingId);
    });
  }

  Future<CalendarAddResult> _add(SessionCalendarEvent event) async {
    try {
      switch (await gateway.requestAccess()) {
        case CalendarAccess.granted:
          break;
        case CalendarAccess.denied:
          return CalendarAddResult.permissionDenied;
        case CalendarAccess.restricted:
          return CalendarAddResult.restricted;
        case CalendarAccess.unavailable:
          return CalendarAddResult.unavailable;
      }
      var saved = await store.read(event.bookingId);

      // Find the event this device wrote earlier, by id and then by token.
      // A calendar error (thrown) is inconclusive: it ends in "failed" with
      // the record untouched, and nothing is created. Only a definite "no
      // such event" (null) counts as missing.
      if (saved != null) {
        final found = await _findSaved(saved);
        if (found != null) {
          final (id, info) = found;
          if (id != saved.eventId) {
            // Interrupted before its id was saved, or the calendar gave the
            // event another id: adopt it.
            saved = _withId(saved, id);
            await store.write(saved);
          }
          final mine = saved;
          if (event.sameTimeAs(mine)) {
            // Confirm the calendar details once, if a failure left them out.
            if (mine.calendarId == null && info.calendarId != null) {
              await _quietly(
                () => store.write(_withId(mine, id, info.calendarId)),
              );
            }
            return CalendarAddResult.alreadyAdded;
          }
          await gateway.update(id, event);
          await store.write(
            SavedSessionEvent.of(
              event,
              eventId: id,
              calendarId: mine.calendarId ?? info.calendarId,
              token: mine.token,
            ),
          );
          return CalendarAddResult.updated;
        }
        // Confirmed missing (deleted in the calendar app, or never kept):
        // write it again, under the same token when there is one. A legacy
        // id that now belongs to another event is left alone.
        saved = saved.token == null
            ? null
            : SavedSessionEvent.of(event, token: saved.token);
      }

      // 1. Save the token first: if this fails, nothing is written.
      final token = saved?.token ?? newToken();
      await store.write(SavedSessionEvent.of(event, token: token));
      // 2. Write the event, and save its id straight away.
      final id = await gateway.create(event, link: recoveryLink(token));
      if (id.isEmpty) return CalendarAddResult.failed;
      final withId = SavedSessionEvent.of(event, eventId: id, token: token);
      await store.write(withId);
      // 3. Read it back: "added" only for an event the calendar kept.
      final info = await gateway.lookup(id);
      if (info == null) {
        // Not readable yet (some calendars are slow) or not kept: keep only
        // the token, so the next tap adopts the event if it appears and
        // writes it again if it never does.
        await _quietly(
          () => store.write(SavedSessionEvent.of(event, token: token)),
        );
        return CalendarAddResult.failed;
      }
      await _quietly(() => store.write(_withId(withId, id, info.calendarId)));
      return CalendarAddResult.added;
    } catch (_) {
      // Whatever was written is in the record (token and, once known, id),
      // so the next tap finds it rather than adding it again.
      return CalendarAddResult.failed;
    }
  }

  /// The event [saved] describes, with its id: by the saved id first, then
  /// by the recovery token. Null only when the calendar answered that it has
  /// no such event; a calendar error is thrown, never read as "missing".
  Future<(String, CalendarEventInfo)?> _findSaved(
    SavedSessionEvent saved,
  ) async {
    if (saved.eventId case final id?) {
      final info = await gateway.lookup(id);
      if (info != null && saved.owns(info)) return (id, info);
    }
    final token = saved.token;
    if (token == null) return null; // legacy record: the id was its only key
    final found = await gateway.findByLink(
      recoveryLink(token),
      saved.startUtc.subtract(searchMargin),
      saved.endUtc.add(searchMargin),
    );
    if (found == null) return null;
    final info = await gateway.lookup(found);
    return info != null && saved.owns(info) ? (found, info) : null;
  }

  static SavedSessionEvent _withId(
    SavedSessionEvent s,
    String eventId, [
    String? calendarId,
  ]) => SavedSessionEvent(
    bookingId: s.bookingId,
    slotId: s.slotId,
    startUtc: s.startUtc,
    endUtc: s.endUtc,
    eventId: eventId,
    calendarId: calendarId ?? s.calendarId,
    token: s.token,
  );

  /// Best effort: the event is already confirmed or already recoverable.
  static Future<void> _quietly(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {}
  }

  /// What this device has saved for [session], to label the button. Never
  /// prompts: an event deleted in the calendar app is noticed here only when
  /// access was already granted, otherwise on the next tap.
  Future<SessionCalendarState> stateOf(
    Map<String, dynamic> session, {
    DateTime? now,
  }) async {
    if (!gateway.isSupported) return SessionCalendarState.hidden;
    final event = SessionCalendarEvent.fromSession(session, now: now);
    if (event == null) return SessionCalendarState.hidden;
    try {
      final saved = await store.read(event.bookingId);
      if (saved == null) return SessionCalendarState.notAdded;
      // Interrupted before the id was saved: the next tap finishes it.
      final id = saved.eventId;
      if (id == null) return SessionCalendarState.notAdded;
      final check = await gateway.lookupWithoutPrompt(id);
      if (check != null) {
        final (exists, info) = check;
        // Not found by its id (or the id is another event's now): offer
        // "Add" again. The record is kept, so the tap still searches by
        // token before writing anything.
        if (!exists || (info != null && !saved.owns(info))) {
          return SessionCalendarState.notAdded;
        }
      }
      return event.sameTimeAs(saved)
          ? SessionCalendarState.added
          : SessionCalendarState.outdated;
    } catch (_) {
      return SessionCalendarState.notAdded;
    }
  }
}
