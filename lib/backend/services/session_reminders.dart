import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'session_calendar.dart' show SessionCalendarEvent;

// Sprint 4 US6: reminders before confirmed support sessions.
//
// The reminders are generated and scheduled on the phone itself (Android
// local notifications). Nothing is written to or read from the notifications
// table: only the session list comes from Supabase (my_maak_sessions(), Razan's
// session scheduling), the same rows the Sessions screen shows. Razan's
// support_session notifications (request, confirmed, canceled, rescheduled)
// are separate and unchanged; these reminders never duplicate them.
//
// This file holds the rules, independent of the notification plugin:
//  * which sessions get reminders: confirmed and still upcoming, for the help
//    seeker and the volunteer alike (both see the session in their list);
//  * when: [leadTimes] before the start, skipping times that have passed;
//  * what they say: neutral text with no names, roles, conditions or times;
//  * keeping them in step with the sessions: a reconcile, run whenever fresh
//    session data is available, schedules what is missing, moves what was
//    rescheduled and cancels what was canceled or is no longer eligible;
//  * one reminder per account, booking and lead time, with an id this
//    device allocated for it (never reused while it is in use), so the
//    same reminder is never scheduled twice;
//  * reminders of an account that signed out or turned reminders off are
//    canceled.
// The phone's notification system sits behind [ReminderScheduler]; what this
// device scheduled sits behind [ReminderStore].
//
// Times are exact instants (UTC), so a time-zone or daylight-saving change on
// the phone never moves a reminder, and the text says "in 1 hour" rather than
// a clock time that could be read in the wrong zone.
//
// Limit: a reminder is scheduled on this phone from the last session list it
// saw. If the OTHER participant cancels or reschedules while this app is not
// running, the old reminder can still fire; it is corrected the next time
// the app opens, returns to the foreground, or receives the change.

/// One reminder this device should show.
@immutable
class PlannedReminder {
  final String bookingId;
  final Duration lead;

  /// When it is shown, and when the session starts (both UTC).
  final DateTime atUtc, startUtc;
  const PlannedReminder({
    required this.bookingId,
    required this.lead,
    required this.atUtc,
    required this.startUtc,
  });
}

/// A reminder this device scheduled, as remembered between app runs.
@immutable
class ScheduledReminder {
  final String userId, bookingId;
  final int leadMinutes, id;
  final DateTime atUtc, startUtc;
  const ScheduledReminder({
    required this.userId,
    required this.bookingId,
    required this.leadMinutes,
    required this.id,
    required this.atUtc,
    required this.startUtc,
  });

  String get key => SessionReminders.keyOf(userId, bookingId, leadMinutes);

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'booking_id': bookingId,
    'lead_minutes': leadMinutes,
    'id': id,
    'at': atUtc.toIso8601String(),
    'starts_at': startUtc.toIso8601String(),
  };

  static ScheduledReminder? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = json['user_id'], booking = json['booking_id'];
    final lead = json['lead_minutes'], id = json['id'];
    final at = DateTime.tryParse('${json['at']}');
    final start = DateTime.tryParse('${json['starts_at']}');
    if (user is! String ||
        booking is! String ||
        lead is! int ||
        id is! int ||
        at == null ||
        start == null) {
      return null;
    }
    return ScheduledReminder(
      userId: user,
      bookingId: booking,
      leadMinutes: lead,
      id: id,
      atUtc: at.toUtc(),
      startUtc: start.toUtc(),
    );
  }
}

/// The phone's notification system. Implemented with
/// flutter_local_notifications (device_session_reminders.dart).
abstract class ReminderScheduler {
  /// False where reminders cannot be scheduled (web, desktop). When false
  /// nothing else is called.
  bool get isSupported;

  /// Schedules notification [id] at [atUtc], replacing any with that id.
  Future<void> schedule({
    required int id,
    required DateTime atUtc,
    required String title,
    required String body,
  });

  /// Cancels notification [id]: removes it if shown, and its alarm if not.
  Future<void> cancel(int id);
}

/// Local storage for what this device scheduled, and the opt-out setting.
abstract class ReminderStore {
  Future<String?> readRegistry();
  Future<void> writeRegistry(String json);

