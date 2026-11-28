
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalReminderService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'personal_reminders';

  static String get _userId {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('User is not authenticated');
    }

    return user.id;
  }

  // Get personal reminders
  static Future<List<Map<String, dynamic>>> getReminders() async {
    final result = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .order('scheduled_at', ascending: true);

    return List<Map<String, dynamic>>.from(result);
  }

  // Create a personal reminder
  static Future<Map<String, dynamic>> createReminder({
    required String title,
    required String type,
    required DateTime scheduledAt,
    String notes = '',
    String repeatType = 'none',
    int remindBeforeMinutes = 0,
  }) async {
    final result = await _client
        .from(_table)
        .insert({
      'user_id': _userId,
      'title': title.trim(),
      'type': type,
      'notes': notes.trim(),
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'repeat_type': repeatType,
      'remind_before_minutes': remindBeforeMinutes,
    })
        .select()
        .single();

    return Map<String, dynamic>.from(result);
  }

  // Update a personal reminder
  static Future<Map<String, dynamic>> updateReminder({
    required String id,
    required String title,
    required String type,
    required DateTime scheduledAt,
    required String notes,
    required String repeatType,
    required int remindBeforeMinutes,
  }) async {
    final result = await _client
        .from(_table)
        .update({
      'title': title.trim(),
      'type': type,
      'notes': notes.trim(),
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'repeat_type': repeatType,
      'remind_before_minutes': remindBeforeMinutes,
    })
        .eq('id', id)
        .eq('user_id', _userId)
        .select()
        .single();

    return Map<String, dynamic>.from(result);
  }

  // Complete a reminder and generate its next occurrence
  static Future<Map<String, dynamic>> completeReminder(
      String id,
      ) async {
    final result = await _client.rpc(
      'complete_personal_reminder',
      params: {
        'p_reminder_id': id,
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  // Mark a reminder as completed or incomplete
  static Future<void> setCompleted({
    required String id,
    required bool isCompleted,
  }) async {
    if (isCompleted) {
      await completeReminder(id);
      return;
    }

    final reminder = await _client
        .from(_table)
        .select('repeat_type, series_id')
        .eq('id', id)
        .eq('user_id', _userId)
        .single();

    if (reminder['repeat_type'] != 'none' ||
        reminder['series_id'] != null) {
      throw StateError(
        'Recurring reminders require a separate restore operation',
      );
    }

    await _client
        .from(_table)
        .update({
      'is_completed': false,
      'completed_at': null,
    })
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id')
        .single();
  }

  // Delete a personal reminder

  // Delete a personal reminder or recurring series
  static Future<Map<String, dynamic>> deleteReminder(
      String id, {
        String scope = 'single',
      }) async {
    final result = await _client.rpc(
      'delete_personal_reminder',
      params: {
        'p_reminder_id': id,
        'p_scope': scope,
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }
}
