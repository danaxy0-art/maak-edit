import 'package:flutter/material.dart';

import '../../backend/services/device_session_calendar.dart';
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(SessionCalendarButton old) {
    super.didUpdateWidget(old);
    // The list reloaded (for example after a reschedule): label again.
    if (old.session['slot_id'] != widget.session['slot_id'] ||
        old.session['starts_at'] != widget.session['starts_at'] ||
        old.session['status'] != widget.session['status']) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!_calendar.gateway.isSupported) return; // web / desktop: never shown
    final state = await _calendar.stateOf(widget.session);
    if (mounted) setState(() => _state = state);
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
