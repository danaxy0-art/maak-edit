// === ADDED BY RAZAN: session scheduling screens (new file) ===================
// User stories covered here:
//   * Volunteer sets and manages available time slots ........ AvailabilityPage
//   * Help Seeker views a volunteer's available time slots ... VolunteerSlotsPage
//   * Help Seeker requests a session at an available time .... VolunteerSlotsPage
//   * Volunteer accepts or rejects a session request ......... SessionsPage
//   * Help Seeker or Volunteer reschedules or cancels ........ SessionsPage
// Data comes from supabase/migrations/20261121100000_session_scheduling.sql
// through the "ADDED BY RAZAN" methods in supabase_service.dart.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'feedback.dart';
import 'session_calendar_button.dart'; // Sprint 4 US5: add to phone calendar
import 'ui.dart';

// ---- Small date helpers (no extra package needed) ----------------------------
const _kDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _local(Object? value) => DateTime.parse('$value').toLocal();

String _dayText(DateTime d) =>
    '${_kDays[d.weekday - 1]}, ${d.day} ${_kMonths[d.month - 1]} ${d.year}';

String _clockText(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _rangeText(DateTime start, DateTime end) =>
    '${_clockText(start)} – ${_clockText(end)}';

/// "Today", "Tomorrow" or the plain date, for the session card.
String _relativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today · ${_dayText(d)}';
  if (diff == 1) return 'Tomorrow · ${_dayText(d)}';
  return _dayText(d);
}

/// "Starts in 2 h 10 min" for a session that begins within 24 hours.
String? _startsIn(DateTime start) {
  final left = start.difference(DateTime.now());
  if (left.isNegative || left > const Duration(hours: 24)) return null;
  final h = left.inHours;
  final m = left.inMinutes % 60;
  if (h == 0) return 'Starts in ${m < 1 ? 1 : m} min';
  return 'Starts in $h h $m min';
}

/// Shared page frame: title, pull-to-refresh, loading / error / empty states.
class _LoadList extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  )
  item;
  final String emptyTitle, emptyText;
  final Widget Function(VoidCallback reload)? header;
  const _LoadList({
    required this.title,
    required this.load,
    required this.item,
    required this.emptyTitle,
    required this.emptyText,
    this.header,
  });
  @override
  State<_LoadList> createState() => _LoadListState();
}

class _LoadListState extends State<_LoadList> with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _future;

  // The other person's changes (a session accepted, rescheduled or canceled)
  // appear without pulling to refresh: every 30 seconds while the page is
  // open, and when the app comes back to the foreground. Before this, an
  // accepted session showed "Add to calendar" only after a manual refresh.
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _quietRefresh(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _quietRefresh();
  }

  /// Reloads in the background: the list stays on screen (no spinner), and
  /// a failed refresh keeps what is shown; the next one tries again.
  Future<void> _quietRefresh() async {
    if (_refreshing || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _refreshing = true;
    try {
      final rows = await widget.load();
      if (mounted) setState(() => _future = Future.value(rows));
    } catch (_) {
      // Keep the current list.
    } finally {
      _refreshing = false;
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ResponsiveBody(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load data',
              friendlyError(snapshot.error!),
              retry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.header != null) widget.header!(_reload),
                if (rows.isEmpty)
                  EmptyState(widget.emptyTitle, widget.emptyText),
                for (final row in rows)
                  Padding(
                    // Keyed by row id so each card keeps its own state (busy
                    // buttons, calendar label) when the list reloads.
                    key: row['id'] == null
                        ? null
                        : ValueKey('load_list_${row['id']}'),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: widget.item(context, row, _reload),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// Same red and green the chat and reopen-request screens use (support.dart,
// notifications.dart), so session actions look like the rest of the app.
const Color _sessionRed = Color(0xFFB54747);
const Color _sessionGreen = Color(0xFF287A57);

/// Red / green action button, matching the other pages: red outline for
/// Reject, Cancel and Remove (like "Reject appeal"), solid green for Accept
/// (like "Accept & reopen"). A solid red variant is used in confirm dialogs.
class _ToneButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool danger, filled, busy;
  final VoidCallback? onPressed;
  const _ToneButton(
    this.label, {
    this.icon,
    this.danger = false,
    this.filled = false,
    this.busy = false,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final tone = danger ? _sessionRed : _sessionGreen;
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: MaakText.button.copyWith(fontSize: 14),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: MaakSpace.sm),
                Icon(icon, size: 16),
              ],
            ],
          );
    final shape = const StadiumBorder();
    const size = Size(64, 44);
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MaakColors.fill,
              disabledForegroundColor: MaakColors.muted,
              minimumSize: size,
              shape: shape,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: tone,
              backgroundColor: MaakColors.surface,
              side: BorderSide(color: tone, width: 1.5),
              minimumSize: size,
              shape: shape,
            ),
            child: child,
          );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String yes,
  String no = 'Keep it',
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        backgroundColor: MaakColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title),
        content: Text(message),
        actions: [
          PillButton(
            no,
            outlined: true,
            compact: true,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          danger
              ? _ToneButton(
                  yes,
                  danger: true,
                  filled: true,
                  onPressed: () => Navigator.pop(dialogContext, true),
                )
              : PillButton(
                  yes,
                  compact: true,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
        ],
      ),
    ) ??
    false;

