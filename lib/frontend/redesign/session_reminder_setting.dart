import 'package:flutter/material.dart';

import '../../backend/services/device_session_reminders.dart';
import '../theme/app_theme.dart';

// Sprint 4 US6: the reminder opt-out on the Account settings page.

/// What the setting reads and changes; [AppReminderSettings] by default.
abstract class ReminderSettings {
  bool get supported;
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);

  /// Null when unknown.
  Future<bool?> notificationsEnabled();
  Future<bool> exactTiming();
  Future<void> requestExactTiming();
}

class AppReminderSettings implements ReminderSettings {
  const AppReminderSettings();
  @override
  bool get supported => sessionRemindersSupported;
  @override
  Future<bool> isEnabled() => AppSessionReminders.isEnabled();
  @override
  Future<void> setEnabled(bool enabled) =>
      AppSessionReminders.setEnabled(enabled);
  @override
  Future<bool?> notificationsEnabled() =>
      AppSessionReminders.scheduler.notificationsEnabled();
  @override
  Future<bool> exactTiming() =>
      AppSessionReminders.scheduler.canScheduleExact();
  @override
  Future<void> requestExactTiming() =>
      AppSessionReminders.scheduler.requestExact();
}

/// "Session reminders" switch (on by default). Hidden where reminders are not
/// available (web). Explains when the phone blocks notifications, and offers
/// exact timing when Android would otherwise deliver them approximately.
class SessionReminderSetting extends StatefulWidget {
  final ReminderSettings settings;
  const SessionReminderSetting({
    super.key,
    this.settings = const AppReminderSettings(),
  });

  static const title = 'Session reminders';
  static const subtitle = '1 hour and 10 minutes before each confirmed session';
  static const blocked =
      "Notifications are turned off for Ma'ak in your phone settings, so "
      'reminders cannot be shown.';
  static const approximate = 'Reminders may arrive a few minutes late.';

  @override
  State<SessionReminderSetting> createState() => _SessionReminderSettingState();
}

class _SessionReminderSettingState extends State<SessionReminderSetting> {
  bool? _enabled;
  bool? _notifications;
  bool _exact = true;
  bool _busy = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!widget.settings.supported) return;
    // Back from the phone's settings: show what changed there.
    _lifecycle = AppLifecycleListener(onResume: _load);
    _load();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = widget.settings;
    final enabled = await s.isEnabled();
    final notifications = await s.notificationsEnabled();
    final exact = await s.exactTiming();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _notifications = notifications;
      _exact = exact;
    });
  }

  Future<void> _change(bool value) async {
    setState(() {
      _busy = true;
      _enabled = value;
    });
    try {
      await widget.settings.setEnabled(value);
    } catch (_) {
      if (mounted) setState(() => _enabled = !value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.supported) return const SizedBox.shrink();
    final enabled = _enabled;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('session_reminders_switch'),
            secondary: const Icon(
              Icons.alarm_outlined,
              color: AppColors.primaryNavy,
            ),
            title: const Text(SessionReminderSetting.title),
            subtitle: const Text(SessionReminderSetting.subtitle),
            value: enabled ?? false,
            onChanged: enabled == null || _busy ? null : _change,
          ),
          if (enabled == true && _notifications == false)
            const _Note(SessionReminderSetting.blocked),
          if (enabled == true && _notifications != false && !_exact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    SessionReminderSetting.approximate,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  TextButton(
                    key: const ValueKey('session_reminders_exact'),
                    onPressed: widget.settings.requestExactTiming,
                    child: const Text('Allow exact timing'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
    ),
  );
}
