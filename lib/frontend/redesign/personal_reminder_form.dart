import 'package:flutter/material.dart';
import '../../backend/services/personal_reminder_service.dart';
import '../../backend/services/personal_reminder_notification_service.dart';

class PersonalReminderForm extends StatefulWidget {
  final Map<String, dynamic>? reminder;
  final DateTime? initialDate;

  const PersonalReminderForm({
    super.key,
    this.reminder,
    this.initialDate,
  });

  @override
  State<PersonalReminderForm> createState() =>
      _PersonalReminderFormState();
}

class _PersonalReminderFormState
    extends State<PersonalReminderForm> {

  static const _accent = Color(0xFFB87580);
  static const _softPink = Color(0xFFFFF1F3);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  late DateTime _date;
  late TimeOfDay _time;

  String _type = 'medication';
  String _repeatType = 'none';
  int _remindBefore = 0;

  bool _saving = false;

  bool get _isEditing => widget.reminder != null;

  @override
  void initState() {
    super.initState();

    final reminder = widget.reminder;

    _titleController = TextEditingController(
      text: reminder?['title'] as String? ?? '',
    );

    _notesController = TextEditingController(
      text: reminder?['notes'] as String? ?? '',
    );

    final defaultTime =
    DateTime.now().add(const Duration(hours: 1));

    final initialDate = widget.initialDate;

    final scheduledAt = reminder != null
        ? DateTime.parse(
      reminder['scheduled_at'] as String,
    ).toLocal()
        : initialDate != null
        ? DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
      defaultTime.hour,
      defaultTime.minute,
    )
        : defaultTime;

    _date = scheduledAt;
    _time = TimeOfDay.fromDateTime(scheduledAt);

    _type = reminder?['type'] as String? ?? 'medication';

    _repeatType =
        reminder?['repeat_type'] as String? ?? 'none';

    _remindBefore =
        (reminder?['remind_before_minutes'] as num?)
            ?.toInt() ??
            0;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Select date
  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedDate = DateUtils.dateOnly(_date);

    final firstDate = selectedDate.isBefore(today)
        ? selectedDate
        : today;

    final lastDate = DateTime(today.year + 10);

    final selected = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: firstDate,
      lastDate: selectedDate.isAfter(lastDate)
          ? selectedDate
          : lastDate,
    );

    if (selected != null && mounted) {
      setState(() {
        _date = selected;
      });
    }
  }

  // Select time
  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time,
    );

    if (selected != null && mounted) {
      setState(() {
        _time = selected;
      });
    }
  }

  // Save reminder
  Future<void> _save() async {
    if (_saving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final scheduledAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    if (scheduledAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a future date and time.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      Map<String, dynamic> savedReminder;

      if (_isEditing) {
        savedReminder = await PersonalReminderService.updateReminder(
          id: widget.reminder!['id'] as String,
          title: _titleController.text,
          type: _type,
          scheduledAt: scheduledAt,
          notes: _notesController.text,
          repeatType: _repeatType,
          remindBeforeMinutes: _remindBefore,
        );
      } else {
        savedReminder = await PersonalReminderService.createReminder(
          title: _titleController.text,
          type: _type,
          scheduledAt: scheduledAt,
          notes: _notesController.text,
          repeatType: _repeatType,
          remindBeforeMinutes: _remindBefore,
        );
      }

      try {
        final scheduled = await PersonalReminderNotificationService
            .scheduleReminder(savedReminder);

        if (!scheduled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder saved, but notification was not scheduled.',
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Reminder notification error: $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder saved, but notification scheduling failed.',
              ),
            ),
          );
        }
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);

    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save reminder. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // Section label
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Reminder type card
  Widget _typeCard({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _type == value;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _saving
          ? null
          : () {
        setState(() {
          _type = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: selected ? _softPink : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _accent
                : const Color(0xFFEAD8DC),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: _accent,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Date and time button
  Widget _pickerButton({
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFEAD8DC),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: _accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFEAD8DC),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFEAD8DC),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _accent,
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(_date);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit reminder' : 'Add reminder',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _label('Reminder type'),

              Row(
                children: [
                  Expanded(
                    child: _typeCard(
                      value: 'medication',
                      label: 'Medication',
                      icon: Icons.medication_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _typeCard(
                      value: 'doctor_appointment',
                      label: 'Doctor appointment',
                      icon: Icons.medical_services_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _typeCard(
                      value: 'medical_test',
                      label: 'Medical test',
                      icon: Icons.science_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _typeCard(
                      value: 'other',
                      label: 'Other',
                      icon: Icons.event_note_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _label('Title *'),

              TextFormField(
                controller: _titleController,
                enabled: !_saving,
                maxLength: 150,
                decoration: _decoration(
                  'Enter reminder title',
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'Please enter a title';
                  }

                  if (value.trim().length > 150) {
                    return 'Title is too long';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        _label('Date *'),
                        _pickerButton(
                          text: dateText,
                          icon: Icons.calendar_today_outlined,
                          onTap: _pickDate,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        _label('Time *'),
                        _pickerButton(
                          text: _time.format(context),
                          icon: Icons.access_time,
                          onTap: _pickTime,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _label('Notes & questions'),

              TextFormField(
                controller: _notesController,
                enabled: !_saving,
                minLines: 4,
                maxLines: 6,
                decoration: _decoration(
                  'Write anything you want to remember...',
                ),
              ),

              const SizedBox(height: 24),

              _label('Repeat'),

              DropdownButtonFormField<String>(
                initialValue: _repeatType,
                isExpanded: true,
                decoration: _decoration('Repeat'),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('Does not repeat'),
                  ),
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text('Daily'),
                  ),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text('Weekly'),
                  ),
                  DropdownMenuItem(
                    value: 'monthly',
                    child: Text('Monthly'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                  if (value != null) {
                    setState(() {
                      _repeatType = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              _label('Remind me'),

              DropdownButtonFormField<int>(
                initialValue: _remindBefore,
                isExpanded: true,
                decoration: _decoration('Reminder time'),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('At scheduled time'),
                  ),
                  const DropdownMenuItem(
                    value: 15,
                    child: Text('15 minutes before'),
                  ),
                  const DropdownMenuItem(
                    value: 30,
                    child: Text('30 minutes before'),
                  ),
                  const DropdownMenuItem(
                    value: 60,
                    child: Text('1 hour before'),
                  ),
                  const DropdownMenuItem(
                    value: 1440,
                    child: Text('1 day before'),
                  ),
                  if (![0, 15, 30, 60, 1440]
                      .contains(_remindBefore))
                    DropdownMenuItem(
                      value: _remindBefore,
                      child: Text(
                        '$_remindBefore minutes before',
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                  if (value != null) {
                    setState(() {
                      _remindBefore = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    _isEditing
                        ? 'Save changes'
                        : 'Save reminder',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