// =============================================================================
// Volunteer: set and manage available time slots
// =============================================================================
class AvailabilityPage extends StatelessWidget {
  const AvailabilityPage({super.key});

  // ADDED BY RAZAN: static so the Sessions page can start the same steps from its + button.
  static Future<void> _add(BuildContext context, VoidCallback reload) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      helpText: 'Choose the day',
      // ADDED BY RAZAN: day / month / year order, with the format shown to the member.
      locale: const Locale('en', 'GB'),
      fieldLabelText: 'Date (day/month/year)',
      fieldHintText: 'DD/MM/YYYY',
      errorFormatText: 'Write the date as DD/MM/YYYY',
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'Choose the start time',
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null || !context.mounted) return;
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('How long is this time slot?'),
        children: [
          for (final m in const [30, 45, 60, 90, 120])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, m),
              child: Text(m < 60 ? '$m minutes' : '${m ~/ 60}h ${m % 60}m'),
            ),
        ],
      ),
    );
    if (minutes == null || !context.mounted) return;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!start.isAfter(DateTime.now())) {
      showAppError(context, ArgumentError('Choose a time in the future.'));
      return;
    }
    try {
      await SupabaseService.addTimeSlot(
        start,
        start.add(Duration(minutes: minutes)),
      );
      if (context.mounted) showSuccess(context, 'Time slot added.');
      reload();
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    }
  }

  Future<void> _remove(
    BuildContext context,
    Map<String, dynamic> slot,
    VoidCallback reload,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Remove this time slot?',
      message:
          'Help seekers will no longer see ${_dayText(_local(slot['starts_at']))} at ${_clockText(_local(slot['starts_at']))}.',
      yes: 'Remove',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await SupabaseService.removeTimeSlot(slot['id'] as String);
      if (context.mounted) showSuccess(context, 'Time slot removed.');
      reload();
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => _LoadList(
    title: 'My available times',
    load: SupabaseService.getMyTimeSlots,
    emptyTitle: 'No time slots yet',
    emptyText:
        'Add the times you can support someone. Help seekers can only request a session at these times.',
    header: (reload) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PillButton(
        'Add a time slot',
        icon: Icons.add,
        expand: true,
        onPressed: () => _add(context, reload),
      ),
    ),
    item: (context, slot, reload) {
      final start = _local(slot['starts_at']);
      final end = _local(slot['ends_at']);
      final status = slot['booking_status'] as String?;
      final who = slot['seeker_name'] as String? ?? 'A help seeker';
      return SoftCard(
        child: Row(
          children: [
            const IconBadge(Icons.event_available_outlined, size: 44),
            const SizedBox(width: MaakSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayText(start),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rangeText(start, end),
                    style: const TextStyle(color: MaakColors.muted),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      status == 'accepted'
                          ? 'Confirmed with $who'
                          : '$who is waiting for your answer (see Sessions)',
                      style: MaakText.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (status == null)
              IconButton(
                tooltip: 'Remove time slot',
                icon: const Icon(Icons.delete_outline, color: _sessionRed),
                onPressed: () => _remove(context, slot, reload),
              ),
          ],
        ),
      );
    },
  );
}

// =============================================================================
// Help Seeker: view a volunteer's open slots, then request a session.
// With [rescheduleBookingId] the same list is used to move an existing session.
// =============================================================================
class VolunteerSlotsPage extends StatelessWidget {
  final String volunteerId;
  final String volunteerName;
  final String? rescheduleBookingId;

  /// True when a volunteer is moving a session onto one of their own slots.
  final bool ownSlots;

