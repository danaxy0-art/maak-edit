import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../../backend/services/personal_reminder_service.dart';
import '../../backend/services/personal_reminder_notification_service.dart';
import 'personal_reminder_form.dart';

class PersonalRemindersPage extends StatefulWidget {
  const PersonalRemindersPage({super.key});

  @override
  State<PersonalRemindersPage> createState() =>
      _PersonalRemindersPageState();
}

class _PersonalRemindersPageState
    extends State<PersonalRemindersPage> {

  static const _accent = Color(0xFFB87580);
  static const _softPink = Color(0xFFFFF1F3);
  static const _border = Color(0xFFEAD8DC);

  late Future<List<Map<String, dynamic>>> _future;

  bool _showCompleted = false;
  bool _busy = false;
  bool _calendarView = false;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    tz_data.initializeTimeZones();
    _future = PersonalReminderService.getReminders();
  }

  // Refresh reminders
  Future<void> _refresh() async {
    if (!mounted) return;

    final future = PersonalReminderService.getReminders();

    setState(() {
      _future = future;
    });

    try {
      await future;
    } catch (_) {
      // Error is displayed by FutureBuilder.
    }
  }

  // Display feedback message
  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Open Add or Edit form
  Future<void> _openForm({
    Map<String, dynamic>? reminder,
  }) async {
    if (_busy) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonalReminderForm(
          reminder: reminder,
          initialDate: reminder == null && _calendarView
              ? _selectedDay
              : null,
        ),
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      if (reminder == null) {
        setState(() {
          _showCompleted = false;
        });
      }

      await _refresh();

      _message(
        reminder == null
            ? 'Reminder added successfully'
            : 'Reminder updated successfully',
      );
    }
  }

  // Complete or restore reminder
  Future<void> _toggleCompleted(
      Map<String, dynamic> reminder,
      ) async {
    if (_busy) return;

    final completed = reminder['is_completed'] == true;

    setState(() {
      _busy = true;
    });

    try {
      Map<String, dynamic>? nextReminder;
      if (completed) {
        await PersonalReminderService.setCompleted(
          id: reminder['id'] as String,
          isCompleted: false,
        );
      } else {
        final result = await PersonalReminderService.completeReminder(
          reminder['id'] as String,
        );
        final next = result['next_reminder'];
        if (next is Map) {
          nextReminder = Map<String, dynamic>.from(next);
        }
      }

      String? notificationWarning;
      try {
        if (completed) {
          final scheduled = await PersonalReminderNotificationService
              .scheduleReminder({...reminder, 'is_completed': false});
          if (!scheduled) {
            notificationWarning = 'Reminder restored, but no notification was scheduled.';
          }
        } else {
          await PersonalReminderNotificationService.cancelReminder(
            reminder['id'] as String,
          );
          if (nextReminder != null) {
            final scheduled = await PersonalReminderNotificationService
                .scheduleReminder(nextReminder);
            if (!scheduled) {
              notificationWarning = 'Next reminder saved, but no notification was scheduled.';
            }
          }
        }
      } catch (e) {
        debugPrint('Reminder notification error: $e');
        notificationWarning = 'Reminder updated, but notification update failed.';
      }

      await _refresh();

      _message(
        notificationWarning ?? (completed
            ? 'Reminder restored'
            : nextReminder != null
            ? 'Completed. Next reminder added.'
            : 'Reminder marked as completed'),
      );
    } catch (_) {
      _message('Could not update reminder.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // Delete reminder or recurring series
  Future<void> _deleteReminder(
      Map<String, dynamic> reminder,
      ) async {
    if (_busy) return;

    final recurring = reminder['repeat_type'] != 'none' ||
        reminder['series_id'] != null;
    String selectedScope = 'single';

    final scope = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(recurring
              ? 'Delete recurring reminder?'
              : 'Delete reminder?'),
          content: recurring
              ? SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose which occurrences to delete.'),
                for (final option in const [
                  ['single', 'This occurrence only',
                    'Delete this reminder and keep the recurrence.'],
                  ['future', 'This and future occurrences',
                    'Stop future reminders and keep previous history.'],
                  ['all', 'All occurrences',
                    'Delete the entire series, including its history.'],
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selectedScope == option[0]
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selectedScope == option[0] ? _accent : Colors.grey,
                    ),
                    title: Text(option[1]),
                    subtitle: Text(option[2]),
                    onTap: () => setDialogState(() {
                      selectedScope = option[0];
                    }),
                  ),
              ],
            ),
          )
              : const Text(
            'This reminder and its personal notes '
                'will be permanently deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedScope),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (scope == null || !mounted || _busy) return;
    setState(() => _busy = true);

    try {
      final result = await PersonalReminderService.deleteReminder(
        reminder['id'] as String,
        scope: scope,
      );

      String? notificationWarning;
      final deletedIds = result['deleted_ids'] as List;
      for (final id in deletedIds) {
        try {
          await PersonalReminderNotificationService.cancelReminder(id as String);
        } catch (e) {
          debugPrint('Reminder notification cancellation error: $e');
          notificationWarning = 'Deleted, but some notifications could not be cancelled.';
        }
      }

      final next = result['next_reminder'];
      if (next is Map) {
        try {
          final scheduled = await PersonalReminderNotificationService
              .scheduleReminder(Map<String, dynamic>.from(next));
          if (!scheduled) {
            notificationWarning = 'Deleted, but notification update was incomplete.';
          }
        } catch (e) {
          debugPrint('Next reminder notification error: $e');
          notificationWarning = 'Deleted, but notification update was incomplete.';
        }
      }

      await _refresh();
      _message(notificationWarning ?? (scope == 'all'
          ? 'Recurring series deleted'
          : scope == 'future'
          ? 'This and future reminders deleted'
          : next is Map
          ? 'Reminder deleted. Next reminder added.'
          : 'Reminder deleted'));
    } catch (e) {
      debugPrint('Reminder deletion error: $e');
      _message('Could not delete reminder.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // Reminder type label
  String _typeLabel(String type) {
    switch (type) {
      case 'medication':
        return 'Medication';

      case 'doctor_appointment':
        return 'Doctor appointment';

      case 'medical_test':
        return 'Medical test';

      default:
        return 'Other';
    }
  }

  // Reminder type icon
  IconData _typeIcon(String type) {
    switch (type) {
      case 'medication':
        return Icons.medication_outlined;

      case 'doctor_appointment':
        return Icons.medical_services_outlined;

      case 'medical_test':
        return Icons.science_outlined;

      default:
        return Icons.event_note_outlined;
    }
  }

  // Repeat label
  String _repeatLabel(String repeat) {
    switch (repeat) {
      case 'daily':
        return 'Daily';

      case 'weekly':
        return 'Weekly';

      case 'monthly':
        return 'Monthly';

      default:
        return 'Does not repeat';
    }
  }

  // Notification preference label
  String _notificationLabel(int minutes) {
    switch (minutes) {
      case 0:
        return 'At scheduled time';

      case 60:
        return '1 hour before';

      case 1440:
        return '1 day before';

      default:
        return '$minutes minutes before';
    }
  }

  // Format date and time
  String _dateTimeLabel(DateTime date) {
    final localizations = MaterialLocalizations.of(context);

    final dateText = localizations.formatMediumDate(date);

    final timeText = TimeOfDay.fromDateTime(date)
        .format(context);

    return '$dateText · $timeText';
  }

  // Upcoming / Completed filter
  Widget _filterButton({
    required String label,
    required bool completed,
  }) {
    final selected = _showCompleted == completed;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _showCompleted = completed;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accent : _border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : const Color(0xFF66575B),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // Empty state
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 42,
        horizontal: 16,
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: _softPink,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showCompleted
                  ? Icons.task_alt
                  : Icons.event_note_outlined,
              color: _accent,
              size: 42,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _showCompleted
                ? 'No completed reminders'
                : 'No reminders yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _showCompleted
                ? 'Your completed reminders will appear here.'
                : 'Add your first appointment or medication '
                'reminder to stay organized.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.grey,
              height: 1.5,
              fontSize: 13,
            ),
          ),

          if (!_showCompleted) ...[
            const SizedBox(height: 22),

            OutlinedButton.icon(
              onPressed: _busy ? null : () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add your first reminder'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Reminder card
  Widget _reminderCard(Map<String, dynamic> reminder) {
    final type = reminder['type'] as String;

    final notes = reminder['notes'] as String? ?? '';

    final completed = reminder['is_completed'] == true;

    final repeat =
        reminder['repeat_type'] as String? ?? 'none';
    final recurringHistory = completed &&
        (repeat != 'none' || reminder['series_id'] != null);

    final remindBefore =
        (reminder['remind_before_minutes'] as num?)
            ?.toInt() ??
            0;

    final scheduledAt = DateTime.parse(
      reminder['scheduled_at'] as String,
    ).toLocal();

    final overdue =
        !completed && scheduledAt.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _softPink,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _typeIcon(type),
                  color: _accent,
                  size: 24,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(type),
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      reminder['title'] as String,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _dateTimeLabel(scheduledAt),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'edit') {
                    _openForm(reminder: reminder);
                  } else if (value == 'delete') {
                    _deleteReminder(reminder);
                  }
                },
                itemBuilder: (_) => [
                  if (!recurringHistory)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (overdue) ...[
            const SizedBox(height: 10),
            const Text(
              'Overdue',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 14),

          if (repeat != 'none') ...[
            Row(
              children: [
                const Icon(
                  Icons.repeat,
                  size: 17,
                  color: _accent,
                ),
                const SizedBox(width: 7),
                Text(
                  _repeatLabel(repeat),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 8),
          ],

          Row(
            children: [
              const Icon(
                Icons.notifications_none,
                size: 17,
                color: _accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Reminder preference: '
                      '${_notificationLabel(remindBefore)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          if (notes.trim().isNotEmpty) ...[
            const Divider(height: 26),

            const Text(
              'Notes & questions',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              notes,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],

          const Divider(height: 26),

          InkWell(
            onTap: _busy || recurringHistory
                ? null
                : () => _toggleCompleted(reminder),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 4,
              ),
              child: Row(
                children: [
                  Icon(
                    completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: completed
                        ? Colors.green
                        : _accent,
                    size: 22,
                  ),

                  const SizedBox(width: 8),

                  Text(
                    completed
                        ? (recurringHistory ? 'Completed' : 'Completed · Mark as incomplete')
                        : 'Mark as completed',
                    style: TextStyle(
                      color: completed
                          ? Colors.green
                          : _accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() => Row(
    children: [
      for (final calendar in [false, true]) ...[
        if (calendar) const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => setState(() => _calendarView = calendar),
          style: OutlinedButton.styleFrom(
            backgroundColor: _calendarView == calendar ? _accent : Colors.white,
            foregroundColor: _calendarView == calendar ? Colors.white : _accent,
            side: const BorderSide(color: _accent),
          ),
          icon: Icon(calendar ? Icons.calendar_month : Icons.view_list),
          label: Text(calendar ? 'Calendar' : 'List'),
        )),
      ],
    ],
  );

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = _month;
    });
  }

  // Project future occurrences for display only, using Riyadh recurrence dates.
  List<Map<String, dynamic>> _monthEvents(List<Map<String, dynamic>> rows) {
    final events = <Map<String, dynamic>>[];
    final end = DateTime(_month.year, _month.month + 1);
    final location = tz.getLocation('Asia/Riyadh');
    bool inMonth(DateTime d) => !d.isBefore(_month) && d.isBefore(end);
    for (final row in rows) {
      final original = DateTime.parse(row['scheduled_at'].toString());
      if (inMonth(original.toLocal())) events.add(row);
      final repeat = row['repeat_type'];
      if (row['is_completed'] == true || repeat == 'none') continue;
      final base = tz.TZDateTime.from(original, location);
      final anchor = (row['anchor_day'] as num?)?.toInt() ?? base.day;
      // Only the displayed month is expanded; no database writes.
      final monthDelta = (_month.year - base.year) * 12 + _month.month - base.month;
      final interval = repeat == 'weekly' ? 7 : 1;
      final days = _month.difference(base.toLocal()).inDays;
      int n = repeat == 'monthly' ? monthDelta - 1 : days ~/ interval - 2;
      if (n < 1) n = 1;
      for (int i = 0; i < 40; i++, n++) {
        late final tz.TZDateTime next;
        if (repeat == 'monthly') {
          final target = DateTime(base.year, base.month + n);
          final last = DateUtils.getDaysInMonth(target.year, target.month);
          next = tz.TZDateTime(location, target.year, target.month,
              anchor.clamp(1, last).toInt(), base.hour, base.minute, base.second);
        } else if (repeat == 'daily' || repeat == 'weekly') {
          next = base.add(Duration(days: n * interval));
        } else {
          break;
        }
        final local = next.toLocal();
        if (!local.isBefore(end)) break;
        if (inMonth(local)) {
          events.add({...row, 'scheduled_at': next.toUtc().toIso8601String(),
            '_projected': true});
        }
      }
    }
    events.sort((a, b) => DateTime.parse(a['scheduled_at'].toString())
        .compareTo(DateTime.parse(b['scheduled_at'].toString())));
    return events;
  }

  Widget _calendar(List<Map<String, dynamic>> reminders) {
    final events = _monthEvents(reminders);
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final day = DateTime.parse(event['scheduled_at'].toString()).toLocal().day;
      (byDay[day] ??= []).add(event);
    }
    final selected = byDay[_selectedDay.day] ?? [];
    final offset = _month.weekday % 7;
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final cells = ((offset + count + 6) ~/ 7) * 7;
    final l10n = MaterialLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: 'Previous month', onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(l10n.formatMonthYear(_month), textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Next month', onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
          ]),
          Row(children: [for (final day in const ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'])
            Expanded(child: Text(day, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)))]),
          const SizedBox(height: 8),
          for (int week = 0; week < cells ~/ 7; week++)
            Row(children: [for (int col = 0; col < 7; col++)
              Expanded(child: _calendarCell(week * 7 + col - offset + 1, count, byDay))]),
          TextButton(onPressed: () => setState(() {
            _selectedDay = DateUtils.dateOnly(DateTime.now());
            _month = DateTime(_selectedDay.year, _selectedDay.month);
          }), child: const Text('Today')),
          const Text('Pink: reminder · Green: completed · Grey: future occurrence',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
      const SizedBox(height: 20),
      Text(l10n.formatFullDate(_selectedDay), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (selected.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text('No reminders on this day'))),
      for (final event in selected)
        if (event['_projected'] == true) _projectedCard(event) else _reminderCard(event),
    ]);
  }

  Widget _calendarCell(int day, int count, Map<int, List<Map<String, dynamic>>> byDay) {
    if (day < 1 || day > count) return const SizedBox(height: 44);
    final date = DateTime(_month.year, _month.month, day);
    final selected = DateUtils.isSameDay(date, _selectedDay);
    final today = DateUtils.isSameDay(date, DateTime.now());
    final events = byDay[day] ?? [];
    return Semantics(selected: selected, button: true, label: '${MaterialLocalizations.of(context).formatFullDate(date)}, ${events.length} reminders',
      child: InkWell(onTap: () => setState(() => _selectedDay = date),
        borderRadius: BorderRadius.circular(10),
        child: Container(height: 44, margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(color: selected ? _accent : today ? _softPink : null,
              borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$day', style: TextStyle(color: selected ? Colors.white : null,
                fontWeight: today || selected ? FontWeight.bold : FontWeight.normal)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final color in <Color>{
                for (final event in events) event['_projected'] == true ? Colors.grey : event['is_completed'] == true ? Colors.green : _accent,
              }) Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: selected ? Colors.white : color, shape: BoxShape.circle)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _projectedCard(Map<String, dynamic> event) => Card(
    child: ListTile(
      leading: Icon(_typeIcon(event['type'] as String), color: _accent),
      title: Text(event['title'] as String),
      subtitle: Text('${_dateTimeLabel(DateTime.parse(event['scheduled_at'].toString()).toLocal())} · ${_repeatLabel(event['repeat_type'] as String)}\nFuture occurrence · Preview only'),
      trailing: const Icon(Icons.repeat, color: Colors.grey),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My health planner'),
        actions: [
          IconButton(
            tooltip: 'Refresh reminders',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openForm(),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),

      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20, 12, 20, 16,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your health, your schedule',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Keep track of your personal appointments '
                        'and health reminders.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _viewToggle(),
                  if (!_calendarView) const SizedBox(height: 10),
                  if (!_calendarView) Row(
                    children: [
                      _filterButton(
                        label: 'Upcoming',
                        completed: false,
                      ),

                      const SizedBox(width: 10),

                      _filterButton(
                        label: 'Completed',
                        completed: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_busy)
              const LinearProgressIndicator(
                color: _accent,
              ),

            Expanded(
              child: FutureBuilder<
                  List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: _accent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'Could not load reminders. Retry',
                        ),
                      ),
                    );
                  }

                  final reminders = (snapshot.data ?? [])
                      .where(
                        (item) =>
                    _calendarView || item['is_completed'] ==
                        _showCompleted,
                  )
                      .toList();

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: _accent,
                    child: ListView(
                      physics:
                      const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        20, 4, 20, 100,
                      ),
                      children: [
                        if (_calendarView)
                          _calendar(reminders)
                        else if (reminders.isEmpty)
                          _emptyState()
                        else
                          ...reminders.map(_reminderCard),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
