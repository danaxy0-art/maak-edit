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
//  * that "added" is only reported after the calendar returned an event id,
//  * that permission is only asked for when the member taps the button.
// The device calendar sits behind [CalendarGateway]; what this device added
// sits behind [SavedSessionStore] (local, per signed-in member).
//
// Limits: events are not kept in sync automatically. A rescheduled session is
// updated only when the member taps "Update calendar", and a canceled session
// stays in the calendar until the member deletes it there.

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

/// An event the calendar confirmed it saved.
@immutable
class CreatedCalendarEvent {
  final String eventId;
  final String? calendarId;
  const CreatedCalendarEvent(this.eventId, {this.calendarId});
}

/// A session this device already put in its calendar.
@immutable
class SavedSessionEvent {
  final String bookingId, eventId, slotId;
  final String? calendarId;
  final DateTime startUtc, endUtc;
  const SavedSessionEvent({
    required this.bookingId,
    required this.eventId,
    required this.slotId,
    required this.startUtc,
    required this.endUtc,
    this.calendarId,
  });

  factory SavedSessionEvent.of(
    SessionCalendarEvent e,
    String eventId, {
    String? calendarId,
  }) => SavedSessionEvent(
    bookingId: e.bookingId,
    eventId: eventId,
    calendarId: calendarId,
    slotId: e.slotId,
    startUtc: e.startUtc,
    endUtc: e.endUtc,
  );

  Map<String, Object?> toJson() => {
    'booking_id': bookingId,
    'event_id': eventId,
    'calendar_id': calendarId,
    'slot_id': slotId,
    'starts_at': startUtc.toIso8601String(),
    'ends_at': endUtc.toIso8601String(),
  };

  static SavedSessionEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = DateTime.tryParse('${json['starts_at']}');
    final end = DateTime.tryParse('${json['ends_at']}');
    final values = [json['booking_id'], json['event_id'], json['slot_id']];
    if (start == null || end == null || values.any((v) => v is! String)) {
      return null;
    }
    final calendarId = json['calendar_id'];
    return SavedSessionEvent(
      bookingId: values[0] as String,
      eventId: values[1] as String,
      slotId: values[2] as String,
      calendarId: calendarId is String ? calendarId : null,
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

  /// Writes the event. Returns only after the calendar saved it; throws if
  /// nothing was saved.
  Future<CreatedCalendarEvent> create(SessionCalendarEvent event);

  /// The event still exists (the member may have deleted it). Needs access.
  Future<bool> exists(String eventId);

  /// Whether the event still exists, checked only if access was already
  /// granted; null when it cannot be checked without prompting.
  Future<bool?> existsWithoutPrompt(String eventId);

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
  /// A new event was saved (the calendar returned its id).
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

  /// The calendar refused or failed; nothing is reported as saved.
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
  SessionCalendar({required this.gateway, required this.store});

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
      final saved = await store.read(event.bookingId);
      if (saved != null) {
        if (await gateway.exists(saved.eventId)) {
          if (event.sameTimeAs(saved)) return CalendarAddResult.alreadyAdded;
          await gateway.update(saved.eventId, event);
          await store.write(
            SavedSessionEvent.of(
              event,
              saved.eventId,
              calendarId: saved.calendarId,
            ),
          );
          return CalendarAddResult.updated;
        }
        // Deleted in the calendar app: forget it and add it again.
        await store.remove(event.bookingId);
      }
      final created = await gateway.create(event);
      if (created.eventId.isEmpty) return CalendarAddResult.failed;
      await store.write(
        SavedSessionEvent.of(
          event,
          created.eventId,
          calendarId: created.calendarId,
        ),
      );
      return CalendarAddResult.added;
    } catch (_) {
      return CalendarAddResult.failed;
    }
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
      if (await gateway.existsWithoutPrompt(saved.eventId) == false) {
        await store.remove(event.bookingId);
        return SessionCalendarState.notAdded;
      }
      return event.sameTimeAs(saved)
          ? SessionCalendarState.added
          : SessionCalendarState.outdated;
    } catch (_) {
      return SessionCalendarState.notAdded;
    }
  }
}