  /// The other person in the session (shown when rescheduling).
  final String? peerName;
  const VolunteerSlotsPage({
    super.key,
    required this.volunteerId,
    required this.volunteerName,
    this.rescheduleBookingId,
    this.ownSlots = false,
    this.peerName,
  });

  bool get _moving => rescheduleBookingId != null;

  Future<void> _choose(
    BuildContext context,
    Map<String, dynamic> slot,
    VoidCallback reload,
  ) async {
    final start = _local(slot['starts_at']);
    final end = _local(slot['ends_at']);
    final when = '${_dayText(start)}, ${_rangeText(start, end)}';
    final ok = await _confirm(
      context,
      title: _moving ? 'Move the session here?' : 'Request this time?',
      message: _moving
          ? 'Move your session with ${peerName ?? volunteerName} to $when? ${ownSlots ? 'They will be told.' : 'The volunteer may need to confirm again.'}'
          : 'Ask $volunteerName for a session on $when? They will accept or decline.',
      yes: _moving ? 'Move session' : 'Send request',
      no: 'Not now',
    );
    if (!ok || !context.mounted) return;
    try {
      if (_moving) {
        await SupabaseService.rescheduleSession(
          rescheduleBookingId!,
          slot['id'] as String,
        );
      } else {
        await SupabaseService.requestSession(slot['id'] as String);
      }
      if (!context.mounted) return;
      showSuccess(
        context,
        _moving ? 'Session rescheduled.' : 'Session request sent.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (context.mounted) {
        showAppError(context, e);
        reload(); // the slot may have just been taken by someone else
      }
    }
  }

