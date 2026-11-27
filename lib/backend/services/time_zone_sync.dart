import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Tells the database this device's UTC offset, so session notifications
/// (push and in-app) show times in the member's device time.
/// See supabase/migrations/20261127000000_session_notifications.sql.
///
/// Called when the member's app shell opens and whenever the app returns to
/// the foreground; it only calls the server when the offset or the signed-in
/// user changed. Failures are ignored: the server then uses Riyadh time.
class TimeZoneSync {
  TimeZoneSync._();

  /// "user id:offset" last saved by this app run.
  static String? _saved;

  static Future<void> sync() async {
    final user = SupabaseService.currentUser?.id;
    if (user == null) return;
    final minutes = DateTime.now().timeZoneOffset.inMinutes;
    // Same limits as set_maak_utc_offset.
    if (minutes < -720 || minutes > 840 || minutes % 15 != 0) return;
    final key = '$user:$minutes';
    if (key == _saved) return;
    try {
      await SupabaseService.client.rpc(
        'set_maak_utc_offset',
        params: {'p_minutes': minutes},
      );
      _saved = key;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TimeZoneSync: could not save offset (${error.runtimeType}).');
      }
    }
  }
}
