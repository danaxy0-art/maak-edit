import 'package:flutter/material.dart';

import '../../backend/services/device_session_calendar.dart';
import '../../backend/services/device_session_reminders.dart';
import '../../backend/services/session_calendar.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'feedback.dart';

// Sprint 4 US5: "Add to calendar" on a confirmed upcoming session card
// (Razan's _SessionCard in sessions.dart). Rules: session_calendar.dart.

/// Shows nothing unless [session] is confirmed, upcoming, and this device
/// has a calendar. Labels: "Add to calendar", "In your calendar",
/// "Update calendar", and a busy state while the calendar works.
class SessionCalendarButton extends StatefulWidget {
  final Map<String, dynamic> session;

  /// Test hook; defaults to the app's calendar.
  final SessionCalendar? calendar;
  const SessionCalendarButton({
    super.key,
    required this.session,
    this.calendar,
  });

  @override
  State<SessionCalendarButton> createState() => _SessionCalendarButtonState();
}

class _SessionCalendarButtonState extends State<SessionCalendarButton> {
  SessionCalendar get _calendar =>
      widget.calendar ?? AppSessionCalendar.instance;

  SessionCalendarState _state = SessionCalendarState.hidden;
  bool _busy = false;

  // Each check gets a number; only the latest one may change the label, so
  // a slow earlier check can't overwrite a newer result.
  int _check = 0;

  @override
  void initState() {
    super.initState();
    _state = _initialState();
    _refresh();
    // US6: a confirmed session appeared on the Sessions screen (for example
    // just accepted): bring the session reminders up to date. Reminders do
    // not depend on the calendar; this widget is only where the screen
    // shows each confirmed session.
    AppSessionReminders.sessionsChanged();
  }

  /// Shown at once for an eligible session ("Add to calendar"), instead of
  /// staying hidden until the device calendar has been checked, which can
  /// take a few seconds. The check then corrects the label if needed.
  SessionCalendarState _initialState() =>
      _calendar.gateway.isSupported &&
          SessionCalendarEvent.fromSession(widget.session) != null
      ? SessionCalendarState.notAdded
      : SessionCalendarState.hidden;

  @override
  void didUpdateWidget(SessionCalendarButton old) {
    super.didUpdateWidget(old);
    // The list reloaded (for example after a reschedule): label again. The
    // end time is checked too, although a new end normally means a new slot.
    const fields = [
      'id',
      'slot_id',
      'starts_at',
      'ends_at',
      'status',
      'display_status',
    ];
    final changedSession = old.session['id'] != widget.session['id'];
    if (old.calendar != widget.calendar ||
        fields.any((f) => old.session[f] != widget.session[f])) {
      if (changedSession || old.calendar != widget.calendar) {
        _state = _initialState();
      }
      _refresh();
      AppSessionReminders.sessionsChanged(); // US6: rescheduled
    }
  }

  @override
  void dispose() {
    // US6: canceled, rescheduled by the help seeker (back to pending), or
    // started: the card no longer shows a confirmed session.
    AppSessionReminders.sessionsChanged();
    super.dispose();
  }

  Future<void> _refresh() async {
    final calendar = _calendar;
    if (!calendar.gateway.isSupported) return; // web / desktop: never shown
    final check = ++_check;
    final state = await calendar.stateOf(widget.session);
    if (mounted && check == _check) setState(() => _state = state);
  }

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _calendar.add(widget.session);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case CalendarAddResult.added:
        showSuccess(context, 'Added to your calendar.');
      case CalendarAddResult.updated:
        showSuccess(context, 'Your calendar now shows the new time.');
      case CalendarAddResult.alreadyAdded:
        _note('This session is already in your calendar.');
      case CalendarAddResult.permissionDenied:
        _note(
          'Allow calendar access in Settings to add sessions to your calendar.',
          settings: true,
        );
      case CalendarAddResult.restricted:
        _note('Calendar access is restricted on this phone.');
      case CalendarAddResult.unavailable:
        _note('Add a calendar account to this phone to save sessions there.');
      case CalendarAddResult.notEligible:
        _note('Only confirmed sessions that have not started can be added.');
      case CalendarAddResult.failed:
        showAppError(
          context,
          ArgumentError('Could not save this session to your calendar.'),
          retry: _tap,
        );
    }
    await _refresh();
  }

  void _note(String message, {bool settings = false}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: settings
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () => AppSessionCalendar.openSettings(),
                  )
                : null,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (_state) {
      SessionCalendarState.hidden => (null, null),
      SessionCalendarState.notAdded => (
        'Add to calendar',
        Icons.event_outlined,
      ),
      SessionCalendarState.added => ('In your calendar', Icons.event_available),
      SessionCalendarState.outdated => (
        'Update calendar',
        Icons.edit_calendar_outlined,
      ),
    };
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: MaakSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // While busy the button shows the app's spinner; this names it.
          Semantics(
            label: _busy ? 'Saving to calendar' : null,
            liveRegion: _busy,
            child: PillButton(
              label,
              key: const ValueKey('session_calendar_button'),
              icon: icon,
              outlined: _state != SessionCalendarState.outdated,
              compact: true,
              busy: _busy,
              // "In your calendar" stays tappable: it re-checks the calendar
              // and adds the event again if it was deleted there.
              onPressed: _busy ? null : _tap,
            ),
          ),
          if (_state == SessionCalendarState.outdated) ...[
            const SizedBox(height: 4),
            Text(
              'The session time changed. Your calendar still shows the old '
              'time until you update it.',
              style: MaakText.caption,
            ),
          ],
        ],
      ),
    );
  }
}