  @override
  Widget build(BuildContext context) => _LoadList(
    title: _moving ? 'Choose a new time' : 'Available times',
    load: () => SupabaseService.getAvailableSlots(volunteerId),
    emptyTitle: 'No available times',
    emptyText: _moving
        ? (ownSlots
              ? 'You have no other open times. Add more under My available times.'
              : '$volunteerName has no other open times right now.')
        : '$volunteerName has not shared any open times yet. Check again later.',
    header: (_) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        ownSlots
            ? 'Choose one of your open times to move this session to.'
            : 'Times shown in your local time. Tap a time to ${_moving ? 'move your session' : 'request a session'} with $volunteerName.',
        style: MaakText.body,
      ),
    ),
    item: (context, slot, reload) {
      final start = _local(slot['starts_at']);
      final end = _local(slot['ends_at']);
      return SoftCard(
        onTap: () => _choose(context, slot, reload),
        child: Row(
          children: [
            const IconBadge(Icons.schedule, size: 44),
            const SizedBox(width: MaakSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayText(start),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rangeText(start, end),
                    style: const TextStyle(color: MaakColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    },
  );
}

// =============================================================================
// Both roles: my sessions (accept / reject, reschedule, cancel)
// =============================================================================
class SessionsPage extends StatelessWidget {
  final String role;
  const SessionsPage({super.key, required this.role});

  bool get _volunteer => role == 'volunteer';

  @override
  Widget build(BuildContext context) => _LoadList(
    title: 'Sessions',
    load: SupabaseService.getMySessions,
    emptyTitle: 'No sessions yet',
    emptyText: _volunteer
        ? 'Session requests from help seekers will appear here.'
        : 'Open a volunteer\'s profile and choose an available time to request a session.',
    header: (_) => _volunteer
        ? Padding(
            padding: const EdgeInsets.only(bottom: 14),
            // ADDED BY RAZAN: one tap on + starts adding a time slot.
            child: Column(
              children: [
                PillButton(
                  'Add a time slot',
                  icon: Icons.add,
                  expand: true,
                  onPressed: () => AvailabilityPage._add(context, () {}),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('My available times'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AvailabilityPage()),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink(),
    item: (context, session, reload) =>
        _SessionCard(session: session, reload: reload),
  );
}

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback reload;
  const _SessionCard({required this.session, required this.reload});
  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _busy = false;

  Map<String, dynamic> get s => widget.session;
  bool get _isVolunteer => s['is_volunteer'] == true;
  String get _id => s['id'] as String;
  DateTime get _start => _local(s['starts_at']);
  DateTime get _end => _local(s['ends_at']);
  String get _status => '${s['display_status']}';
  bool get _live =>
      _status == 'pending' || _status == 'accepted' || _status == 'in_progress';
  bool get _future => _start.isAfter(DateTime.now());

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSuccess(context, done);
      widget.reload();
    } catch (e) {
      if (mounted) {
        showAppError(context, e);
        widget.reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool accept) async {
    if (!accept) {
      final ok = await _confirm(
        context,
        title: 'Decline this session?',
        message:
            'You will not be offered ${_dayText(_start)}, ${_clockText(_start)} again. The help seeker will be told.',
        yes: 'Decline',
        no: 'Back',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    await _run(
      () => SupabaseService.decideSession(_id, accept),
      accept ? 'Session confirmed.' : 'Session declined.',
    );
  }

  Future<void> _cancel() async {
    final ok = await _confirm(
      context,
      title: 'Cancel this session?',
      message:
          '${_dayText(_start)}, ${_rangeText(_start, _end)} with ${s['contact_name'] ?? 'your peer'} will be canceled and they will be told.',
      yes: 'Cancel session',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(() => SupabaseService.cancelSession(_id), 'Session canceled.');
  }

  Future<void> _reschedule() async {
    // Pick a new time from the volunteer's open slots (your own if you are the volunteer).
    final volunteerId = s['volunteer_id'] as String;
    final peer = '${s['contact_name'] ?? 'your peer'}';
    final moved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VolunteerSlotsPage(
          volunteerId: volunteerId,
          volunteerName: _isVolunteer ? 'you' : peer,
          rescheduleBookingId: _id,
          ownSlots: _isVolunteer,
          peerName: peer,
        ),
      ),
    );
    if (moved == true) widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final name = s['contact_name'] as String? ?? 'Your peer';
    final (label, icon, color) = switch (_status) {
      'pending' => ('Awaiting response', Icons.schedule, MaakColors.pending),
      'accepted' => ('Confirmed', Icons.check, const Color(0xFFCDEFD8)),
      'in_progress' => (
        'Happening now',
        Icons.play_circle_outline,
        const Color(0xFFCDEFD8),
      ),
      'completed' => ('Completed', Icons.task_alt, const Color(0xFFE3E5E8)),
      'rejected' => ('Declined', Icons.close, const Color(0xFFFAC9C9)),
      'canceled' => ('Canceled', Icons.block, const Color(0xFFFAC9C9)),
      _ => ('Expired', Icons.history, const Color(0xFFE3E5E8)),
    };
    final canAnswer = _isVolunteer && _status == 'pending' && _future;
    // A volunteer answers a pending request with Accept / Decline only;
    // Reschedule and Cancel are for requests that are already confirmed, and
    // for the help seeker's own requests.
    final canChange = _live && _future && !canAnswer;
    final reschedulesLeft = 3 - ((s['reschedule_count'] as num?)?.toInt() ?? 0);
    return SoftCard(
      flat: !_live,
      color: _live ? MaakColors.surface : MaakColors.warmWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              StatusPill(label: label, icon: icon, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(_relativeDay(_start), style: MaakText.body),
          Text(
            _rangeText(_start, _end),
            style: const TextStyle(color: MaakColors.muted),
          ),
          if (_status == 'accepted' && _startsIn(_start) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _startsIn(_start)!,
                style: MaakText.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          // Sprint 4 US5: confirmed, upcoming sessions only; hidden on web.
          if (_status == 'accepted' && _future)
            SessionCalendarButton(session: s),
          if (_status == 'canceled' && s['canceled_by_me'] != true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Canceled by the other person.',
                style: MaakText.caption,
              ),
            ),
          if (canAnswer) ...[
            const SizedBox(height: MaakSpace.md),
            Row(
              children: [
                Expanded(
                  child: _ToneButton(
                    'Decline',
                    icon: Icons.close,
                    danger: true,
                    onPressed: _busy ? null : () => _decide(false),
                  ),
                ),
                const SizedBox(width: MaakSpace.sm),
                Expanded(
                  child: _ToneButton(
                    'Accept',
                    icon: Icons.check,
                    filled: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => _decide(true),
                  ),
                ),
              ],
            ),
          ],
          if (canChange) ...[
            const SizedBox(height: MaakSpace.sm),
            Row(
              children: [
                if (reschedulesLeft > 0)
                  Expanded(
                    child: PillButton(
                      'Reschedule',
                      icon: Icons.event_repeat_outlined,
                      outlined: true,
                      compact: true,
                      onPressed: _busy ? null : _reschedule,
                    ),
                  ),
                if (reschedulesLeft > 0) const SizedBox(width: MaakSpace.sm),
                Expanded(
                  child: _ToneButton(
                    'Cancel',
                    icon: Icons.close,
                    danger: true,
                    onPressed: _busy ? null : _cancel,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// === END ADDED BY RAZAN ======================================================