  /// Null until the member changes the setting (reminders are on).
  Future<bool?> readEnabled(String userId);
  Future<void> writeEnabled(String userId, bool enabled);
}

class SessionReminders {
  SessionReminders({required this.scheduler, required this.store});

  final ReminderScheduler scheduler;
  final ReminderStore store;

  /// Android notification channel of the reminders (Settings shows it as
  /// "Session reminders"). Other notification code leaves this channel's
  /// notifications alone.
  static const channelId = 'maak_session_reminders';

  /// Reminders before each confirmed session, longest first.
  static const leadTimes = [Duration(hours: 1), Duration(minutes: 10)];

  /// Neutral wording only: it can show on the lock screen.
  static const title = 'Upcoming support session';
  static String bodyFor(Duration lead) =>
      "Your Ma'ak session starts in ${_describe(lead)}.";

  static String _describe(Duration lead) {
    if (lead.inMinutes % 60 == 0) {
      final hours = lead.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return lead.inMinutes == 1 ? '1 minute' : '${lead.inMinutes} minutes';
  }

  /// Ids are allocated from here, one per reminder, and kept while in use.
  static const firstId = 0x3E000000;
  static const lastId = 0x3EFFFFFF;

  /// [id] if it lies outside the reminders' range, otherwise the matching id
  /// in the next block (0x3F……). Other code that derives notification ids
  /// (for example from a hash) passes them through this, so it can never
  /// show, replace or cancel a session reminder by accident.
  static int outsideReminderIds(int id) =>
      id >= firstId && id <= lastId ? id ^ 0x01000000 : id;

  static String keyOf(String userId, String bookingId, int leadMinutes) =>
      '$userId|$bookingId|$leadMinutes';

  /// The reminders [sessions] (rows of my_maak_sessions()) call for at [now]:
  /// confirmed, upcoming sessions only, and only reminder times still ahead.
  static List<PlannedReminder> plan(
    Iterable<Map<String, dynamic>> sessions,
    DateTime now,
  ) {
    final result = <PlannedReminder>[];
    final seen = <String>{};
    for (final s in sessions) {
      // Same rule as "Add to calendar": accepted, not started, valid times.
      final e = SessionCalendarEvent.fromSession(s, now: now);
      if (e == null || !seen.add(e.bookingId)) continue;
      for (final lead in leadTimes) {
        final at = e.startUtc.subtract(lead);
        if (!at.isAfter(now)) continue; // already passed: skipped
        result.add(
          PlannedReminder(
            bookingId: e.bookingId,
            lead: lead,
            atUtc: at,
            startUtc: e.startUtc,
          ),
        );
      }
    }
    return result;
  }

  /// Whether [userId] wants reminders (on unless turned off).
  Future<bool> isEnabled(String userId) async =>
      await store.readEnabled(userId) ?? true;

  /// Turns reminders on or off for [userId]. Off cancels theirs at once; on
  /// takes effect at the next [reconcile].
  Future<void> setEnabled(String userId, bool enabled) async {
    await store.writeEnabled(userId, enabled);
    if (!enabled) await _run(() => _cancelWhere((r) => r.userId == userId));
  }

  /// Brings this device's reminders in line with [sessions], the signed-in
  /// member [userId]'s session list just loaded from the server. Reminders
  /// of any other account are canceled. Calls run one at a time.
  Future<void> reconcile({
    required String userId,
    required List<Map<String, dynamic>> sessions,
    DateTime? now,
  }) => _run(() => _reconcile(userId, sessions, now ?? DateTime.now()));

  /// Cancels every reminder this device scheduled, for every account (sign
  /// out).
  Future<void> cancelAll() => _run(() => _cancelWhere((_) => true));

  Future<void> _queue = Future.value();
  Future<void> _run(Future<void> Function() step) {
    final next = _queue.then((_) => step());
    _queue = next.catchError((Object e) {
      debugPrint('Session reminders: ${e.runtimeType}');
    });
    return next;
  }

  Future<void> _reconcile(
    String userId,
    List<Map<String, dynamic>> sessions,
    DateTime now,
  ) async {
    if (!scheduler.isSupported) return;
    final registry = await _load();
    final enabled = await isEnabled(userId);
    final wanted = <String, PlannedReminder>{
      if (enabled)
        for (final p in plan(sessions, now))
          keyOf(userId, p.bookingId, p.lead.inMinutes): p,
    };
    // Bookings still confirmed and upcoming, with their start time.
    final upcoming = <String, DateTime>{
      for (final s in sessions)
        if (SessionCalendarEvent.fromSession(s, now: now) case final e?)
          e.bookingId: e.startUtc,
    };

    final keep = <String, ScheduledReminder>{};
    for (final r in registry.values) {
      final want = wanted[r.key];
      if (r.userId != userId || !enabled) {
        await scheduler.cancel(r.id); // another account, or turned off
      } else if (want != null) {
        if (!want.atUtc.isAtSameMomentAs(r.atUtc)) {
          // Rescheduled: the old time goes, the new one is set below.
          await scheduler.cancel(r.id);
        }
        keep[r.key] = r;
      } else if (upcoming[r.bookingId] case final start?
          when start.isAtSameMomentAs(r.startUtc)) {
        // Same session, this reminder's time has passed: it was shown (or
        // is about to be). Left as it is, so it is not removed from view.
        keep[r.key] = r;
      } else if (!r.startUtc.isAfter(now)) {
        // The session has started: nothing left to change.
      } else {
        await scheduler.cancel(r.id); // canceled, moved or not eligible
      }
    }

    final used = {for (final r in keep.values) r.id};
    var next = await _nextId(used);
    for (final MapEntry(key: key, value: p) in wanted.entries) {
      final old = keep[key];
      final id = old?.id ?? next;
      if (old == null) {
        used.add(id);
        next = _advance(id, used);
      }
      // Scheduled again every time: replaces the alarm with the same id, and
      // restores one the system dropped (for example after exact alarms
      // were turned off for the app).
      await scheduler.schedule(
        id: id,
        atUtc: p.atUtc,
        title: title,
        body: bodyFor(p.lead),
      );
      keep[key] = ScheduledReminder(
        userId: userId,
        bookingId: p.bookingId,
        leadMinutes: p.lead.inMinutes,
        id: id,
        atUtc: p.atUtc,
        startUtc: p.startUtc,
      );
      await _save(keep, next);
    }
    await _save(keep, next);
  }

  Future<void> _cancelWhere(bool Function(ScheduledReminder) test) async {
    if (!scheduler.isSupported) return;
    final registry = await _load();
    final keep = <String, ScheduledReminder>{};
    for (final r in registry.values) {
      if (test(r)) {
        await scheduler.cancel(r.id);
      } else {
        keep[r.key] = r;
      }
    }
    await _save(keep, await _nextId({for (final r in keep.values) r.id}));
  }

  // Registry ---------------------------------------------------------------

  int? _storedNext;

  Future<Map<String, ScheduledReminder>> _load() async {
    final raw = await store.readRegistry();
    final result = <String, ScheduledReminder>{};
    _storedNext = null;
    if (raw == null) return result;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final next = json['next'];
        if (next is int) _storedNext = next;
        final list = json['reminders'];
        if (list is List) {
          for (final item in list) {
            final r = ScheduledReminder.fromJson(item);
            if (r != null) result[r.key] = r;
          }
        }
      }
    } on FormatException {
      // Unreadable: start afresh (the alarms it described are replaced as
      // soon as the same reminders are scheduled again).
    }
    return result;
  }

  Future<void> _save(Map<String, ScheduledReminder> reminders, int next) =>
      store.writeRegistry(
        jsonEncode({
          'next': next,
          'reminders': [for (final r in reminders.values) r.toJson()],
        }),
      );

  Future<int> _nextId(Set<int> used) async {
    final stored = _storedNext;
    final start = stored != null && stored >= firstId && stored <= lastId
        ? stored
        : firstId;
    return used.contains(start) ? _advance(start, used) : start;
  }

  /// The next id after [id] that is not in [used] (wrapping in the range).
  static int _advance(int id, Set<int> used) {
    var next = id;
    do {
      next = next >= lastId ? firstId : next + 1;
    } while (used.contains(next));
    return next;
  }
}
