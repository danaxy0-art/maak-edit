import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_calendar.dart';
import 'supabase_service.dart';

// Sprint 4 US5: the real device calendar (device_calendar_plus 0.12.0) and
// the local record of what this device added (shared_preferences).
//
// Permission: full calendar access. Write-only access can add events, but the
// plugin needs full access to look an event up or move it (getEvent and
// updateEvent), which duplicate prevention and rescheduling require. It is
// requested only from [SessionCalendar.add], which runs on a member's tap.

/// device_calendar_plus behind [CalendarGateway]. On web and desktop
/// [isSupported] is false and the plugin is never touched.
class DeviceCalendarGateway implements CalendarGateway {
  DeviceCalendarGateway({DeviceCalendar? plugin}) : _override = plugin;
  final DeviceCalendar? _override;
  DeviceCalendar get _plugin => _override ?? DeviceCalendar.instance;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<CalendarAccess> requestAccess() async {
    var status = await _plugin.hasPermissions();
    // Not asked yet, or only "add events" was allowed: ask for full access.
    if (status == CalendarPermissionStatus.notDetermined ||
        status == CalendarPermissionStatus.writeOnly) {
      status = await _plugin.requestPermissions();
    }
    switch (status) {
      case CalendarPermissionStatus.granted:
        // A phone with no calendar account cannot store events.
        final calendars = await _plugin.listCalendars();
        return calendars.any((c) => !c.readOnly)
            ? CalendarAccess.granted
            : CalendarAccess.unavailable;
      case CalendarPermissionStatus.restricted:
        return CalendarAccess.restricted;
      case CalendarPermissionStatus.denied:
      case CalendarPermissionStatus.writeOnly:
      case CalendarPermissionStatus.notDetermined:
        return CalendarAccess.denied;
    }
  }

  @override
  Future<CreatedCalendarEvent> create(SessionCalendarEvent event) async {
    final id = await _plugin.createEvent(
      title: SessionCalendarEvent.title,
      // Exact instants; the calendar shows them in the device's time zone.
      startDate: event.startUtc,
      endDate: event.endUtc,
      description: SessionCalendarEvent.notes,
    );
    // Read it back: "added" is reported only for an event that exists.
    final saved = await _plugin.getEvent(id);
    if (saved == null) {
      throw StateError('The calendar did not keep the new event.');
    }
    return CreatedCalendarEvent(id, calendarId: saved.calendarId);
  }

  @override
  Future<bool> exists(String eventId) async {
    try {
      return await _plugin.getEvent(eventId) != null;
    } on DeviceCalendarException catch (e) {
      if (e.errorCode == DeviceCalendarError.notFound) return false;
      rethrow;
    }
  }

  @override
  Future<bool?> existsWithoutPrompt(String eventId) async {
    if (await _plugin.hasPermissions() != CalendarPermissionStatus.granted) {
      return null;
    }
    return exists(eventId);
  }

  @override
  Future<void> update(String eventId, SessionCalendarEvent event) =>
      _plugin.updateEvent(
        instanceId: eventId,
        title: SessionCalendarEvent.title,
        startDate: event.startUtc,
        endDate: event.endUtc,
        description: const Patch.set(SessionCalendarEvent.notes),
      );

  /// Opens the app's settings so the member can allow calendar access.
  Future<void> openSettings() => _plugin.openAppSettings();
}

/// Records in shared_preferences, one key per signed-in member and booking,
/// so another account on the same phone never sees or reuses them.
class PrefsSavedSessionStore implements SavedSessionStore {
  PrefsSavedSessionStore({String? Function()? userId})
    : _userId = userId ?? (() => SupabaseService.currentUser?.id);
  final String? Function() _userId;

  static const _prefix = 'maak.session_calendar.v1';

  String _key(String bookingId) {
    final user = _userId();
    if (user == null || user.isEmpty) {
      throw StateError('Calendar records need a signed-in member.');
    }
    return '$_prefix.$user.$bookingId';
  }

  @override
  Future<SavedSessionEvent?> read(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(bookingId));
    if (raw == null) return null;
    try {
      return SavedSessionEvent.fromJson(jsonDecode(raw));
    } on FormatException {
      return null; // A damaged record is treated as never added.
    }
  }

  @override
  Future<void> write(SavedSessionEvent saved) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key(saved.bookingId),
      jsonEncode(saved.toJson()),
    )) {
      throw StateError('Could not remember the calendar event.');
    }
  }

  @override
  Future<void> remove(String bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(bookingId));
  }
}

/// The app-wide calendar helper. Tests replace it.
class AppSessionCalendar {
  AppSessionCalendar._();

  static final _gateway = DeviceCalendarGateway();
  static SessionCalendar? _instance;

  static SessionCalendar get instance => _instance ??= SessionCalendar(
    gateway: _gateway,
    store: PrefsSavedSessionStore(),
  );

  /// Opens the app's settings (after calendar access was denied).
  static Future<void> openSettings() async {
    final gateway = instance.gateway;
    if (gateway is DeviceCalendarGateway && gateway.isSupported) {
      await gateway.openSettings();
    }
  }

  @visibleForTesting
  static set instance(SessionCalendar? value) => _instance = value;
}
